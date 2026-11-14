import Foundation

enum WorkSessionState: String, Codable, CaseIterable, Sendable {
    case prepared
    case running
    case manuallyPaused = "paused_manual"
    case privacyPaused = "paused_privacy"
    case afk
    case sleeping
    case recovering
    case finished
    case corrected
    case archived

    var label: String {
        switch self {
        case .prepared: "Preparada"
        case .running: "En curso"
        case .manuallyPaused: "Pausada"
        case .privacyPaused: "Privacidad"
        case .afk: "Inactiva"
        case .sleeping: "Suspendida"
        case .recovering: "Recuperándose"
        case .finished: "Finalizada"
        case .corrected: "Corregida"
        case .archived: "Archivada"
        }
    }

    func canTransition(to target: WorkSessionState) -> Bool {
        if self == target { return true }
        return switch (self, target) {
        case (.prepared, .running),
             (.running, .manuallyPaused),
             (.running, .privacyPaused),
             (.running, .afk),
             (.running, .sleeping),
             (.running, .finished),
             (.manuallyPaused, .running),
             (.manuallyPaused, .privacyPaused),
             (.manuallyPaused, .finished),
             (.privacyPaused, .running),
             (.privacyPaused, .manuallyPaused),
             (.privacyPaused, .finished),
             (.afk, .running),
             (.afk, .manuallyPaused),
             (.afk, .sleeping),
             (.afk, .finished),
             (.sleeping, .recovering),
             (.sleeping, .finished),
             (.recovering, .running),
             (.recovering, .manuallyPaused),
             (.recovering, .finished),
             (.finished, .corrected),
             (.finished, .archived),
             (.corrected, .archived):
            true
        default:
            false
        }
    }
}

struct ClientRecord: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var color: String
    var archived: Bool
}

struct ProjectRecord: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var clientID: UUID
    var name: String
    var color: String
    var isBillable: Bool
    var hourlyRate: Decimal?
    var archived: Bool
}

struct TaskRecord: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var projectID: UUID?
    var name: String
    var archived: Bool
}

struct SessionRecord: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var clientID: UUID
    var projectID: UUID
    var taskID: UUID
    var description: String
    var tags: [String]
    var startedAt: Date
    var endedAt: Date?
    var state: WorkSessionState
    var timezone: String
    var isBillable: Bool
    var hourlyRate: Decimal?
    var activeSeconds: TimeInterval
    var afkSeconds: TimeInterval
    var pausedSeconds: TimeInterval
    var suspendedSeconds: TimeInterval
    var screenshotCount: Int
    var initialNote: String
    var expectedResults: String
    var integrityStatus: String
    var schemaVersion: Int

    var elapsed: TimeInterval {
        max(0, (endedAt ?? Date()).timeIntervalSince(startedAt))
    }

    var estimatedValue: Decimal? {
        guard isBillable, let hourlyRate else { return nil }
        return hourlyRate * Decimal(elapsed / 3600)
    }
}

struct ScreenshotRecord: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let sessionID: UUID
    let capturedAt: Date
    let relativePath: String
    let thumbnailPath: String?
    let sha256: String
    let displayID: UInt32
    let width: Int
    let height: Int
    let scale: Double
    let activeApplication: String?
    let activeWindow: String?
    var included: Bool
    var deletedAt: Date?
    var note: String
}

struct DeliverableRecord: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let sessionID: UUID
    var title: String
    var details: String
    var link: String?
    let createdAt: Date
}

struct AuditEntry: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let occurredAt: Date
    let entityType: String
    let entityID: UUID?
    let action: String
    let oldValue: String?
    let newValue: String?
    let reason: String?
    let manual: Bool
    let deviceID: String
}

struct SessionDraft: Sendable {
    var clientID: UUID
    var projectID: UUID
    var taskID: UUID
    var description = ""
    var tags: [String] = []
    var isBillable = true
    var hourlyRate: Decimal?
    var screenshotsEnabled = true
    var initialNote = ""
    var expectedResults = ""
}

enum WorklogError: LocalizedError {
    case invalidTransition(WorkSessionState, WorkSessionState)
    case activeSessionExists
    case noActiveSession
    case invalidInput(String)
    case database(String)
    case screenshot(String)
    case export(String)
    case sharing(String)

    var errorDescription: String? {
        switch self {
        case let .invalidTransition(from, to):
            "Transición de estado no válida: \(from.label) → \(to.label)."
        case .activeSessionExists:
            "Ya existe una sesión activa."
        case .noActiveSession:
            "No hay ninguna sesión activa."
        case let .invalidInput(message),
             let .database(message),
             let .screenshot(message),
             let .export(message),
             let .sharing(message):
            message
        }
    }
}

extension TimeInterval {
    var worklogDuration: String {
        let seconds = max(0, Int(self))
        return String(
            format: "%02d:%02d:%02d",
            seconds / 3600,
            (seconds / 60) % 60,
            seconds % 60
        )
    }
}
