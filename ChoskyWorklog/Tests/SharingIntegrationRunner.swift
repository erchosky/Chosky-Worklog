import Foundation

private struct SharingFailure: Error, CustomStringConvertible {
    let description: String
}

@main
@MainActor
struct SharingIntegrationRunner {
    static func main() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("chosky-sharing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let database = try WorklogDatabase(url: temporary.appendingPathComponent("worklog.sqlite3"))
        guard let client = try database.clients().first,
              let project = try database.projects(clientID: client.id).first,
              let task = try database.tasks(projectID: project.id).first
        else {
            throw SharingFailure(description: "Faltan datos iniciales")
        }
        var finished = makeSession(client: client, project: project, task: task)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ProductConfig.timezone
        let now = Date()
        let today = calendar.startOfDay(for: now)
        finished.startedAt = max(today, now.addingTimeInterval(-120))
        finished.endedAt = max(finished.startedAt.addingTimeInterval(1), now.addingTimeInterval(-60))
        finished.state = .finished
        try database.save(session: finished)
        let active = makeSession(client: client, project: project, task: task)
        try database.save(session: active)
        let sharing = SharingServer(database: database)
        sharing.localOnly = true
        sharing.permissions.liveTimer = false
        sharing.permissions.finishedSessions = true
        sharing.permissions.todaySummary = true
        sharing.permissions.oldHistory = false
        sharing.enable(expirationHours: 1)

        var ready = false
        for _ in 0..<30 {
            if sharing.status == "Solo este Mac" {
                ready = true
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        try expect(ready, "El listener no quedó listo: \(sharing.lastError ?? "sin detalle")")
        let url = try unwrap(sharing.shareURL, "No se generó enlace")
        print("✓ listener local y token temporal")

        let (data, response) = try await URLSession.shared.data(from: url)
        try expect((response as? HTTPURLResponse)?.statusCode == 200, "El panel no respondió 200")
        let html = String(decoding: data, as: UTF8.self)
        try expect(html.contains("solo lectura"), "El panel no identifica el acceso de solo lectura")
        try expect(html.contains("data-kind=\"finished\""), "No mostró la sesión finalizada autorizada")
        try expect(!html.contains("data-kind=\"active\""), "Mostró el cronómetro sin permiso")
        try expect(sharing.lastAccess != nil, "No se registró el acceso")
        sharing.permissions.liveTimer = true
        sharing.permissions.finishedSessions = false
        let (activeData, activeResponse) = try await URLSession.shared.data(from: url)
        let activeHTML = String(decoding: activeData, as: UTF8.self)
        try expect((activeResponse as? HTTPURLResponse)?.statusCode == 200, "El panel no respondió 200")
        try expect(activeHTML.contains("data-kind=\"active\""), "No mostró el cronómetro autorizado")
        try expect(!activeHTML.contains("data-kind=\"finished\""), "Mostró sesiones finalizadas sin permiso")
        print("✓ panel autenticado respeta permisos de datos")

        sharing.revokeAll()
        try expect(!sharing.masterEnabled && sharing.shareURL == nil, "La revocación no limpió estado")
        var oldLinkWorks = false
        do {
            let (_, oldResponse) = try await URLSession.shared.data(from: url)
            oldLinkWorks = (oldResponse as? HTTPURLResponse)?.statusCode == 200
        } catch {
            oldLinkWorks = false
        }
        try expect(!oldLinkWorks, "El enlace antiguo continúa funcionando")
        print("✓ revocación cierra listener e invalida enlace")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw SharingFailure(description: message) }
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw SharingFailure(description: message) }
        return value
    }

    private static func makeSession(
        client: ClientRecord,
        project: ProjectRecord,
        task: TaskRecord
    ) -> SessionRecord {
        SessionRecord(
            id: UUID(), clientID: client.id, projectID: project.id, taskID: task.id,
            description: "Compartición", tags: [], startedAt: Date(), endedAt: nil,
            state: .running, timezone: ProductConfig.timezone.identifier,
            isBillable: false, hourlyRate: nil, activeSeconds: 120,
            afkSeconds: 0, pausedSeconds: 0, suspendedSeconds: 0,
            screenshotCount: 0, initialNote: "", expectedResults: "",
            integrityStatus: "test", schemaVersion: ProductConfig.schemaVersion
        )
    }
}
