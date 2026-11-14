import CryptoKit
import Darwin
import Foundation
import Network
import Security

struct SharePermissions: Codable, Sendable {
    var liveTimer = true
    var todaySummary = true
    var finishedSessions = true
    var screenshots = false
    var applicationNames = true
    var windowTitles = false
    var domains = false
    var fullURLs = false
    var notes = false
    var deliverables = true
    var rates = false
    var downloads = false
    var oldHistory = false
}

@MainActor
final class SharingServer: ObservableObject {
    @Published private(set) var masterEnabled = false
    @Published private(set) var status = "Desactivado"
    @Published private(set) var shareURL: URL?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var activeConnections = 0
    @Published private(set) var lastAccess: Date?
    @Published private(set) var lastError: String?
    @Published var localOnly = true
    @Published var permissions = SharePermissions()

    private let port: NWEndpoint.Port = 8724
    private let database: WorklogDatabase
    private var listener: NWListener?
    private var expiryTask: Task<Void, Never>?
    private var tokenHash: [UInt8]?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var attempts: [String: [Date]] = [:]
    private let maximumRequestBytes = 16_384

    init(database: WorklogDatabase) {
        self.database = database
    }

    func enable(expirationHours: Int = 24) {
        guard !masterEnabled else { return }
        do {
            let rawToken = try Self.generateToken()
            tokenHash = Array(SHA256.hash(data: Data(rawToken.utf8)))
            let expiration = Date().addingTimeInterval(
                TimeInterval(max(1, min(expirationHours, 168)) * 3600)
            )
            expiresAt = expiration
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            if localOnly {
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
            }
            let listener = if localOnly {
                try NWListener(using: parameters)
            } else {
                try NWListener(using: parameters, on: port)
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.listenerStateChanged(state) }
            }
            listener.start(queue: .global(qos: .utility))
            self.listener = listener
            masterEnabled = true
            shareURL = URL(string: "http://\(localOnly ? "127.0.0.1" : Self.localAddress()):\(port.rawValue)/?token=\(rawToken)")
            status = "Iniciando"
            expiryTask?.cancel()
            expiryTask = Task { [weak self] in
                try? await Task.sleep(
                    for: .seconds(max(0, expiration.timeIntervalSinceNow))
                )
                guard !Task.isCancelled else { return }
                self?.revokeAll()
            }
            try database.addAudit(
                entityType: "sharing",
                entityID: nil,
                action: "enable",
                oldValue: "disabled",
                newValue: localOnly ? "localhost" : "lan",
                reason: "Caduca \(expiration.formatted())",
                manual: true
            )
        } catch {
            expiryTask?.cancel()
            expiryTask = nil
            listener?.cancel()
            listener = nil
            tokenHash = nil
            masterEnabled = false
            shareURL = nil
            expiresAt = nil
            lastError = error.localizedDescription
            status = "Error"
        }
    }

    func revokeAll() {
        expiryTask?.cancel()
        expiryTask = nil
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
        listener?.cancel()
        listener = nil
        tokenHash = nil
        masterEnabled = false
        shareURL = nil
        expiresAt = nil
        activeConnections = 0
        attempts.removeAll()
        status = "Desactivado"
        try? database.addAudit(
            entityType: "sharing",
            entityID: nil,
            action: "revoke_all",
            oldValue: "enabled",
            newValue: "disabled",
            reason: "Interruptor maestro",
            manual: true
        )
    }

    private func listenerStateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            status = localOnly ? "Solo este Mac" : "Red local"
            lastError = nil
        case let .failed(error):
            lastError = error.localizedDescription
            revokeAll()
            status = "Error"
        case .cancelled:
            if masterEnabled { status = "Detenido" }
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard masterEnabled else {
            connection.cancel()
            return
        }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        activeConnections = connections.count
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            if case .failed = state {
                Task { @MainActor in self?.remove(connection) }
            } else if case .cancelled = state {
                Task { @MainActor in self?.remove(connection) }
            }
        }
        connection.start(queue: .global(qos: .utility))
        receiveRequest(from: connection, accumulated: Data())
    }

    private func receiveRequest(from connection: NWConnection, accumulated: Data) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: maximumRequestBytes
        ) { [weak self, weak connection] data, _, isComplete, error in
            guard let connection else { return }
            Task { @MainActor in
                guard let self else { return }
                if error != nil {
                    self.remove(connection)
                    return
                }
                var request = accumulated
                if let data { request.append(data) }
                guard request.count <= self.maximumRequestBytes else {
                    self.send(
                        status: "431 Request Header Fields Too Large",
                        body: "La petición es demasiado grande.",
                        to: connection
                    )
                    return
                }
                let headersComplete = request.range(of: Data("\r\n\r\n".utf8)) != nil
                if headersComplete || isComplete {
                    self.respond(to: connection, data: request)
                } else {
                    self.receiveRequest(from: connection, accumulated: request)
                }
            }
        }
    }

    private func respond(to connection: NWConnection, data: Data) {
        guard masterEnabled,
              let expiresAt,
              expiresAt > Date()
        else {
            send(status: "410 Gone", body: "Acceso revocado o caducado.", to: connection)
            return
        }
        let remote = Self.remoteDescription(connection.endpoint)
        guard !rateLimited(remote) else {
            send(status: "429 Too Many Requests", body: "Demasiados intentos.", to: connection)
            logAccess(remote: remote, action: "rate_limited", allowed: false)
            return
        }
        guard let request = String(data: data, encoding: .utf8),
              request.hasPrefix("GET ")
        else {
            send(status: "400 Bad Request", body: "Petición no válida.", to: connection)
            return
        }
        let presented = Self.extractToken(from: request)
        guard let presented, validate(token: presented) else {
            registerAttempt(remote)
            send(status: "401 Unauthorized", body: "Token no válido.", to: connection)
            logAccess(remote: remote, action: "authenticate", allowed: false)
            return
        }
        do {
            let body = try dashboardHTML()
            send(status: "200 OK", body: body, to: connection)
            lastAccess = Date()
            logAccess(remote: remote, action: "view_dashboard", allowed: true)
        } catch {
            send(status: "500 Internal Server Error", body: "No se pudo preparar el panel.", to: connection)
        }
    }

    private func dashboardHTML() throws -> String {
        let allSessions = try database.sessions(limit: 5_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ProductConfig.timezone
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let sessions = allSessions.filter { session in
            if session.endedAt == nil {
                return permissions.liveTimer
            }
            guard permissions.finishedSessions else { return false }
            if permissions.oldHistory { return true }
            guard permissions.todaySummary else { return false }
            return session.startedAt < tomorrow && (session.endedAt ?? now) >= today
        }
        let formatter = DateFormatter()
        formatter.locale = ProductConfig.locale
        formatter.timeZone = ProductConfig.timezone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let rows = sessions.map { session in
            """
            <tr data-kind="\(session.endedAt == nil ? "active" : "finished")"><td>\(Self.escape(formatter.string(from: session.startedAt)))</td>
            <td>\(session.elapsed.worklogDuration)</td>
            <td>\(session.activeSeconds.worklogDuration)</td>
            <td>\(session.afkSeconds.worklogDuration)</td>
            <td>\(session.pausedSeconds.worklogDuration)</td></tr>
            """
        }.joined()
        let emptyNotice = sessions.isEmpty
            ? "<p>No hay sesiones autorizadas para mostrar con los permisos actuales.</p>"
            : ""
        return """
        <!doctype html><html lang="es"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Chosky Worklog · Acceso privado</title>
        <style>body{font:16px -apple-system;margin:40px auto;max-width:900px;padding:0 20px}
        table{width:100%;border-collapse:collapse}td,th{padding:10px;border-bottom:1px solid #bbb8;text-align:left}
        .notice{padding:12px;border-left:3px solid #5e5ce6;background:#5e5ce611}</style></head>
        <body><h1>Chosky Worklog</h1><p>Panel privado de solo lectura.</p>
        <p class="notice">Tiempo registrado, activo, AFK y pausado son métricas diferentes; no representan una puntuación de productividad.</p>
        <table><thead><tr><th>Inicio</th><th>Registrado</th><th>Activo</th><th>AFK</th><th>Pausado</th></tr></thead>
        <tbody>\(rows)</tbody></table>\(emptyNotice)
        <p>Actualizado \(Self.escape(formatter.string(from: Date()))).</p></body></html>
        """
    }

    private func send(status: String, body: String, to connection: NWConnection) {
        let data = Data(body.utf8)
        let header = [
            "HTTP/1.1 \(status)",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(data.count)",
            "Cache-Control: no-store",
            "Referrer-Policy: no-referrer",
            "X-Content-Type-Options: nosniff",
            "Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'",
            "Connection: close"
        ].joined(separator: "\r\n") + "\r\n\r\n"
        var response = Data(header.utf8)
        response.append(data)
        connection.send(
            content: response,
            contentContext: .defaultMessage,
            isComplete: true,
            completion: .contentProcessed { [weak self, weak connection] _ in
                guard let connection else { return }
                Task { @MainActor in self?.forget(connection) }
            }
        )
    }

    private func validate(token: String) -> Bool {
        guard let tokenHash else { return false }
        let candidate = Array(SHA256.hash(data: Data(token.utf8)))
        guard candidate.count == tokenHash.count else { return false }
        var difference: UInt8 = 0
        for index in candidate.indices {
            difference |= candidate[index] ^ tokenHash[index]
        }
        return difference == 0
    }

    private func rateLimited(_ remote: String) -> Bool {
        let cutoff = Date().addingTimeInterval(-60)
        let recent = (attempts[remote] ?? []).filter { $0 > cutoff }
        attempts[remote] = recent
        return recent.count >= 10
    }

    private func registerAttempt(_ remote: String) {
        attempts[remote, default: []].append(Date())
    }

    private func remove(_ connection: NWConnection) {
        connection.cancel()
        forget(connection)
    }

    private func forget(_ connection: NWConnection) {
        connections.removeValue(forKey: ObjectIdentifier(connection))
        activeConnections = connections.count
    }

    private func logAccess(remote: String, action: String, allowed: Bool) {
        try? database.addAudit(
            entityType: "share_access",
            entityID: nil,
            action: action,
            oldValue: nil,
            newValue: allowed ? "allowed" : "denied",
            reason: remote,
            manual: false
        )
    }

    private static func generateToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw WorklogError.sharing("No se pudo generar un token seguro.")
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func extractToken(from request: String) -> String? {
        let firstLine = request.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let parts = firstLine.split(separator: " ")
        if parts.count >= 2,
           let components = URLComponents(string: String(parts[1])),
           let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
            return token
        }
        for line in request.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.lowercased().hasPrefix("authorization: bearer ") {
                return String(text.dropFirst("authorization: bearer ".count))
            }
        }
        return nil
    }

    private static func localAddress() -> String {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let first = addressPointer else {
            return "127.0.0.1"
        }
        defer { freeifaddrs(addressPointer) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = cursor {
            let flags = Int32(interface.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isUp, !isLoopback,
               let address = interface.pointee.ifa_addr,
               address.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let length = socklen_t(address.pointee.sa_len)
                if getnameinfo(
                    address,
                    length,
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    let bytes = host.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
                    return String(decoding: bytes, as: UTF8.self)
                }
            }
            cursor = interface.pointee.ifa_next
        }
        return "127.0.0.1"
    }

    private static func remoteDescription(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case let .hostPort(host, _): String(describing: host)
        default: "unknown"
        }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
