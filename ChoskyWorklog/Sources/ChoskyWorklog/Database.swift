import CSQLite
import Foundation

private let sqliteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)

final class WorklogDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    let url: URL

    init(
        url: URL = ProductConfig.databaseURL,
        migrateIfNeeded: Bool = true
    ) throws {
        self.url = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard sqlite3_open_v2(
            url.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            throw WorklogError.database("No se pudo abrir la base de datos.")
        }
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = FULL")
        try execute("PRAGMA busy_timeout = 5000")
        if migrateIfNeeded {
            try migrate()
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            applied_at REAL NOT NULL
        )
        """)
        let version = try scalarInt("SELECT COALESCE(MAX(version), 0) FROM schema_migrations")
        guard version <= ProductConfig.schemaVersion else {
            throw WorklogError.database(
                "La base de datos pertenece a una versión más reciente de la aplicación."
            )
        }
        if version < 1 {
            try transaction {
                for sql in Self.schemaV1 {
                    try execute(sql)
                }
                try seedDefaults()
                try run(
                    "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                    [.integer(1), .double(Date().timeIntervalSince1970)]
                )
            }
        } else {
            try seedDefaults()
        }
    }

    private func seedDefaults() throws {
        if try scalarInt("SELECT COUNT(*) FROM clients") > 0 { return }
        let client = ClientRecord(
            id: UUID(),
            name: ProductConfig.defaultClientName,
            color: "#5E5CE6",
            archived: false
        )
        try save(client: client)
        let projects = [
            "Gestión Nina", "VIP Guard", "MiniApp de Telegram", "Contenido",
            "Administración", "Desarrollo", "Personal"
        ]
        let projectRecords = projects.enumerated().map { index, name in
            ProjectRecord(
                id: UUID(),
                clientID: client.id,
                name: name,
                color: Self.defaultColors[index % Self.defaultColors.count],
                isBillable: name != "Personal",
                hourlyRate: nil,
                archived: false
            )
        }
        for project in projectRecords { try save(project: project) }
        let initialTasks = [
            "Edición de fotografías", "Selección de fotografías",
            "Organización de contenido", "Publicación de contenido",
            "Gestión de plataformas", "Gestión de redes sociales",
            "Mensajes y atención", "Bot de Telegram", "MiniApp de Telegram",
            "Desarrollo", "Corrección de errores", "Seguridad", "Mantenimiento",
            "Soporte técnico", "Planificación", "Reuniones", "Administración",
            "Otras tareas"
        ]
        for name in initialTasks {
            try save(task: TaskRecord(
                id: UUID(),
                projectID: nil,
                name: name,
                archived: false
            ))
        }
        try addAudit(
            entityType: "database",
            entityID: nil,
            action: "seed_defaults",
            oldValue: nil,
            newValue: "Nina, \(projects.count) proyectos, \(initialTasks.count) tareas",
            reason: "Instalación inicial",
            manual: false
        )
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func execute(_ sql: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(errorPointer)
            throw WorklogError.database(message)
        }
    }

    enum Value {
        case null
        case text(String)
        case integer(Int64)
        case double(Double)
    }

    private func run(_ sql: String, _ values: [Value] = []) throws {
        lock.lock()
        defer { lock.unlock() }
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw WorklogError.database(String(cString: sqlite3_errmsg(handle)))
        }
    }

    private func query(
        _ sql: String,
        _ values: [Value] = [],
        row: (OpaquePointer) throws -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                try row(statement)
            } else if result == SQLITE_DONE {
                break
            } else {
                throw WorklogError.database(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    private func scalarInt(_ sql: String) throws -> Int {
        var value = 0
        try query(sql) { statement in
            value = Int(sqlite3_column_int64(statement, 0))
        }
        return value
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw WorklogError.database(String(cString: sqlite3_errmsg(handle)))
        }
        return statement
    }

    private func bind(_ values: [Value], to statement: OpaquePointer) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32 = switch value {
            case .null:
                sqlite3_bind_null(statement, index)
            case let .text(string):
                sqlite3_bind_text(statement, index, string, -1, sqliteTransient)
            case let .integer(integer):
                sqlite3_bind_int64(statement, index, integer)
            case let .double(double):
                sqlite3_bind_double(statement, index, double)
            }
            guard result == SQLITE_OK else {
                throw WorklogError.database(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func uuid(_ statement: OpaquePointer, _ index: Int32) throws -> UUID {
        guard let string = text(statement, index), let value = UUID(uuidString: string) else {
            throw WorklogError.database("UUID inválido en la base de datos.")
        }
        return value
    }

    func clients(includeArchived: Bool = false) throws -> [ClientRecord] {
        var records: [ClientRecord] = []
        let suffix = includeArchived ? "" : " WHERE archived = 0"
        try query("SELECT id, name, color, archived FROM clients\(suffix) ORDER BY sort_order, name") {
            records.append(ClientRecord(
                id: try uuid($0, 0),
                name: text($0, 1) ?? "",
                color: text($0, 2) ?? "#5E5CE6",
                archived: sqlite3_column_int($0, 3) != 0
            ))
        }
        return records
    }

    func save(client: ClientRecord) throws {
        let name = try validated(client.name, field: "cliente", max: 200, required: true)
        try run("""
        INSERT INTO clients(id, name, color, archived)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name, color = excluded.color, archived = excluded.archived
        """, [
            .text(client.id.uuidString), .text(name), .text(client.color),
            .integer(client.archived ? 1 : 0)
        ])
    }

    func projects(clientID: UUID? = nil, includeArchived: Bool = false) throws -> [ProjectRecord] {
        var records: [ProjectRecord] = []
        var conditions: [String] = []
        var values: [Value] = []
        if let clientID {
            conditions.append("client_id = ?")
            values.append(.text(clientID.uuidString))
        }
        if !includeArchived { conditions.append("archived = 0") }
        let clause = conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")
        try query("""
        SELECT id, client_id, name, color, billable, hourly_rate, archived
        FROM projects\(clause) ORDER BY sort_order, name
        """, values) {
            records.append(ProjectRecord(
                id: try uuid($0, 0),
                clientID: try uuid($0, 1),
                name: text($0, 2) ?? "",
                color: text($0, 3) ?? "#5E5CE6",
                isBillable: sqlite3_column_int($0, 4) != 0,
                hourlyRate: text($0, 5).flatMap { Decimal(string: $0, locale: nil) },
                archived: sqlite3_column_int($0, 6) != 0
            ))
        }
        return records
    }

    func save(project: ProjectRecord) throws {
        let name = try validated(project.name, field: "proyecto", max: 200, required: true)
        try run("""
        INSERT INTO projects(id, client_id, name, color, billable, hourly_rate, archived)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            client_id = excluded.client_id, name = excluded.name,
            color = excluded.color, billable = excluded.billable,
            hourly_rate = excluded.hourly_rate, archived = excluded.archived
        """, [
            .text(project.id.uuidString), .text(project.clientID.uuidString),
            .text(name), .text(project.color), .integer(project.isBillable ? 1 : 0),
            project.hourlyRate.map { .text(NSDecimalNumber(decimal: $0).stringValue) } ?? .null,
            .integer(project.archived ? 1 : 0)
        ])
    }

    func tasks(projectID: UUID? = nil, includeArchived: Bool = false) throws -> [TaskRecord] {
        var records: [TaskRecord] = []
        var conditions: [String] = []
        var values: [Value] = []
        if let projectID {
            conditions.append("(project_id IS NULL OR project_id = ?)")
            values.append(.text(projectID.uuidString))
        }
        if !includeArchived { conditions.append("archived = 0") }
        let clause = conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")
        try query("SELECT id, project_id, name, archived FROM tasks\(clause) ORDER BY sort_order, name", values) {
            records.append(TaskRecord(
                id: try uuid($0, 0),
                projectID: text($0, 1).flatMap(UUID.init(uuidString:)),
                name: text($0, 2) ?? "",
                archived: sqlite3_column_int($0, 3) != 0
            ))
        }
        return records
    }

    func save(task: TaskRecord) throws {
        let name = try validated(task.name, field: "tarea", max: 200, required: true)
        try run("""
        INSERT INTO tasks(id, project_id, name, archived)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            project_id = excluded.project_id, name = excluded.name, archived = excluded.archived
        """, [
            .text(task.id.uuidString),
            task.projectID.map { .text($0.uuidString) } ?? .null,
            .text(name), .integer(task.archived ? 1 : 0)
        ])
    }

    func activeSession() throws -> SessionRecord? {
        try sessions(activeOnly: true, limit: 1).first
    }

    func sessions(activeOnly: Bool = false, limit: Int = 500) throws -> [SessionRecord] {
        var records: [SessionRecord] = []
        let clause = activeOnly
            ? " WHERE ended_at IS NULL AND state NOT IN ('finished', 'archived')"
            : ""
        try query("""
        SELECT id, client_id, project_id, task_id, description, tags, started_at,
               ended_at, state, timezone, billable, hourly_rate, active_seconds,
               afk_seconds, paused_seconds, suspended_seconds, screenshot_count,
               initial_note, expected_results, integrity_status, schema_version
        FROM work_sessions\(clause)
        ORDER BY started_at DESC LIMIT ?
        """, [.integer(Int64(max(1, min(limit, 5_000))))]) {
            let state = text($0, 8).flatMap(WorkSessionState.init(rawValue:)) ?? .recovering
            records.append(SessionRecord(
                id: try uuid($0, 0),
                clientID: try uuid($0, 1),
                projectID: try uuid($0, 2),
                taskID: try uuid($0, 3),
                description: text($0, 4) ?? "",
                tags: (text($0, 5) ?? "").split(separator: ",").map(String.init),
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double($0, 6)),
                endedAt: sqlite3_column_type($0, 7) == SQLITE_NULL
                    ? nil : Date(timeIntervalSince1970: sqlite3_column_double($0, 7)),
                state: state,
                timezone: text($0, 9) ?? ProductConfig.timezone.identifier,
                isBillable: sqlite3_column_int($0, 10) != 0,
                hourlyRate: text($0, 11).flatMap { Decimal(string: $0, locale: nil) },
                activeSeconds: sqlite3_column_double($0, 12),
                afkSeconds: sqlite3_column_double($0, 13),
                pausedSeconds: sqlite3_column_double($0, 14),
                suspendedSeconds: sqlite3_column_double($0, 15),
                screenshotCount: Int(sqlite3_column_int64($0, 16)),
                initialNote: text($0, 17) ?? "",
                expectedResults: text($0, 18) ?? "",
                integrityStatus: text($0, 19) ?? "valid",
                schemaVersion: Int(sqlite3_column_int64($0, 20))
            ))
        }
        return records
    }

    func save(session: SessionRecord) throws {
        try run("""
        INSERT INTO work_sessions(
            id, client_id, project_id, task_id, description, tags, started_at,
            ended_at, state, timezone, billable, hourly_rate, active_seconds,
            afk_seconds, paused_seconds, suspended_seconds, screenshot_count,
            initial_note, expected_results, integrity_status, schema_version
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            client_id = excluded.client_id, project_id = excluded.project_id,
            task_id = excluded.task_id, description = excluded.description,
            tags = excluded.tags, started_at = excluded.started_at,
            ended_at = excluded.ended_at, state = excluded.state,
            timezone = excluded.timezone, billable = excluded.billable,
            hourly_rate = excluded.hourly_rate, active_seconds = excluded.active_seconds,
            afk_seconds = excluded.afk_seconds, paused_seconds = excluded.paused_seconds,
            suspended_seconds = excluded.suspended_seconds,
            screenshot_count = excluded.screenshot_count,
            initial_note = excluded.initial_note,
            expected_results = excluded.expected_results,
            integrity_status = excluded.integrity_status,
            schema_version = excluded.schema_version
        """, [
            .text(session.id.uuidString), .text(session.clientID.uuidString),
            .text(session.projectID.uuidString), .text(session.taskID.uuidString),
            .text(try validated(session.description, field: "descripción", max: 4_000)),
            .text(try validated(
                session.tags.joined(separator: ","),
                field: "etiquetas",
                max: 4_000
            )),
            .double(session.startedAt.timeIntervalSince1970),
            session.endedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            .text(session.state.rawValue), .text(session.timezone),
            .integer(session.isBillable ? 1 : 0),
            session.hourlyRate.map { .text(NSDecimalNumber(decimal: $0).stringValue) } ?? .null,
            .double(session.activeSeconds), .double(session.afkSeconds),
            .double(session.pausedSeconds), .double(session.suspendedSeconds),
            .integer(Int64(session.screenshotCount)),
            .text(try validated(session.initialNote, field: "nota", max: 10_000)),
            .text(try validated(session.expectedResults, field: "resultados esperados", max: 10_000)),
            .text(session.integrityStatus), .integer(Int64(session.schemaVersion))
        ])
    }

    func addSegment(
        sessionID: UUID,
        state: WorkSessionState,
        startedAt: Date,
        endedAt: Date? = nil,
        reason: String? = nil
    ) throws {
        try run("""
        INSERT INTO session_segments(id, session_id, state, started_at, ended_at, reason)
        VALUES (?, ?, ?, ?, ?, ?)
        """, [
            .text(UUID().uuidString), .text(sessionID.uuidString), .text(state.rawValue),
            .double(startedAt.timeIntervalSince1970),
            endedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            reason.map(Value.text) ?? .null
        ])
    }

    func closeOpenSegment(sessionID: UUID, endedAt: Date = Date()) throws {
        try run("""
        UPDATE session_segments SET ended_at = ?
        WHERE id = (
            SELECT id FROM session_segments
            WHERE session_id = ? AND ended_at IS NULL
            ORDER BY started_at DESC LIMIT 1
        )
        """, [.double(endedAt.timeIntervalSince1970), .text(sessionID.uuidString)])
    }

    func save(screenshot: ScreenshotRecord) throws {
        try run("""
        INSERT INTO screenshots(
            id, session_id, captured_at, relative_path, thumbnail_path, sha256,
            display_id, width, height, scale, active_application, active_window,
            included, deleted_at, note
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            .text(screenshot.id.uuidString), .text(screenshot.sessionID.uuidString),
            .double(screenshot.capturedAt.timeIntervalSince1970),
            .text(screenshot.relativePath),
            screenshot.thumbnailPath.map(Value.text) ?? .null,
            .text(screenshot.sha256), .integer(Int64(screenshot.displayID)),
            .integer(Int64(screenshot.width)), .integer(Int64(screenshot.height)),
            .double(screenshot.scale),
            screenshot.activeApplication.map(Value.text) ?? .null,
            screenshot.activeWindow.map(Value.text) ?? .null,
            .integer(screenshot.included ? 1 : 0),
            screenshot.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            .text(screenshot.note)
        ])
    }

    func screenshots(sessionID: UUID? = nil, limit: Int = 1_000) throws -> [ScreenshotRecord] {
        var records: [ScreenshotRecord] = []
        let clause = sessionID == nil ? "" : " WHERE session_id = ?"
        var values: [Value] = sessionID.map { [.text($0.uuidString)] } ?? []
        values.append(.integer(Int64(max(1, min(limit, 10_000)))))
        try query("""
        SELECT id, session_id, captured_at, relative_path, thumbnail_path, sha256,
               display_id, width, height, scale, active_application, active_window,
               included, deleted_at, note
        FROM screenshots\(clause) ORDER BY captured_at DESC LIMIT ?
        """, values) {
            records.append(ScreenshotRecord(
                id: try uuid($0, 0),
                sessionID: try uuid($0, 1),
                capturedAt: Date(timeIntervalSince1970: sqlite3_column_double($0, 2)),
                relativePath: text($0, 3) ?? "",
                thumbnailPath: text($0, 4),
                sha256: text($0, 5) ?? "",
                displayID: UInt32(sqlite3_column_int64($0, 6)),
                width: Int(sqlite3_column_int64($0, 7)),
                height: Int(sqlite3_column_int64($0, 8)),
                scale: sqlite3_column_double($0, 9),
                activeApplication: text($0, 10),
                activeWindow: text($0, 11),
                included: sqlite3_column_int($0, 12) != 0,
                deletedAt: sqlite3_column_type($0, 13) == SQLITE_NULL
                    ? nil : Date(timeIntervalSince1970: sqlite3_column_double($0, 13)),
                note: text($0, 14) ?? ""
            ))
        }
        return records
    }

    func markScreenshotDeleted(id: UUID, date: Date = Date()) throws {
        try run(
            "UPDATE screenshots SET deleted_at = ?, included = 0 WHERE id = ?",
            [.double(date.timeIntervalSince1970), .text(id.uuidString)]
        )
    }

    func addDeliverable(sessionID: UUID, title: String, details: String, link: String?) throws {
        try run("""
        INSERT INTO deliverables(id, session_id, title, details, link, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """, [
            .text(UUID().uuidString), .text(sessionID.uuidString),
            .text(try validated(title, field: "resultado", max: 500, required: true)),
            .text(try validated(details, field: "detalle", max: 10_000)),
            link.map(Value.text) ?? .null,
            .double(Date().timeIntervalSince1970)
        ])
    }

    func deliverables(sessionID: UUID) throws -> [DeliverableRecord] {
        var records: [DeliverableRecord] = []
        try query("""
        SELECT id, session_id, title, details, link, created_at
        FROM deliverables WHERE session_id = ? ORDER BY created_at
        """, [.text(sessionID.uuidString)]) {
            records.append(DeliverableRecord(
                id: try uuid($0, 0),
                sessionID: try uuid($0, 1),
                title: text($0, 2) ?? "",
                details: text($0, 3) ?? "",
                link: text($0, 4),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double($0, 5))
            ))
        }
        return records
    }

    func addAudit(
        entityType: String,
        entityID: UUID?,
        action: String,
        oldValue: String?,
        newValue: String?,
        reason: String?,
        manual: Bool
    ) throws {
        try run("""
        INSERT INTO audit_log(
            id, occurred_at, entity_type, entity_id, action, old_value,
            new_value, reason, manual, device_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            .text(UUID().uuidString), .double(Date().timeIntervalSince1970),
            .text(entityType), entityID.map { .text($0.uuidString) } ?? .null,
            .text(action), oldValue.map(Value.text) ?? .null,
            newValue.map(Value.text) ?? .null, reason.map(Value.text) ?? .null,
            .integer(manual ? 1 : 0), .text(Self.deviceID)
        ])
    }

    func auditEntries(limit: Int = 500) throws -> [AuditEntry] {
        var records: [AuditEntry] = []
        try query("""
        SELECT id, occurred_at, entity_type, entity_id, action, old_value,
               new_value, reason, manual, device_id
        FROM audit_log ORDER BY occurred_at DESC LIMIT ?
        """, [.integer(Int64(max(1, min(limit, 5_000))))]) {
            records.append(AuditEntry(
                id: try uuid($0, 0),
                occurredAt: Date(timeIntervalSince1970: sqlite3_column_double($0, 1)),
                entityType: text($0, 2) ?? "",
                entityID: text($0, 3).flatMap(UUID.init(uuidString:)),
                action: text($0, 4) ?? "",
                oldValue: text($0, 5),
                newValue: text($0, 6),
                reason: text($0, 7),
                manual: sqlite3_column_int($0, 8) != 0,
                deviceID: text($0, 9) ?? ""
            ))
        }
        return records
    }

    func setSetting(_ key: String, value: String) throws {
        try run("""
        INSERT INTO settings(key, value, updated_at) VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
        """, [.text(key), .text(value), .double(Date().timeIntervalSince1970)])
    }

    func setting(_ key: String) throws -> String? {
        var result: String?
        try query("SELECT value FROM settings WHERE key = ?", [.text(key)]) {
            result = text($0, 0)
        }
        return result
    }

    func integrityCheck() throws -> String {
        var result = "unknown"
        try query("PRAGMA integrity_check") { result = text($0, 0) ?? "unknown" }
        return result
    }

    func checkpoint() throws {
        try execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    func migrationVersion() throws -> Int {
        try scalarInt("SELECT COALESCE(MAX(version), 0) FROM schema_migrations")
    }

    private func validated(
        _ value: String,
        field: String,
        max: Int,
        required: Bool = false
    ) throws -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if required, cleaned.isEmpty {
            throw WorklogError.invalidInput("El campo \(field) no puede estar vacío.")
        }
        guard cleaned.count <= max else {
            throw WorklogError.invalidInput("El campo \(field) supera \(max) caracteres.")
        }
        return cleaned
    }

    private static let deviceID: String = {
        Host.current().localizedName ?? "Mac"
    }()

    private static let defaultColors = [
        "#5E5CE6", "#0A84FF", "#30D158", "#FF9F0A",
        "#FF375F", "#64D2FF", "#BF5AF2"
    ]

    private static let schemaV1 = [
        """
        CREATE TABLE clients (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, color TEXT NOT NULL,
            archived INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL DEFAULT (unixepoch())
        )
        """,
        """
        CREATE TABLE projects (
            id TEXT PRIMARY KEY, client_id TEXT NOT NULL REFERENCES clients(id),
            name TEXT NOT NULL, color TEXT NOT NULL, billable INTEGER NOT NULL DEFAULT 1,
            hourly_rate TEXT, archived INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0, created_at REAL NOT NULL DEFAULT (unixepoch())
        )
        """,
        """
        CREATE TABLE tasks (
            id TEXT PRIMARY KEY, project_id TEXT REFERENCES projects(id),
            name TEXT NOT NULL, archived INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0, created_at REAL NOT NULL DEFAULT (unixepoch())
        )
        """,
        "CREATE TABLE tags (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, color TEXT)",
        """
        CREATE TABLE project_tags (
            project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
            PRIMARY KEY(project_id, tag_id)
        )
        """,
        """
        CREATE TABLE work_sessions (
            id TEXT PRIMARY KEY, client_id TEXT NOT NULL REFERENCES clients(id),
            project_id TEXT NOT NULL REFERENCES projects(id), task_id TEXT NOT NULL REFERENCES tasks(id),
            description TEXT NOT NULL DEFAULT '', tags TEXT NOT NULL DEFAULT '',
            started_at REAL NOT NULL, ended_at REAL, state TEXT NOT NULL, timezone TEXT NOT NULL,
            billable INTEGER NOT NULL DEFAULT 1, hourly_rate TEXT,
            active_seconds REAL NOT NULL DEFAULT 0, afk_seconds REAL NOT NULL DEFAULT 0,
            paused_seconds REAL NOT NULL DEFAULT 0, suspended_seconds REAL NOT NULL DEFAULT 0,
            screenshot_count INTEGER NOT NULL DEFAULT 0, initial_note TEXT NOT NULL DEFAULT '',
            expected_results TEXT NOT NULL DEFAULT '', integrity_status TEXT NOT NULL DEFAULT 'valid',
            schema_version INTEGER NOT NULL
        )
        """,
        """
        CREATE UNIQUE INDEX one_active_session ON work_sessions((1))
        WHERE ended_at IS NULL AND state NOT IN ('finished', 'archived')
        """,
        "CREATE INDEX sessions_started_at ON work_sessions(started_at)",
        "CREATE INDEX sessions_project ON work_sessions(project_id, started_at)",
        """
        CREATE TABLE session_segments (
            id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES work_sessions(id) ON DELETE CASCADE,
            state TEXT NOT NULL, started_at REAL NOT NULL, ended_at REAL, reason TEXT
        )
        """,
        "CREATE INDEX segments_session_time ON session_segments(session_id, started_at)",
        """
        CREATE TABLE pauses (
            id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES work_sessions(id) ON DELETE CASCADE,
            kind TEXT NOT NULL, started_at REAL NOT NULL, ended_at REAL, reason TEXT
        )
        """,
        """
        CREATE TABLE afk_periods (
            id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES work_sessions(id) ON DELETE CASCADE,
            started_at REAL NOT NULL, ended_at REAL, source TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE screenshots (
            id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES work_sessions(id) ON DELETE RESTRICT,
            captured_at REAL NOT NULL, relative_path TEXT NOT NULL UNIQUE, thumbnail_path TEXT,
            sha256 TEXT NOT NULL, display_id INTEGER NOT NULL, width INTEGER NOT NULL,
            height INTEGER NOT NULL, scale REAL NOT NULL, active_application TEXT,
            active_window TEXT, included INTEGER NOT NULL DEFAULT 1, deleted_at REAL,
            note TEXT NOT NULL DEFAULT ''
        )
        """,
        "CREATE INDEX screenshots_session_time ON screenshots(session_id, captured_at)",
        """
        CREATE TABLE screenshot_files (
            id TEXT PRIMARY KEY, screenshot_id TEXT NOT NULL REFERENCES screenshots(id) ON DELETE CASCADE,
            relative_path TEXT NOT NULL, kind TEXT NOT NULL, bytes INTEGER NOT NULL, sha256 TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE activity_links (
            id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES work_sessions(id) ON DELETE CASCADE,
            bucket_id TEXT NOT NULL, event_id TEXT, started_at REAL NOT NULL, ended_at REAL,
            project_id TEXT, task_id TEXT
        )
        """,
        """
        CREATE TABLE application_rules (
            id TEXT PRIMARY KEY, bundle_id TEXT, app_name TEXT, title_pattern TEXT,
            category TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1, priority INTEGER NOT NULL DEFAULT 0
        )
        """,
        """
        CREATE TABLE domain_rules (
            id TEXT PRIMARY KEY, domain_pattern TEXT NOT NULL, url_pattern TEXT,
            category TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1, priority INTEGER NOT NULL DEFAULT 0
        )
        """,
        """
        CREATE TABLE manual_adjustments (
            id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES work_sessions(id) ON DELETE CASCADE,
            field TEXT NOT NULL, old_value TEXT, new_value TEXT, reason TEXT NOT NULL,
            occurred_at REAL NOT NULL, device_id TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE audit_log (
            id TEXT PRIMARY KEY, occurred_at REAL NOT NULL, entity_type TEXT NOT NULL,
            entity_id TEXT, action TEXT NOT NULL, old_value TEXT, new_value TEXT,
            reason TEXT, manual INTEGER NOT NULL, device_id TEXT NOT NULL
        )
        """,
        "CREATE INDEX audit_time ON audit_log(occurred_at)",
        """
        CREATE TABLE deliverables (
            id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES work_sessions(id) ON DELETE CASCADE,
            title TEXT NOT NULL, details TEXT NOT NULL DEFAULT '', link TEXT, created_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE rates (
            id TEXT PRIMARY KEY, client_id TEXT REFERENCES clients(id), project_id TEXT REFERENCES projects(id),
            kind TEXT NOT NULL, amount TEXT NOT NULL, currency TEXT NOT NULL,
            valid_from REAL, valid_until REAL
        )
        """,
        """
        CREATE TABLE reports (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at REAL NOT NULL,
            start_at REAL NOT NULL, end_at REAL NOT NULL, format TEXT NOT NULL,
            relative_path TEXT NOT NULL, manifest_hash TEXT, protected INTEGER NOT NULL DEFAULT 0
        )
        """,
        """
        CREATE TABLE report_items (
            report_id TEXT NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
            entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
            PRIMARY KEY(report_id, entity_type, entity_id)
        )
        """,
        """
        CREATE TABLE share_profiles (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, permissions_json TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 0, created_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE share_tokens (
            id TEXT PRIMARY KEY, profile_id TEXT REFERENCES share_profiles(id) ON DELETE CASCADE,
            token_hash TEXT NOT NULL UNIQUE, created_at REAL NOT NULL, expires_at REAL NOT NULL,
            revoked_at REAL, last_access_at REAL
        )
        """,
        """
        CREATE TABLE share_access_log (
            id TEXT PRIMARY KEY, token_id TEXT, occurred_at REAL NOT NULL, remote_address TEXT,
            action TEXT NOT NULL, allowed INTEGER NOT NULL, detail TEXT
        )
        """,
        "CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at REAL NOT NULL)"
    ]
}
