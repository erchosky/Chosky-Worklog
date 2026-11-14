import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@main
@MainActor
struct TestRunner {
    private static var passed = 0
    private static var failed = 0

    static func main() {
        run("máquina de estados") {
            try expect(WorkSessionState.prepared.canTransition(to: .running))
            try expect(WorkSessionState.running.canTransition(to: .manuallyPaused))
            try expect(!WorkSessionState.prepared.canTransition(to: .finished))
            try expect(!WorkSessionState.finished.canTransition(to: .running))
            try expect(!WorkSessionState.archived.canTransition(to: .running))
        }
        run("migración y datos iniciales") {
            try withFixture { fixture in
                try expect(try fixture.database.clients().map(\.name) == ["Nina"])
                try expect(try fixture.database.projects().count == 7)
                try expect(try fixture.database.tasks().count == 18)
                try expect(try fixture.database.integrityCheck() == "ok")
                var emptyNameRejected = false
                do {
                    try fixture.database.save(client: ClientRecord(
                        id: UUID(), name: "   ", color: "#000000", archived: false
                    ))
                } catch {
                    emptyNameRejected = true
                }
                try expect(emptyNameRejected, "SQLite aceptó un cliente sin nombre")
            }
        }
        run("sesión activa única") {
            try withFixture { fixture in
                let first = try fixture.makeSession()
                try fixture.database.save(session: first)
                let second = try fixture.makeSession()
                var rejected = false
                do {
                    try fixture.database.save(session: second)
                } catch {
                    rejected = true
                }
                try expect(rejected, "SQLite permitió dos sesiones activas")
                var finished = first
                finished.state = .finished
                finished.endedAt = Date()
                try fixture.database.save(session: finished)
                try fixture.database.save(session: second)
            }
        }
        run("aleatoriedad de capturas") {
            var generator = SystemRandomNumberGenerator()
            var values = Set<Int>()
            for _ in 0..<200 {
                let value = ScreenshotService.randomIntervalSeconds(
                    minimumMinutes: 8,
                    maximumMinutes: 18,
                    using: &generator
                )
                try expect(value >= 8 * 60)
                try expect(value <= 18 * 60)
                values.insert(Int(value))
            }
            try expect(values.count > 1, "La secuencia aleatoria no varió")
        }
        run("relaciones de sesión y persistencia del último intervalo") {
            try withFixture { fixture in
                guard let client = try fixture.database.clients().first,
                      let project = try fixture.database.projects(clientID: client.id).first,
                      let task = try fixture.database.tasks(projectID: project.id).first
                else {
                    throw TestFailure(description: "Faltan datos iniciales")
                }
                let otherClient = ClientRecord(
                    id: UUID(), name: "Otro cliente", color: "#000000", archived: false
                )
                try fixture.database.save(client: otherClient)
                let otherProject = ProjectRecord(
                    id: UUID(), clientID: otherClient.id, name: "Otro proyecto",
                    color: "#000000", isBillable: false, hourlyRate: nil, archived: false
                )
                try fixture.database.save(project: otherProject)
                let manager = SessionManager(database: fixture.database)
                manager.start(SessionDraft(
                    clientID: client.id,
                    projectID: otherProject.id,
                    taskID: task.id,
                    screenshotsEnabled: false
                ))
                try expect(manager.activeSession == nil, "Se aceptó un proyecto de otro cliente")

                manager.start(SessionDraft(
                    clientID: client.id,
                    projectID: project.id,
                    taskID: task.id,
                    screenshotsEnabled: false
                ))
                try expect(manager.activeSession != nil, "No se pudo iniciar una sesión válida")
                manager.createClient(name: "Cliente durante sesión")
                try expect(
                    manager.activeSession?.state == .running && manager.recoverySession == nil,
                    "Recargar catálogos convirtió una sesión viva en recuperación"
                )
                Thread.sleep(forTimeInterval: 1.1)
                manager.pause()
                try expect(
                    (manager.activeSession?.activeSeconds ?? 0) >= 1,
                    "La pausa perdió el último intervalo activo"
                )
                manager.finish()
            }
        }
        run("detección local de inactividad AFK") {
            try withFixture { fixture in
                guard let client = try fixture.database.clients().first,
                      let project = try fixture.database.projects(clientID: client.id).first,
                      let task = try fixture.database.tasks(projectID: project.id).first
                else {
                    throw TestFailure(description: "Faltan datos iniciales")
                }
                var idleSeconds: TimeInterval = 0
                let manager = SessionManager(
                    database: fixture.database,
                    idleSecondsProvider: { idleSeconds }
                )
                manager.start(SessionDraft(
                    clientID: client.id,
                    projectID: project.id,
                    taskID: task.id,
                    screenshotsEnabled: false
                ))
                idleSeconds = ProductConfig.afkThresholdSeconds + 1
                manager.processTick()
                try expect(manager.activeSession?.state == .afk, "No se detectó el estado AFK")
                idleSeconds = 0
                manager.processTick()
                try expect(manager.activeSession?.state == .running, "No se detectó el regreso de AFK")
                manager.finish()
            }
        }
        run("PDF, HTML, CSV, JSON, ZIP y manifiesto") {
            try withFixture { fixture in
                var session = try fixture.makeSession()
                let rangeStart = Date()
                session.startedAt = rangeStart.addingTimeInterval(-60)
                session.endedAt = rangeStart.addingTimeInterval(60)
                session.state = .finished
                session.description = "=HYPERLINK(\"https://invalid.example\")"
                session.activeSeconds = 120
                session.pausedSeconds = 30
                session.hourlyRate = 125
                try fixture.database.save(session: session)
                let exporter = ReportExporter(
                    database: fixture.database,
                    outputRoot: fixture.temporary.appendingPathComponent("reports")
                )
                let result = try exporter.export(options: ReportOptions(
                    startDate: rangeStart,
                    endDate: rangeStart.addingTimeInterval(3_600)
                ))
                try expect(
                    FileManager.default.fileExists(atPath: result.zip.path),
                    "No se creó el ZIP"
                )
                let prefix = String(
                    data: try Data(contentsOf: result.pdf).prefix(4),
                    encoding: .ascii
                )
                try expect(prefix == "%PDF", "El PDF no tiene una cabecera válida")
                let html = try String(contentsOf: result.html, encoding: .utf8)
                try expect(
                    html.contains("no son una puntuación de productividad"),
                    "El HTML no contiene el aviso de métricas"
                )
                let manifest = try String(contentsOf: result.manifest, encoding: .utf8)
                try expect(manifest.contains("sha256"), "El manifiesto no contiene hashes")
                try expect(
                    manifest.contains(session.id.uuidString),
                    "El manifiesto no referencia la sesión exportada"
                )
                let json = try String(contentsOf: result.json, encoding: .utf8)
                try expect(!json.contains("hourlyRate"), "El JSON expuso una tarifa no autorizada")
                let csv = try String(contentsOf: result.csv, encoding: .utf8)
                try expect(csv.contains("\"'=HYPERLINK"), "El CSV permitió una fórmula ejecutable")
                var invalidRangeRejected = false
                do {
                    _ = try exporter.export(options: ReportOptions(
                        startDate: rangeStart,
                        endDate: rangeStart.addingTimeInterval(-1)
                    ))
                } catch {
                    invalidRangeRejected = true
                }
                try expect(invalidRangeRejected, "Se aceptó un intervalo de informe invertido")
            }
        }
        run("backup y restauración limpia") {
            try withFixture { fixture in
                try fixture.database.save(session: fixture.makeSession())
                let manager = BackupManager(
                    database: fixture.database,
                    outputRoot: fixture.temporary.appendingPathComponent("backups")
                )
                let backup = try manager.create(includeScreenshots: false)
                let verified = try BackupManager.verifyRestore(
                    archive: backup.archive,
                    expectedChecksum: backup.checksum
                )
                try expect(verified == backup.checksum)
            }
        }

        print("\nResultado: \(passed) aprobadas, \(failed) fallidas")
        if failed > 0 {
            exit(1)
        }
    }

