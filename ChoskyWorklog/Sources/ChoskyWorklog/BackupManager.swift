import CryptoKit
import Foundation

struct BackupResult: Sendable {
    let archive: URL
    let checksum: String
}

final class BackupManager: @unchecked Sendable {
    private let database: WorklogDatabase
    private let outputRoot: URL

    init(database: WorklogDatabase, outputRoot: URL = ProductConfig.backupsURL) {
        self.database = database
        self.outputRoot = outputRoot
    }

    func create(includeScreenshots: Bool) throws -> BackupResult {
        try database.checkpoint()
        let id = UUID().uuidString
        let staging = outputRoot.appendingPathComponent(".staging-\(id)", isDirectory: true)
        let archive = outputRoot.appendingPathComponent("Chosky-Backup-\(id).zip")
        try FileManager.default.createDirectory(
            at: staging,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(
            at: database.url,
            to: staging.appendingPathComponent("worklog.sqlite3")
        )
        if includeScreenshots, FileManager.default.fileExists(atPath: ProductConfig.screenshotsURL.path) {
            try FileManager.default.copyItem(
                at: ProductConfig.screenshotsURL,
                to: staging.appendingPathComponent("Screenshots", isDirectory: true)
            )
            if FileManager.default.fileExists(atPath: ProductConfig.thumbnailsURL.path) {
                try FileManager.default.copyItem(
                    at: ProductConfig.thumbnailsURL,
                    to: staging.appendingPathComponent("Thumbnails", isDirectory: true)
                )
            }
        }
        let metadata: [String: Any] = [
            "product": ProductConfig.name,
            "bundleIdentifier": ProductConfig.bundleIdentifier,
            "schemaVersion": ProductConfig.schemaVersion,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "includesScreenshots": includeScreenshots
        ]
        let metadataData = try JSONSerialization.data(
            withJSONObject: metadata,
            options: [.prettyPrinted, .sortedKeys]
        )
        try metadataData.write(
            to: staging.appendingPathComponent("backup-info.json"),
            options: .atomic
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", staging.path, archive.path]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            throw WorklogError.export(
                "Error de backup: \(String(data: data, encoding: .utf8) ?? "desconocido")"
            )
        }
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: archive.path
        )
        try database.addAudit(
            entityType: "backup",
            entityID: nil,
            action: "create",
            oldValue: nil,
            newValue: archive.lastPathComponent,
            reason: includeScreenshots ? "Con capturas" : "Sin capturas",
            manual: true
        )
        return BackupResult(archive: archive, checksum: checksum)
    }

    static func verifyRestore(archive: URL, expectedChecksum: String? = nil) throws -> String {
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let expectedChecksum, checksum != expectedChecksum {
            throw WorklogError.database("El checksum del backup no coincide.")
        }
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("chosky-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, temporary.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw WorklogError.database("No se pudo descomprimir el backup.")
        }
        let restoredFiles = FileManager.default.enumerator(
            at: temporary,
            includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL } ?? []
        guard let databaseURL = restoredFiles.first(where: {
            $0.lastPathComponent == "worklog.sqlite3"
        }) else {
            throw WorklogError.database("El backup no contiene la base de datos.")
        }
        guard let metadataURL = restoredFiles.first(where: {
            $0.lastPathComponent == "backup-info.json"
        }),
              let metadata = try JSONSerialization.jsonObject(
                  with: Data(contentsOf: metadataURL)
              ) as? [String: Any],
              metadata["bundleIdentifier"] as? String == ProductConfig.bundleIdentifier,
              metadata["schemaVersion"] as? Int == ProductConfig.schemaVersion
        else {
            throw WorklogError.database("Los metadatos del backup no son válidos.")
        }
        let restored = try WorklogDatabase(url: databaseURL, migrateIfNeeded: false)
        guard try restored.migrationVersion() == ProductConfig.schemaVersion else {
            throw WorklogError.database("La versión de esquema del backup no es compatible.")
        }
        let integrity = try restored.integrityCheck()
        guard integrity == "ok" else {
            throw WorklogError.database("La restauración no supera integrity_check: \(integrity)")
        }
        return checksum
    }
}
