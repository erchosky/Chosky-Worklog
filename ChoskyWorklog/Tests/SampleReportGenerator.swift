import Foundation

@main
@MainActor
struct SampleReportGenerator {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { exit(2) }
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let workspace = destination.appendingPathComponent(".generator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let database = try WorklogDatabase(url: workspace.appendingPathComponent("sample.sqlite3"))
        guard let client = try database.clients().first,
              let project = try database.projects(clientID: client.id).first,
              let task = try database.tasks(projectID: project.id).first
        else {
            throw WorklogError.database("No se pudieron crear los datos de ejemplo.")
        }
        let end = Date()
        let start = end.addingTimeInterval(-3_600)
        try database.save(session: SessionRecord(
            id: UUID(),
            clientID: client.id,
            projectID: project.id,
            taskID: task.id,
            description: "EJEMPLO — sesión demostrativa, no corresponde a trabajo real",
            tags: ["ejemplo"],
            startedAt: start,
            endedAt: end,
            state: .finished,
            timezone: ProductConfig.timezone.identifier,
            isBillable: false,
            hourlyRate: nil,
            activeSeconds: 2_800,
            afkSeconds: 300,
            pausedSeconds: 500,
            suspendedSeconds: 0,
            screenshotCount: 0,
            initialNote: "Datos sintéticos claramente identificados.",
            expectedResults: "",
            integrityStatus: "sample",
            schemaVersion: 1
        ))
        let exporter = ReportExporter(database: database, outputRoot: workspace.appendingPathComponent("out"))
        let result = try exporter.export(options: ReportOptions(
            startDate: start.addingTimeInterval(-60),
            endDate: end.addingTimeInterval(60),
            includeScreenshots: false,
            executiveSummary: "EJEMPLO DEMOSTRATIVO. Este informe contiene datos sintéticos y no demuestra trabajo real."
        ))
        let mappings = [
            (result.pdf, "example.pdf"),
            (result.html, "example.html"),
            (result.csv, "example.csv"),
            (result.json, "example.json"),
            (result.zip, "example.zip")
        ]
        for (source, name) in mappings {
            let target = destination.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: source, to: target)
        }
    }
}