    private static func run(_ name: String, body: () throws -> Void) {
        do {
            try body()
            passed += 1
            print("✓ \(name)")
        } catch {
            failed += 1
            print("✗ \(name): \(error)")
        }
    }

    private static func expect(
        _ condition: @autoclosure () throws -> Bool,
        _ message: String = "La condición no se cumplió"
    ) throws {
        if try !condition() {
            throw TestFailure(description: message)
        }
    }

    private static func withFixture(_ body: (Fixture) throws -> Void) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try body(fixture)
    }
}

private struct Fixture {
    let temporary: URL
    let database: WorklogDatabase

    init() throws {
        temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("chosky-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        database = try WorklogDatabase(url: temporary.appendingPathComponent("worklog.sqlite3"))
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: temporary)
    }

    func makeSession() throws -> SessionRecord {
        guard let client = try database.clients().first,
              let project = try database.projects(clientID: client.id).first,
              let task = try database.tasks(projectID: project.id).first
        else {
            throw TestFailure(description: "Faltan datos iniciales")
        }
        return SessionRecord(
            id: UUID(),
            clientID: client.id,
            projectID: project.id,
            taskID: task.id,
            description: "Prueba",
            tags: [],
            startedAt: Date(),
            endedAt: nil,
            state: .running,
            timezone: "Europe/Madrid",
            isBillable: true,
            hourlyRate: nil,
            activeSeconds: 0,
            afkSeconds: 0,
            pausedSeconds: 0,
            suspendedSeconds: 0,
            screenshotCount: 0,
            initialNote: "",
            expectedResults: "",
            integrityStatus: "valid",
            schemaVersion: 1
        )
    }
}
