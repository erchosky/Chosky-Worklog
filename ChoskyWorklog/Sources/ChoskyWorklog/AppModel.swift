import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared: AppModel = {
        do {
            try ProductConfig.prepareDirectories()
            return try AppModel()
        } catch {
            fatalError("No se pudo iniciar \(ProductConfig.name): \(error.localizedDescription)")
        }
    }()

    let database: WorklogDatabase
    let sessions: SessionManager
    let activityWatch: ActivityWatchSupervisor
    let reports: ReportExporter
    let backups: BackupManager
    let sharing: SharingServer

    @Published var lastExport: ExportResult?
    @Published var lastBackup: BackupResult?
    @Published var operationMessage: String?
    private var cancellables: Set<AnyCancellable> = []
    private var previousSession: SessionRecord?

    private init() throws {
        database = try WorklogDatabase()
        sessions = SessionManager(database: database)
        activityWatch = ActivityWatchSupervisor(database: database)
        reports = ReportExporter(database: database)
        backups = BackupManager(database: database)
        sharing = SharingServer(database: database)
        previousSession = sessions.activeSession

        sessions.$activeSession
            .sink { [weak self] current in
                guard let self else { return }
                self.synchronizeActivityWatch(previous: self.previousSession, current: current)
                self.previousSession = current
                self.objectWillChange.send()
            }
            .store(in: &cancellables)
        activityWatch.startServer()
    }

    func exportCurrentMonth() {
        do {
            let calendar = Calendar(identifier: .gregorian)
            let now = Date()
            let start = calendar.date(
                from: calendar.dateComponents([.year, .month], from: now)
            ) ?? now
            let end = calendar.date(byAdding: .month, value: 1, to: start)?
                .addingTimeInterval(-1) ?? now
            lastExport = try reports.export(options: ReportOptions(
                startDate: start,
                endDate: end
            ))
            operationMessage = "Informe exportado correctamente."
        } catch {
            operationMessage = error.localizedDescription
        }
    }

    func createBackup(includeScreenshots: Bool) {
        do {
            let result = try backups.create(includeScreenshots: includeScreenshots)
            let verified = try BackupManager.verifyRestore(
                archive: result.archive,
                expectedChecksum: result.checksum
            )
            lastBackup = result
            operationMessage = "Backup creado y restaurado en una prueba limpia. SHA-256: \(verified)"
        } catch {
            operationMessage = error.localizedDescription
        }
    }

    func shutdown() {
        sharing.revokeAll()
        activityWatch.stopAll()
        try? database.checkpoint()
    }

    private func synchronizeActivityWatch(
        previous: SessionRecord?,
        current: SessionRecord?
    ) {
        switch (previous, current) {
        case (nil, let current?):
            activityWatch.sessionDidStart(current)
        case (let previous?, nil):
            activityWatch.sessionDidFinish(previous)
        case (let previous?, let current?):
            if previous.state != current.state {
                if current.state == .running {
                    activityWatch.sessionDidResume(current)
                } else {
                    activityWatch.sessionDidPause(current)
                }
            }
        default:
            break
        }
    }
}
