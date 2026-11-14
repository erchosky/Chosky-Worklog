import Darwin
import Foundation

@MainActor
final class ActivityWatchSupervisor: ObservableObject {
    enum Status: String {
        case stopped = "Detenido"
        case starting = "Iniciando"
        case running = "Activo"
        case degraded = "Degradado"
        case error = "Error"
    }

    @Published private(set) var serverStatus: Status = .stopped
    @Published private(set) var watcherStatus: Status = .stopped
    @Published private(set) var lastError: String?
    @Published private(set) var serverPID: Int32?
    @Published private(set) var watcherPIDs: [Int32] = []
    @Published var continuousMode = false {
        didSet {
            guard continuousMode != oldValue else { return }
            if continuousMode {
                if serverStatus == .running {
                    startWatchers()
                } else {
                    startServer()
                }
            } else if !sessionTrackingActive {
                stopWatchers()
            }
        }
    }

    private var server: Process?
    private var watchers: [Process] = []
    private var monitor: Task<Void, Never>?
    private var sessionMonitor: Task<Void, Never>?
    private var activeSessionID: UUID?
    private var sessionTrackingActive = false
    private let database: WorklogDatabase
    private let hostname = Host.current().localizedName?
        .replacingOccurrences(of: " ", with: "-")
        .lowercased() ?? "mac"

    init(database: WorklogDatabase) {
        self.database = database
    }

    deinit {
        monitor?.cancel()
        sessionMonitor?.cancel()
        for process in watchers where process.isRunning {
            process.terminate()
        }
        if let server, server.isRunning {
            server.terminate()
        }
    }

    func startServer() {
        guard server?.isRunning != true else { return }
        do {
            let executable = try resourceURL("aw-server-rust/aw-server-rust")
            let activityDirectory = ProductConfig.appSupportURL
                .appendingPathComponent("ActivityWatch", isDirectory: true)
            try FileManager.default.createDirectory(
                at: activityDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let arguments = [
                "--host", "127.0.0.1",
                "--port", String(ProductConfig.activityWatchPort),
                "--dbpath", activityDirectory.appendingPathComponent("peewee-sqlite.v2.db").path,
                "--no-legacy-import"
            ]
            let process = try guardedProcess(executable: executable, arguments: arguments)
            let log = try logHandle(named: "activitywatch-server.log")
            process.standardOutput = log
            process.standardError = log
            process.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    guard let self, self.server === process else { return }
                    self.stopWatchers()
                    self.serverStatus = process.terminationStatus == 0 ? .stopped : .error
                    self.serverPID = nil
                    if process.terminationStatus != 0 {
                        self.lastError = "ActivityWatch terminó con código \(process.terminationStatus)."
                    }
                }
            }
            serverStatus = .starting
            try process.run()
            server = process
            serverPID = process.processIdentifier
            monitor?.cancel()
            monitor = Task { [weak self] in
                guard let self else { return }
                for _ in 0..<20 {
                    if Task.isCancelled { return }
                    if await self.healthCheck() {
                        guard !Task.isCancelled else { return }
                        self.serverStatus = .running
                        self.lastError = nil
                        if self.continuousMode || self.sessionTrackingActive {
                            self.startWatchers()
                        }
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                }
                self.serverStatus = .error
                self.lastError = "ActivityWatch no respondió en 127.0.0.1:\(ProductConfig.activityWatchPort)."
            }
        } catch {
            serverStatus = .error
            lastError = error.localizedDescription
        }
    }

    func stopAll() {
        monitor?.cancel()
        sessionMonitor?.cancel()
        stopWatchers()
        terminate(server)
        server = nil
        serverPID = nil
        serverStatus = .stopped
    }

    func sessionDidStart(_ session: SessionRecord) {
        activeSessionID = session.id
        sessionTrackingActive = true
        if serverStatus == .running {
            startWatchers()
            Task { await sendSessionHeartbeat(session, state: "running") }
        } else {
            startServer()
            monitorSessionReadiness(session)
        }
    }

    func sessionDidPause(_ session: SessionRecord) {
        sessionTrackingActive = false
        sessionMonitor?.cancel()
        guard !continuousMode else {
            Task { await sendSessionHeartbeat(session, state: session.state.rawValue) }
            return
        }
        stopWatchers()
        Task { await sendSessionHeartbeat(session, state: session.state.rawValue) }
    }

    func sessionDidResume(_ session: SessionRecord) {
        activeSessionID = session.id
        sessionTrackingActive = true
        if serverStatus == .running {
            startWatchers()
            Task { await sendSessionHeartbeat(session, state: "running") }
        } else {
            startServer()
            monitorSessionReadiness(session)
        }
    }

    func sessionDidFinish(_ session: SessionRecord) {
        sessionMonitor?.cancel()
        Task { await sendSessionHeartbeat(session, state: "finished") }
        activeSessionID = nil
        sessionTrackingActive = false
        if !continuousMode { stopWatchers() }
    }

    func restart() {
        stopAll()
        startServer()
    }

