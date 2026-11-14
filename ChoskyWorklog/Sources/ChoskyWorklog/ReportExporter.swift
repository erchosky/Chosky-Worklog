import AppKit
import CoreGraphics
import CoreText
import CryptoKit
import Foundation

struct ReportOptions: Sendable {
    var startDate: Date
    var endDate: Date
    var includeScreenshots = false
    var includeRates = false
    var includeWindowTitles = false
    var executiveSummary = ""
}

struct ExportResult: Sendable {
    let directory: URL
    let pdf: URL
    let html: URL
    let csv: URL
    let json: URL
    let zip: URL
    let manifest: URL
}

@MainActor
final class ReportExporter {
    private let database: WorklogDatabase
    private let outputRoot: URL

    init(database: WorklogDatabase, outputRoot: URL = ProductConfig.reportsURL) {
        self.database = database
        self.outputRoot = outputRoot
    }

    func export(options: ReportOptions) throws -> ExportResult {
        guard options.startDate <= options.endDate else {
            throw WorklogError.invalidInput("El inicio del informe debe ser anterior al final.")
        }
        let allSessions = try database.sessions(limit: 5_000)
        let matchingSessions = allSessions
            .filter {
                $0.startedAt <= options.endDate
                    && ($0.endedAt ?? Date()) >= options.startDate
            }
            .sorted { $0.startedAt < $1.startedAt }
        let sessions = matchingSessions.map { session in
            var redacted = session
            if !options.includeRates {
                redacted.hourlyRate = nil
            }
            return redacted
        }
        let id = UUID().uuidString
        let directory = outputRoot.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let jsonURL = directory.appendingPathComponent("informe.json")
        let csvURL = directory.appendingPathComponent("informe.csv")
        let htmlURL = directory.appendingPathComponent("informe.html")
        let pdfURL = directory.appendingPathComponent("informe.pdf")
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let zipURL = outputRoot.appendingPathComponent("Chosky-Worklog-\(id).zip")
        var completed = false
        defer {
            if !completed {
                try? FileManager.default.removeItem(at: directory)
                try? FileManager.default.removeItem(at: zipURL)
            }
        }

        try writeJSON(sessions: sessions, options: options, to: jsonURL)
        try writeCSV(sessions: sessions, to: csvURL)
        try writeHTML(sessions: sessions, options: options, to: htmlURL)
        try writePDF(sessions: sessions, options: options, to: pdfURL)
        try writeManifest(
            files: [pdfURL, htmlURL, csvURL, jsonURL],
            sessions: sessions,
            to: manifestURL
        )
        try createZIP(directory: directory, destination: zipURL)
        try database.addAudit(
            entityType: "report",
            entityID: nil,
            action: "export",
            oldValue: nil,
            newValue: directory.lastPathComponent,
            reason: "\(sessions.count) sesiones",
            manual: true
        )
        completed = true
        return ExportResult(
            directory: directory,
            pdf: pdfURL,
            html: htmlURL,
            csv: csvURL,
            json: jsonURL,
            zip: zipURL,
            manifest: manifestURL
        )
    }

