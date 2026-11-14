import Foundation

private struct IntegrationFailure: Error, CustomStringConvertible {
    let description: String
}

@main
@MainActor
struct IntegrationRunner {
    static func main() async throws {
        try ProductConfig.prepareDirectories()
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("chosky-integration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let database = try WorklogDatabase(url: temporary.appendingPathComponent("worklog.sqlite3"))
        let supervisor = ActivityWatchSupervisor(database: database)
        supervisor.startServer()
        var ready = false
        for _ in 0..<40 {
            if await supervisor.healthCheck() {
                ready = true
                break
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        try expect(
            ready,
            "ActivityWatch no arrancó: \(supervisor.lastError ?? "sin detalle")"
        )
        print("✓ servidor ActivityWatch responde")

        guard let client = try database.clients().first,
              let project = try database.projects(clientID: client.id).first,
              let task = try database.tasks(projectID: project.id).first
        else {
            throw IntegrationFailure(description: "Faltan datos iniciales")
        }
        let session = SessionRecord(
            id: UUID(),
            clientID: client.id,
            projectID: project.id,
            taskID: task.id,
            description: "Integración",
            tags: [],
            startedAt: Date(),
            endedAt: nil,
            state: .running,
            timezone: ProductConfig.timezone.identifier,
            isBillable: false,
            hourlyRate: nil,
            activeSeconds: 0,
            afkSeconds: 0,
            pausedSeconds: 0,
            suspendedSeconds: 0,
            screenshotCount: 0,
            initialNote: "",
            expectedResults: "",
            integrityStatus: "test",
            schemaVersion: 1
        )
        try database.save(session: session)
        supervisor.sessionDidStart(session)
        try await Task.sleep(for: .seconds(12))
        try expect(supervisor.watcherPIDs.count == 2, "No se iniciaron ambos watchers")
        print("✓ watchers AFK y ventana supervisados")

        let buckets = try await fetchBuckets()
        try expect(
            buckets.contains(where: { $0.hasPrefix("aw-watcher-worksession_") }),
            "No se creó el bucket correlacionado de sesión"
        )
        try expect(
            buckets.contains(where: { $0.hasPrefix("aw-watcher-afk_") }),
            "No se creó el bucket AFK"
        )
        try expect(
            buckets.contains(where: { $0.hasPrefix("aw-watcher-window_") }),
            "No se creó el bucket de ventana"
        )
        print("✓ buckets de sesión, AFK y ventana presentes")

        var paused = session
        paused.state = .manuallyPaused
        supervisor.sessionDidPause(paused)
        try await Task.sleep(for: .seconds(3))
        try expect(supervisor.watcherPIDs.isEmpty, "Los watchers no pararon al pausar")
        print("✓ pausa estricta detiene watchers")

        supervisor.restart()
        for _ in 0..<40 {
            if await supervisor.healthCheck() { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        try await Task.sleep(for: .seconds(2))
        try expect(
            supervisor.watcherPIDs.isEmpty,
            "Reiniciar el motor reactivó watchers durante una pausa"
        )
        print("✓ reinicio durante pausa conserva el modo estricto")

        supervisor.continuousMode = true
        try await Task.sleep(for: .seconds(3))
        try expect(supervisor.watcherPIDs.count == 2, "El modo continuo no inició watchers")
        supervisor.continuousMode = false
        try await Task.sleep(for: .seconds(3))
        try expect(supervisor.watcherPIDs.isEmpty, "Al salir del modo continuo quedaron watchers")
        print("✓ cambio de modo continuo aplica inmediatamente")

        supervisor.stopAll()
        try await Task.sleep(for: .seconds(3))
        supervisor.sessionDidStart(session)
        supervisor.sessionDidPause(paused)
        for _ in 0..<40 {
            if await supervisor.healthCheck() { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        try await Task.sleep(for: .seconds(2))
        try expect(
            supervisor.watcherPIDs.isEmpty,
            "Una pausa durante el arranque dejó watchers activos"
        )
        print("✓ pausa durante arranque no reactiva watchers")

        supervisor.sessionDidFinish(paused)
        supervisor.stopAll()
        try await Task.sleep(for: .seconds(3))
        let stillHealthy = await supervisor.healthCheck()
        try expect(!stillHealthy, "El servidor sigue escuchando tras cerrar")
        print("✓ cierre completo libera el puerto")
    }

    private static func fetchBuckets() async throws -> [String] {
        let url = URL(string: "http://127.0.0.1:\(ProductConfig.activityWatchPort)/api/0/buckets")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw IntegrationFailure(description: "Respuesta de buckets no válida")
        }
        return Array(object.keys)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw IntegrationFailure(description: message)
        }
    }
}