    func healthCheck() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(ProductConfig.activityWatchPort)/api/0/info") else {
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let info = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = info["version"] as? String,
                  !version.isEmpty
            else { return false }
            return true
        } catch {
            return false
        }
    }

    private func startWatchers() {
        guard watchers.isEmpty, serverStatus == .running else { return }
        var started: [Process] = []
        do {
            let definitions = [
                ("aw-watcher-afk/aw-watcher-afk", ["--host", "127.0.0.1", "--port", String(ProductConfig.activityWatchPort)]),
                ("aw-watcher-window/aw-watcher-window", ["--host", "127.0.0.1", "--port", String(ProductConfig.activityWatchPort), "--strategy", "swift"])
            ]
            for (path, arguments) in definitions {
                let process = try guardedProcess(
                    executable: try resourceURL(path),
                    arguments: arguments
                )
                let log = try logHandle(named: path.contains("afk") ? "activitywatch-afk.log" : "activitywatch-window.log")
                process.standardOutput = log
                process.standardError = log
                process.terminationHandler = { [weak self] process in
                    Task { @MainActor in
                        guard let self,
                              self.watchers.contains(where: { $0 === process })
                        else { return }
                        let remaining = self.watchers.filter { $0 !== process }
                        self.watchers = []
                        for watcher in remaining { self.terminate(watcher) }
                        self.watcherPIDs = []
                        self.watcherStatus = .error
                        self.lastError = "Un watcher de ActivityWatch terminó inesperadamente con código \(process.terminationStatus)."
                    }
                }
                try process.run()
                started.append(process)
            }
            watchers = started
            watcherPIDs = started.map(\.processIdentifier)
            watcherStatus = .running
        } catch {
            for process in started { terminate(process) }
            watchers = []
            watcherPIDs = []
            watcherStatus = .error
            lastError = "No se pudieron iniciar los watchers: \(error.localizedDescription)"
        }
    }

    private func stopWatchers() {
        for process in watchers { terminate(process) }
        watchers = []
        watcherPIDs = []
        watcherStatus = .stopped
    }

    private func terminate(_ process: Process?) {
        guard let process, process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning {
                Darwin.kill(pid, SIGKILL)
            }
        }
    }

    private func sendSessionHeartbeat(_ session: SessionRecord, state: String) async {
        let bucket = "aw-watcher-worksession_\(hostname)"
        guard let base = URL(string: "http://127.0.0.1:\(ProductConfig.activityWatchPort)/api/0") else {
            return
        }
        let createPayload: [String: Any] = [
            "id": bucket,
            "type": "chosky.worksession",
            "client": ProductConfig.bundleIdentifier,
            "hostname": hostname,
            "created": ISO8601DateFormatter().string(from: session.startedAt),
            "data": [:]
        ]
        var create = URLRequest(url: base.appendingPathComponent("buckets/\(bucket)"))
        create.httpMethod = "POST"
        create.setValue("application/json", forHTTPHeaderField: "Content-Type")
        create.httpBody = try? JSONSerialization.data(withJSONObject: createPayload)
        _ = try? await URLSession.shared.data(for: create)

        let event: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "duration": 0,
            "data": [
                "session_id": session.id.uuidString,
                "project_id": session.projectID.uuidString,
                "task_id": session.taskID.uuidString,
                "state": state
            ]
        ]
        var components = URLComponents(
            url: base.appendingPathComponent("buckets/\(bucket)/heartbeat"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "pulsetime", value: "5")]
        guard let url = components?.url else { return }
        var heartbeat = URLRequest(url: url)
        heartbeat.httpMethod = "POST"
        heartbeat.setValue("application/json", forHTTPHeaderField: "Content-Type")
        heartbeat.httpBody = try? JSONSerialization.data(withJSONObject: event)
        _ = try? await URLSession.shared.data(for: heartbeat)
    }

    private func monitorSessionReadiness(_ session: SessionRecord) {
        sessionMonitor?.cancel()
        sessionMonitor = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<20 {
                if Task.isCancelled { return }
                if await self.healthCheck() {
                    guard !Task.isCancelled,
                          self.sessionTrackingActive,
                          self.activeSessionID == session.id
                    else { return }
                    self.serverStatus = .running
                    self.startWatchers()
                    await self.sendSessionHeartbeat(session, state: "running")
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func resourceURL(_ relativePath: String) throws -> URL {
        let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("ActivityWatch", isDirectory: true)
            .appendingPathComponent(relativePath)
        if let bundled, FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/ActivityWatch", isDirectory: true)
            .appendingPathComponent(relativePath)
        if FileManager.default.isExecutableFile(atPath: development.path) {
            return development
        }
        let repositoryDevelopment = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("ChoskyWorklog/Resources/ActivityWatch", isDirectory: true)
            .appendingPathComponent(relativePath)
        if FileManager.default.isExecutableFile(atPath: repositoryDevelopment.path) {
            return repositoryDevelopment
        }
        throw WorklogError.database("No se encontró el componente ActivityWatch: \(relativePath)")
    }

    private func guardedProcess(executable: URL, arguments: [String]) throws -> Process {
        let guardCandidates = [
            ProcessInfo.processInfo.environment["CHOSKY_PROCESS_GUARD_PATH"]
                .map { URL(fileURLWithPath: $0) },
            Bundle.main.executableURL?.deletingLastPathComponent()
                .appendingPathComponent("ChoskyProcessGuard"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/release/ChoskyProcessGuard"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("ChoskyWorklog/.build/release/ChoskyProcessGuard")
        ].compactMap { $0 }
        guard let guardURL = guardCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw WorklogError.database("No se encontró ChoskyProcessGuard.")
        }
        let process = Process()
        process.executableURL = guardURL
        process.arguments = [executable.path] + arguments
        return process
    }

    private func logHandle(named name: String) throws -> FileHandle {
        let url = ProductConfig.logsURL.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        return handle
    }
}
