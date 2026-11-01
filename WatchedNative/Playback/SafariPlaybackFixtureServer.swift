#if DEBUG
import Foundation
import Network

/// Loopback HTML for testing the real system Safari service. Not compiled into release builds.
final class SafariPlaybackFixtureServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "watched.safari-fixture")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    func start(target: URL, completion: @escaping @MainActor (URL?) -> Void) {
        queue.async { [self] in
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    switch state {
                    case .ready:
                        guard let port = listener?.port else { return }
                        var components = URLComponents(url: target, resolvingAgainstBaseURL: false)!
                        components.scheme = "http"; components.host = "127.0.0.1"; components.port = Int(port.rawValue)
                        let url = components.url
                        Task { @MainActor in completion(url) }
                    case .failed:
                        self?.listener?.cancel()
                        Task { @MainActor in completion(nil) }
                    default: break
                    }
                }
                listener.start(queue: queue)
            } catch { Task { @MainActor in completion(nil) } }
        }
    }

    private func serve(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            let line = data.flatMap { String(data: $0, encoding: .utf8) }?.components(separatedBy: "\r\n").first ?? ""
            let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let escaped = path.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            let browse = path.hasPrefix("/browse/")
            let html = """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{background:#111;color:white;font:18px system-ui;padding:30px}a{color:#ff4a55;display:block;padding:24px 0}</style></head><body>
            <h2>\(browse ? "Offline browser navigation fixture" : "Offline system Safari fixture")</h2><p>\(escaped)</p>
            <a href="/browse/movie/1400940">Website back</a><p>Use Safari's Close button to return to the native app.</p></body></html>
            """
            let body = Data(html.utf8)
            let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
            connection.send(content: Data(headers.utf8) + body, completion: .contentProcessed { [weak self] _ in
                connection.cancel()
                self?.queue.async { [weak self] in self?.connections.removeValue(forKey: key) }
            })
        }
    }

    func stop() {
        queue.async { [self] in
            listener?.cancel(); listener = nil
            for connection in connections.values { connection.cancel() }
            connections.removeAll()
        }
    }
    deinit { listener?.cancel() }
}
#endif