    private func writeJSON(
        sessions: [SessionRecord],
        options: ReportOptions,
        to url: URL
    ) throws {
        struct Payload: Codable {
            let exportVersion: Int
            let generatedAt: Date
            let rangeStart: Date
            let rangeEnd: Date
            let wordingNotice: String
            let sessions: [SessionRecord]
        }
        let payload = Payload(
            exportVersion: 1,
            generatedAt: Date(),
            rangeStart: options.startDate,
            rangeEnd: options.endDate,
            wordingNotice: "Tiempo registrado, activo, AFK y pausado son métricas distintas; no constituyen una puntuación de productividad.",
            sessions: sessions
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try atomicWrite(try encoder.encode(payload), to: url)
    }

    private func writeCSV(sessions: [SessionRecord], to url: URL) throws {
        var rows = [
            [
                "session_id", "inicio", "fin", "zona_horaria", "estado",
                "segundos_registrados", "segundos_activos", "segundos_afk",
                "segundos_pausados", "segundos_suspendidos", "capturas",
                "facturable", "descripcion"
            ]
        ]
        let formatter = ISO8601DateFormatter()
        for session in sessions {
            rows.append([
                session.id.uuidString,
                formatter.string(from: session.startedAt),
                session.endedAt.map(formatter.string(from:)) ?? "",
                session.timezone,
                session.state.rawValue,
                String(Int(session.elapsed)),
                String(Int(session.activeSeconds)),
                String(Int(session.afkSeconds)),
                String(Int(session.pausedSeconds)),
                String(Int(session.suspendedSeconds)),
                String(session.screenshotCount),
                session.isBillable ? "sí" : "no",
                session.description
            ])
        }
        let csv = rows.map { row in
            row.map(Self.csvEscape).joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
        try atomicWrite(Data(csv.utf8), to: url)
    }

    private func writeHTML(
        sessions: [SessionRecord],
        options: ReportOptions,
        to url: URL
    ) throws {
        let total = sessions.reduce(0) { $0 + $1.elapsed }
        let active = sessions.reduce(0) { $0 + $1.activeSeconds }
        let afk = sessions.reduce(0) { $0 + $1.afkSeconds }
        let paused = sessions.reduce(0) { $0 + $1.pausedSeconds }
        let date = DateFormatter()
        date.locale = ProductConfig.locale
        date.timeZone = ProductConfig.timezone
        date.dateStyle = .medium
        date.timeStyle = .short
        let rows = sessions.map { session in
            """
            <tr>
              <td>\(Self.htmlEscape(date.string(from: session.startedAt)))</td>
              <td>\(Self.htmlEscape(session.description.isEmpty ? "Sin descripción" : session.description))</td>
              <td>\(session.elapsed.worklogDuration)</td>
              <td>\(session.activeSeconds.worklogDuration)</td>
              <td>\(session.afkSeconds.worklogDuration)</td>
              <td>\(session.pausedSeconds.worklogDuration)</td>
              <td>\(session.screenshotCount)</td>
            </tr>
            """
        }.joined(separator: "\n")
        let summary = options.executiveSummary.isEmpty
            ? "Informe generado localmente por Chosky Worklog."
            : Self.htmlEscape(options.executiveSummary)
        let html = """
        <!doctype html>
        <html lang="es">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Informe de trabajo</title>
          <style>
            :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
            body { max-width: 1100px; margin: 0 auto; padding: 40px; line-height: 1.45; }
            h1 { font-size: 34px; margin-bottom: 4px; }
            .muted { color: #777; }
            .metrics { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin: 28px 0; }
            .metric { border: 1px solid #bbb8; border-radius: 10px; padding: 16px; }
            .metric strong { display: block; font-size: 23px; }
            table { width: 100%; border-collapse: collapse; }
            th, td { text-align: left; padding: 10px; border-bottom: 1px solid #bbb8; }
            th { font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
            .notice { border-left: 3px solid #5e5ce6; padding: 10px 14px; background: #5e5ce611; }
            @media print { body { padding: 0; } }
          </style>
        </head>
        <body>
          <h1>Chosky Worklog</h1>
          <p class="muted">Informe privado · \(Self.htmlEscape(date.string(from: options.startDate))) – \(Self.htmlEscape(date.string(from: options.endDate)))</p>
          <p>\(summary)</p>
          <section class="metrics">
            <div class="metric"><span>Registrado</span><strong>\(total.worklogDuration)</strong></div>
            <div class="metric"><span>Activo</span><strong>\(active.worklogDuration)</strong></div>
            <div class="metric"><span>AFK</span><strong>\(afk.worklogDuration)</strong></div>
            <div class="metric"><span>Pausado</span><strong>\(paused.worklogDuration)</strong></div>
          </section>
          <p class="notice">Estas métricas describen tiempo registrado; no son una puntuación de productividad ni afirman que una persona haya sido «100 % productiva».</p>
          <h2>Sesiones</h2>
          <table>
            <thead><tr><th>Inicio</th><th>Descripción</th><th>Registrado</th><th>Activo</th><th>AFK</th><th>Pausado</th><th>Capturas</th></tr></thead>
            <tbody>\(rows)</tbody>
          </table>
          <p class="muted">Generado sin conexión el \(Self.htmlEscape(date.string(from: Date()))).</p>
        </body>
        </html>
        """
        try atomicWrite(Data(html.utf8), to: url)
    }

    private func writePDF(
        sessions: [SessionRecord],
        options: ReportOptions,
        to url: URL
    ) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw WorklogError.export("No se pudo crear el PDF.")
        }
        let total = sessions.reduce(0) { $0 + $1.elapsed }
        let active = sessions.reduce(0) { $0 + $1.activeSeconds }
        let afk = sessions.reduce(0) { $0 + $1.afkSeconds }
        let paused = sessions.reduce(0) { $0 + $1.pausedSeconds }
        let date = DateFormatter()
        date.locale = ProductConfig.locale
        date.timeZone = ProductConfig.timezone
        date.dateStyle = .medium
        date.timeStyle = .short
        var lines = [
            "CHOSKY WORKLOG",
            "Informe privado",
            "\(date.string(from: options.startDate)) – \(date.string(from: options.endDate))",
            "",
            "Tiempo registrado: \(total.worklogDuration)",
            "Tiempo activo: \(active.worklogDuration)",
            "Tiempo AFK: \(afk.worklogDuration)",
            "Tiempo pausado: \(paused.worklogDuration)",
            "",
            "Las métricas describen tiempo registrado; no son una puntuación de productividad.",
            "",
            "SESIONES"
        ]
        if !options.executiveSummary.isEmpty {
            lines.insert(options.executiveSummary, at: 4)
            lines.insert("", at: 5)
        }
        for session in sessions {
            let description = session.description.isEmpty ? "Sin descripción" : session.description
            lines.append("\(date.string(from: session.startedAt)) · \(session.elapsed.worklogDuration) · \(description)")
        }
        if sessions.isEmpty {
            lines.append("No hay sesiones en el periodo seleccionado.")
        }

        var index = 0
        while index < lines.count {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: mediaBox.height)
            context.scaleBy(x: 1, y: -1)
            var y: CGFloat = 58
            while index < lines.count, y < mediaBox.height - 55 {
                let line = lines[index]
                let isTitle = index == 0
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: isTitle
                        ? NSFont.systemFont(ofSize: 26, weight: .bold)
                        : NSFont.systemFont(ofSize: line == "SESIONES" ? 15 : 11),
                    .foregroundColor: NSColor.black
                ]
                let attributed = NSAttributedString(string: line, attributes: attributes)
                let ctLine = CTLineCreateWithAttributedString(attributed)
                context.textPosition = CGPoint(x: 50, y: y)
                CTLineDraw(ctLine, context)
                y += isTitle ? 38 : 22
                index += 1
            }
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private func writeManifest(
        files: [URL],
        sessions: [SessionRecord],
        to url: URL
    ) throws {
        struct Item: Codable {
            let name: String
            let bytes: Int
            let sha256: String
        }
        struct Manifest: Codable {
            let exportVersion: Int
            let generatedAt: Date
            let sessionIDs: [UUID]
            let files: [Item]
            let integrityNotice: String
        }
        let items = try files.map { file in
            let data = try Data(contentsOf: file, options: .mappedIfSafe)
            return Item(
                name: file.lastPathComponent,
                bytes: data.count,
                sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            )
        }
        let manifest = Manifest(
            exportVersion: 1,
            generatedAt: Date(),
            sessionIDs: sessions.map(\.id),
            files: items,
            integrityNotice: "Los hashes permiten comprobar integridad local; no son una certificación externa."
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try atomicWrite(try encoder.encode(manifest), to: url)
    }

    private func createZIP(directory: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c", "-k", "--sequesterRsrc", "--keepParent",
            directory.path, destination.path
        ]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "Error desconocido"
            throw WorklogError.export("No se pudo crear el ZIP: \(message)")
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
        )
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private static func csvEscape(_ value: String) -> String {
        let dangerousPrefixes: Set<Character> = ["=", "+", "-", "@"]
        let safeValue = value.first.map(dangerousPrefixes.contains) == true
            ? "'\(value)"
            : value
        return "\"\(safeValue.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
