import AppKit
import CryptoKit
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
final class ScreenshotService: ObservableObject {
    @Published private(set) var enabled = true
    @Published private(set) var isPrivacyPaused = false
    @Published private(set) var lastCapture: Date?
    @Published private(set) var nextApproximateCapture: Date?
    @Published private(set) var lastError: String?
    @Published var showApproximateTime = false
    @Published private(set) var minimumMinutes = ProductConfig.screenshotMinimumMinutes
    @Published private(set) var maximumMinutes = ProductConfig.screenshotMaximumMinutes

    private var scheduler: Task<Void, Never>?
    private var sessionID: UUID?
    private var scheduleGeneration = 0
    private let database: WorklogDatabase
    var onCapture: (@MainActor (ScreenshotRecord) -> Void)?
    var mayCapture: (@MainActor () -> Bool)?

    init(database: WorklogDatabase) {
        self.database = database
    }

    deinit {
        scheduler?.cancel()
    }

    var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func start(for sessionID: UUID) {
        invalidateSchedule()
        self.sessionID = sessionID
        isPrivacyPaused = false
        scheduleNext()
    }

    func stop() {
        invalidateSchedule()
        sessionID = nil
        nextApproximateCapture = nil
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        if value, sessionID != nil {
            scheduleNext()
        } else {
            invalidateSchedule()
            nextApproximateCapture = nil
        }
    }

    func setPrivacyPaused(_ value: Bool) {
        isPrivacyPaused = value
        if value {
            invalidateSchedule()
            nextApproximateCapture = nil
        } else if sessionID != nil, enabled {
            scheduleNext()
        }
    }

    func skipNext() {
        guard sessionID != nil, enabled else { return }
        scheduleNext()
    }

    func setMinimumMinutes(_ value: Int) {
        minimumMinutes = max(1, min(value, 60))
        maximumMinutes = max(maximumMinutes, minimumMinutes)
        if sessionID != nil, enabled, !isPrivacyPaused { scheduleNext() }
    }

    func setMaximumMinutes(_ value: Int) {
        maximumMinutes = max(minimumMinutes, min(value, 120))
        if sessionID != nil, enabled, !isPrivacyPaused { scheduleNext() }
    }

    func captureNow() {
        guard canCapture, let expectedSessionID = sessionID else {
            lastError = "La captura está pausada, desactivada o no hay una sesión en curso."
            return
        }
        invalidateSchedule()
        scheduleGeneration += 1
        let generation = scheduleGeneration
        scheduler = Task { [weak self] in
            await self?.performCaptureAndReschedule(
                expectedSessionID: expectedSessionID,
                generation: generation
            )
        }
    }

    static func randomIntervalSeconds(
        minimumMinutes: Int,
        maximumMinutes: Int,
        using generator: inout some RandomNumberGenerator
    ) -> TimeInterval {
        let minimum = max(1, minimumMinutes)
        let maximum = max(minimum, maximumMinutes)
        return TimeInterval(Int.random(
            in: (minimum * 60)...(maximum * 60),
            using: &generator
        ))
    }

    private var canCapture: Bool {
        enabled
            && !isPrivacyPaused
            && sessionID != nil
            && !Self.isScreenLocked
            && (mayCapture?() ?? true)
    }

