import AppKit
import Combine
import Foundation

@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var clients: [ClientRecord] = []
    @Published private(set) var projects: [ProjectRecord] = []
    @Published private(set) var tasks: [TaskRecord] = []
    @Published private(set) var sessions: [SessionRecord] = []
    @Published private(set) var screenshots: [ScreenshotRecord] = []
    @Published private(set) var activeSession: SessionRecord?
    @Published private(set) var recoverySession: SessionRecord?
    @Published private(set) var lastError: String?
    @Published var now = Date()

    let database: WorklogDatabase
    let screenshotService: ScreenshotService
    private var timer: Timer?
    private var lastTick = Date()
    private var lastPersist = Date()
    private var observers: [any NSObjectProtocol] = []
    private let idleSecondsProvider: () -> TimeInterval

    init(
        database: WorklogDatabase,
        idleSecondsProvider: @escaping () -> TimeInterval = {
            CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: .null
            )
        }
    ) {
        self.database = database
        self.idleSecondsProvider = idleSecondsProvider
        screenshotService = ScreenshotService(database: database)
        screenshotService.mayCapture = { [weak self] in
            self?.activeSession?.state == .running
        }
        screenshotService.onCapture = { [weak self] record in
            guard let self else { return }
            self.screenshots.insert(record, at: 0)
            self.activeSession?.screenshotCount += 1
            if let activeSession = self.activeSession {
                try? self.database.save(session: activeSession)
            }
        }
        load(recoverIncomplete: true)
        observeSystem()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.processTick() }
        }
    }

    func load(recoverIncomplete: Bool = false) {
        do {
            clients = try database.clients()
            projects = try database.projects()
            tasks = try database.tasks()
            sessions = try database.sessions()
            screenshots = try database.screenshots()
            if recoverIncomplete, var incomplete = try database.activeSession() {
                incomplete.state = .recovering
                try database.save(session: incomplete)
                try database.closeOpenSegment(sessionID: incomplete.id)
                try database.addSegment(
                    sessionID: incomplete.id,
                    state: .recovering,
                    startedAt: Date(),
                    reason: "Apertura tras cierre incompleto"
                )
                try database.addAudit(
                    entityType: "work_session",
                    entityID: incomplete.id,
                    action: "recovery_detected",
                    oldValue: nil,
                    newValue: WorkSessionState.recovering.rawValue,
                    reason: "La aplicación encontró una sesión sin finalizar",
                    manual: false
                )
                recoverySession = incomplete
                activeSession = incomplete
                replaceSession(incomplete)
            } else if let activeSession {
                replaceSession(activeSession)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func projects(for clientID: UUID?) -> [ProjectRecord] {
        guard let clientID else { return projects }
        return projects.filter { $0.clientID == clientID }
    }

    func tasks(for projectID: UUID?) -> [TaskRecord] {
        tasks.filter { $0.projectID == nil || $0.projectID == projectID }
    }

    func start(_ draft: SessionDraft) {
        do {
            guard activeSession == nil else { throw WorklogError.activeSessionExists }
            guard clients.contains(where: { $0.id == draft.clientID && !$0.archived }),
                  projects.contains(where: {
                      $0.id == draft.projectID
                          && $0.clientID == draft.clientID
                          && !$0.archived
                  }),
                  tasks.contains(where: {
                      $0.id == draft.taskID
                          && ($0.projectID == nil || $0.projectID == draft.projectID)
                          && !$0.archived
                  })
            else {
                throw WorklogError.invalidInput("Selecciona cliente, proyecto y tarea válidos.")
            }
            let now = Date()
            let session = SessionRecord(
                id: UUID(),
                clientID: draft.clientID,
                projectID: draft.projectID,
                taskID: draft.taskID,
                description: draft.description,
                tags: draft.tags,
                startedAt: now,
                endedAt: nil,
                state: .running,
                timezone: ProductConfig.timezone.identifier,
                isBillable: draft.isBillable,
                hourlyRate: draft.hourlyRate,
                activeSeconds: 0,
                afkSeconds: 0,
                pausedSeconds: 0,
                suspendedSeconds: 0,
                screenshotCount: 0,
                initialNote: draft.initialNote,
                expectedResults: draft.expectedResults,
                integrityStatus: "valid",
                schemaVersion: ProductConfig.schemaVersion
            )
            try database.transaction {
                try database.save(session: session)
                try database.addSegment(sessionID: session.id, state: .running, startedAt: now)
                try database.addAudit(
                    entityType: "work_session",
                    entityID: session.id,
                    action: "start",
                    oldValue: nil,
                    newValue: WorkSessionState.running.rawValue,
                    reason: nil,
                    manual: true
                )
            }
            activeSession = session
            recoverySession = nil
            sessions.insert(session, at: 0)
            lastTick = now
            screenshotService.setEnabled(draft.screenshotsEnabled)
            if draft.screenshotsEnabled { screenshotService.start(for: session.id) }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func pause(privacy: Bool = false) {
        transition(to: privacy ? .privacyPaused : .manuallyPaused)
    }

    func resume() {
        transition(to: .running)
        if activeSession?.state == .running {
            recoverySession = nil
        }
    }

    func togglePrivacyPause() {
        guard let activeSession else { return }
        if activeSession.state == .privacyPaused {
            screenshotService.setPrivacyPaused(false)
            resume()
        } else if activeSession.state == .running {
            transition(to: .privacyPaused)
            screenshotService.setPrivacyPaused(true)
        } else {
            lastError = "La pausa de privacidad solo puede activarse mientras la sesión está en curso."
        }
    }

    func finish() {
        guard activeSession != nil else {
            lastError = WorklogError.noActiveSession.localizedDescription
            return
        }
        tick()
        guard var session = activeSession else { return }
        do {
            guard session.state.canTransition(to: .finished) else {
                throw WorklogError.invalidTransition(session.state, .finished)
            }
            let old = session.state
            let end = Date()
            session.state = .finished
            session.endedAt = end
            try database.transaction {
                try database.closeOpenSegment(sessionID: session.id, endedAt: end)
                try database.save(session: session)
                try database.addAudit(
                    entityType: "work_session",
                    entityID: session.id,
                    action: "finish",
                    oldValue: old.rawValue,
                    newValue: WorkSessionState.finished.rawValue,
                    reason: nil,
                    manual: true
                )
            }
            replaceSession(session)
            activeSession = nil
            recoverySession = nil
            screenshotService.stop()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func recoverContinue() {
        transition(to: .running, reason: "Continuación confirmada tras recuperación")
        if activeSession?.state == .running {
            recoverySession = nil
        }
    }

    func recoverFinish() {
        finish()
    }

    func switchTask(to taskID: UUID) {
        guard var session = activeSession,
              tasks.contains(where: {
                  $0.id == taskID
                      && ($0.projectID == nil || $0.projectID == session.projectID)
                      && !$0.archived
              })
        else { return }
        do {
            let oldTask = session.taskID
            let now = Date()
            try database.transaction {
                try database.closeOpenSegment(sessionID: session.id, endedAt: now)
                session.taskID = taskID
                try database.save(session: session)
                try database.addSegment(
                    sessionID: session.id,
                    state: session.state,
                    startedAt: now,
                    reason: "Cambio de tarea"
                )
                try database.addAudit(
                    entityType: "work_session",
                    entityID: session.id,
                    action: "switch_task",
                    oldValue: oldTask.uuidString,
                    newValue: taskID.uuidString,
                    reason: nil,
                    manual: true
                )
            }
            activeSession = session
            replaceSession(session)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addDeliverable(title: String, details: String) {
        guard let sessionID = activeSession?.id ?? sessions.first?.id else { return }
        do {
            try database.addDeliverable(
                sessionID: sessionID,
                title: title,
                details: details,
                link: nil
            )
            try database.addAudit(
                entityType: "deliverable",
                entityID: sessionID,
                action: "create",
                oldValue: nil,
                newValue: title,
                reason: nil,
                manual: true
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteScreenshot(_ screenshot: ScreenshotRecord) {
        guard screenshot.deletedAt == nil else { return }
        let file = ProductConfig.appSupportURL.appendingPathComponent(screenshot.relativePath)
        let thumbnail = screenshot.thumbnailPath.map {
            ProductConfig.appSupportURL.appendingPathComponent($0)
        }
        var movedFiles: [(original: URL, trashed: URL)] = []
        do {
            let trash = ProductConfig.appSupportURL.appendingPathComponent(
                "Trash/\(screenshot.id.uuidString)-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: trash,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            if FileManager.default.fileExists(atPath: file.path) {
                let trashed = trash.appendingPathComponent(file.lastPathComponent)
                try FileManager.default.moveItem(
                    at: file,
                    to: trashed
                )
                movedFiles.append((file, trashed))
            }
            if let thumbnail, FileManager.default.fileExists(atPath: thumbnail.path) {
                let trashed = trash.appendingPathComponent(thumbnail.lastPathComponent)
                try FileManager.default.moveItem(
                    at: thumbnail,
                    to: trashed
                )
                movedFiles.append((thumbnail, trashed))
            }
            try database.transaction {
                try database.markScreenshotDeleted(id: screenshot.id)
                try database.addAudit(
                    entityType: "screenshot",
                    entityID: screenshot.id,
                    action: "move_to_trash",
                    oldValue: screenshot.relativePath,
                    newValue: nil,
                    reason: "Eliminación solicitada por el propietario",
                    manual: true
                )
            }
            load()
        } catch {
            for item in movedFiles.reversed()
            where FileManager.default.fileExists(atPath: item.trashed.path)
                && !FileManager.default.fileExists(atPath: item.original.path) {
                try? FileManager.default.moveItem(at: item.trashed, to: item.original)
            }
            lastError = error.localizedDescription
        }
    }

    func createClient(name: String) {
        do {
            let client = ClientRecord(id: UUID(), name: name, color: "#5E5CE6", archived: false)
            try database.save(client: client)
            try database.addAudit(
                entityType: "client",
                entityID: client.id,
                action: "create",
                oldValue: nil,
                newValue: name,
                reason: nil,
                manual: true
            )
            load()
        } catch { lastError = error.localizedDescription }
    }

    func createProject(clientID: UUID, name: String) {
        do {
            guard clients.contains(where: { $0.id == clientID && !$0.archived }) else {
                throw WorklogError.invalidInput("Selecciona un cliente válido.")
            }
            let project = ProjectRecord(
                id: UUID(), clientID: clientID, name: name, color: "#0A84FF",
                isBillable: true, hourlyRate: nil, archived: false
            )
            try database.save(project: project)
            try database.addAudit(
                entityType: "project",
                entityID: project.id,
                action: "create",
                oldValue: nil,
                newValue: name,
                reason: nil,
                manual: true
            )
            load()
        } catch { lastError = error.localizedDescription }
    }

    func clearError() {
        lastError = nil
    }

    private func transition(
        to target: WorkSessionState,
        reason: String? = nil,
        manual: Bool = true
    ) {
        guard activeSession != nil else {
            lastError = WorklogError.noActiveSession.localizedDescription
            return
        }
        tick()
        guard var session = activeSession else { return }
        do {
            guard session.state.canTransition(to: target) else {
                throw WorklogError.invalidTransition(session.state, target)
            }
            let old = session.state
            let now = Date()
            try database.transaction {
                try database.closeOpenSegment(sessionID: session.id, endedAt: now)
                session.state = target
                try database.save(session: session)
                try database.addSegment(
                    sessionID: session.id,
                    state: target,
                    startedAt: now,
                    reason: reason
                )
                try database.addAudit(
                    entityType: "work_session",
                    entityID: session.id,
                    action: "state_change",
                    oldValue: old.rawValue,
                    newValue: target.rawValue,
                    reason: reason,
                    manual: manual
                )
            }
            activeSession = session
            replaceSession(session)
            lastTick = now
            if target == .running {
                screenshotService.setPrivacyPaused(false)
                if screenshotService.enabled { screenshotService.start(for: session.id) }
            } else {
                screenshotService.stop()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func tick() {
        let timestamp = Date()
        defer {
            now = timestamp
            lastTick = timestamp
        }
        guard var session = activeSession else { return }
        let delta = max(0, min(5, timestamp.timeIntervalSince(lastTick)))
        switch session.state {
        case .running: session.activeSeconds += delta
        case .afk: session.afkSeconds += delta
        case .manuallyPaused, .privacyPaused: session.pausedSeconds += delta
        case .sleeping, .recovering: session.suspendedSeconds += delta
        default: break
        }
        activeSession = session
        replaceSession(session)
        if timestamp.timeIntervalSince(lastPersist) >= 15 {
            try? database.save(session: session)
            lastPersist = timestamp
        }
    }

    func processTick() {
        if activeSession?.state == .running,
           idleSecondsProvider() >= ProductConfig.afkThresholdSeconds {
            transition(
                to: .afk,
                reason: "Inactividad de entrada detectada",
                manual: false
            )
        } else if activeSession?.state == .afk, idleSecondsProvider() < 1 {
            transition(
                to: .running,
                reason: "Actividad de entrada reanudada",
                manual: false
            )
        } else {
            tick()
        }
    }

    private func replaceSession(_ session: SessionRecord) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
    }

    private func observeSystem() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.systemWillSleep() }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.systemDidWake() }
        })
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.systemWillSleep() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.systemDidWake() }
        }
    }

    private func systemWillSleep() {
        guard activeSession?.state == .running || activeSession?.state == .afk else { return }
        transition(
            to: .sleeping,
            reason: "Reposo o bloqueo del sistema",
            manual: false
        )
    }

    private func systemDidWake() {
        guard activeSession?.state == .sleeping else { return }
        transition(
            to: .recovering,
            reason: "Reanudación del sistema pendiente de confirmación",
            manual: false
        )
        recoverySession = activeSession
    }
}
