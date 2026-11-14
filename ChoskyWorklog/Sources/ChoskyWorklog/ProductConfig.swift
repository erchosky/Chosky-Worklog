import Foundation

enum ProductConfig {
    static let name = "Chosky Worklog"
    static let executableName = "ChoskyWorklog"
    static let bundleIdentifier = "com.chosky.worklog"
    static let version = "0.1.0"
    static let schemaVersion = 1
    static let activityWatchPort: UInt16 = 5600
    static let defaultClientName = "Nina"
    static let defaultCurrency = "EUR"
    static let locale = Locale(identifier: "es_ES")
    static let timezone = TimeZone(identifier: "Europe/Madrid") ?? .current
    static let screenshotMinimumMinutes = 8
    static let screenshotMaximumMinutes = 18
    static let afkThresholdSeconds: TimeInterval = 5 * 60

    static var appSupportURL: URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return root.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    static var databaseURL: URL {
        appSupportURL.appendingPathComponent("Database/worklog.sqlite3")
    }

    static var screenshotsURL: URL {
        appSupportURL.appendingPathComponent("Screenshots", isDirectory: true)
    }

    static var thumbnailsURL: URL {
        appSupportURL.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    static var reportsURL: URL {
        appSupportURL.appendingPathComponent("Reports", isDirectory: true)
    }

    static var backupsURL: URL {
        appSupportURL.appendingPathComponent("Backups", isDirectory: true)
    }

    static var logsURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/\(bundleIdentifier)", isDirectory: true)
    }

    static func prepareDirectories() throws {
        let directories = [
            databaseURL.deletingLastPathComponent(),
            screenshotsURL,
            thumbnailsURL,
            reportsURL,
            backupsURL,
            logsURL,
            appSupportURL.appendingPathComponent("ActivityWatch", isDirectory: true),
            appSupportURL.appendingPathComponent("Cache", isDirectory: true)
        ]
        for directory in directories {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        }
    }
}