    private func scheduleNext() {
        invalidateSchedule()
        guard canCapture else {
            nextApproximateCapture = nil
            return
        }
        var generator = SystemRandomNumberGenerator()
        let interval = Self.randomIntervalSeconds(
            minimumMinutes: minimumMinutes,
            maximumMinutes: maximumMinutes,
            using: &generator
        )
        nextApproximateCapture = Date().addingTimeInterval(interval)
        scheduleGeneration += 1
        let generation = scheduleGeneration
        guard let expectedSessionID = sessionID else { return }
        scheduler = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled, let self else { return }
            await self.performCaptureAndReschedule(
                expectedSessionID: expectedSessionID,
                generation: generation
            )
        }
    }

    private func performCaptureAndReschedule(
        expectedSessionID: UUID,
        generation: Int
    ) async {
        defer {
            if scheduleGeneration == generation,
               sessionID == expectedSessionID,
               enabled,
               !isPrivacyPaused {
                scheduler = nil
                scheduleNext()
            }
        }
        guard scheduleGeneration == generation,
              sessionID == expectedSessionID,
              canCapture,
              !Task.isCancelled
        else { return }
        guard hasPermission else {
            lastError = "Falta el permiso de Grabación de pantalla."
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                    ?? content.displays.first
            else {
                throw WorklogError.screenshot("No se encontró ninguna pantalla disponible.")
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height
            configuration.showsCursor = true
            configuration.ignoreShadowsSingleWindow = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            guard scheduleGeneration == generation,
                  sessionID == expectedSessionID,
                  canCapture,
                  !Task.isCancelled
            else { return }
            let record = try persist(
                image: image,
                sessionID: expectedSessionID,
                displayID: display.displayID
            )
            do {
                try database.save(screenshot: record)
            } catch {
                removeFiles(for: record)
                throw error
            }
            lastCapture = record.capturedAt
            lastError = nil
            onCapture?(record)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persist(
        image: CGImage,
        sessionID: UUID,
        displayID: CGDirectDisplayID
    ) throws -> ScreenshotRecord {
        let id = UUID()
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: ProductConfig.timezone, from: now)
        let relativeDirectory = String(
            format: "Screenshots/%04d/%02d/%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        let directory = ProductConfig.appSupportURL.appendingPathComponent(
            relativeDirectory,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let filename = "\(id.uuidString).heic"
        let relativePath = "\(relativeDirectory)/\(filename)"
        let destination = directory.appendingPathComponent(filename)
        let temporary = directory.appendingPathComponent(".\(filename).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let writer = CGImageDestinationCreateWithURL(
            temporary as CFURL,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else {
            throw WorklogError.screenshot("No se pudo preparar el archivo HEIC.")
        }
        CGImageDestinationAddImage(
            writer,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary
        )
        guard CGImageDestinationFinalize(writer) else {
            try? FileManager.default.removeItem(at: temporary)
            throw WorklogError.screenshot("No se pudo finalizar la captura.")
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: temporary.path
        )
        try FileManager.default.moveItem(at: temporary, to: destination)

        let data = try Data(contentsOf: destination, options: .mappedIfSafe)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let thumbnailRelative: String
        do {
            thumbnailRelative = try persistThumbnail(image: image, id: id)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        let app = NSWorkspace.shared.frontmostApplication
        return ScreenshotRecord(
            id: id,
            sessionID: sessionID,
            capturedAt: now,
            relativePath: relativePath,
            thumbnailPath: thumbnailRelative,
            sha256: hash,
            displayID: displayID,
            width: image.width,
            height: image.height,
            scale: Self.scale(for: displayID),
            activeApplication: app?.localizedName,
            activeWindow: nil,
            included: true,
            deletedAt: nil,
            note: ""
        )
    }

    private func persistThumbnail(image: CGImage, id: UUID) throws -> String {
        let relative = "Thumbnails/\(id.uuidString).jpg"
        let url = ProductConfig.appSupportURL.appendingPathComponent(relative)
        let maxWidth = 480
        let ratio = min(1, CGFloat(maxWidth) / CGFloat(image.width))
        let width = max(1, Int(CGFloat(image.width) * ratio))
        let height = max(1, Int(CGFloat(image.height) * ratio))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw WorklogError.screenshot("No se pudo crear la miniatura.")
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let thumbnail = context.makeImage(),
              let writer = CGImageDestinationCreateWithURL(
                  url as CFURL,
                  UTType.jpeg.identifier as CFString,
                  1,
                  nil
              )
        else {
            throw WorklogError.screenshot("No se pudo guardar la miniatura.")
        }
        CGImageDestinationAddImage(
            writer,
            thumbnail,
            [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary
        )
        guard CGImageDestinationFinalize(writer) else {
            throw WorklogError.screenshot("No se pudo finalizar la miniatura.")
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        return relative
    }

    private static var isScreenLocked: Bool {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return true
        }
        if dictionary["CGSSessionScreenIsLocked"] as? Bool == true { return true }
        if let loginDone = dictionary["kCGSessionLoginDoneKey"] as? Bool, !loginDone {
            return true
        }
        return false
    }

    private static func scale(for displayID: CGDirectDisplayID) -> Double {
        for screen in NSScreen.screens {
            let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber
            if number?.uint32Value == displayID {
                return screen.backingScaleFactor
            }
        }
        return 1
    }

    private func invalidateSchedule() {
        scheduleGeneration += 1
        scheduler?.cancel()
        scheduler = nil
    }

    private func removeFiles(for record: ScreenshotRecord) {
        try? FileManager.default.removeItem(
            at: ProductConfig.appSupportURL.appendingPathComponent(record.relativePath)
        )
        if let thumbnailPath = record.thumbnailPath {
            try? FileManager.default.removeItem(
                at: ProductConfig.appSupportURL.appendingPathComponent(thumbnailPath)
            )
        }
    }
}
