import Foundation

// V10_METADATA_CACHE
// Shared requests to the same public metadata endpoint reuse one network task.
// The proxy/FrameXTV credentials, safety filtering, player and source routing
// are not modified. Only successful, small GET metadata responses are cached.
actor XSMetadataRequestCache {
    static let shared = XSMetadataRequestCache()

    private struct Entry {
        let data: Data
        let response: URLResponse
        let received: Date
    }

    private var cached: [URL: Entry] = [:]
    private var lru: [URL] = []
    private var pending: [URL: Task<(Data, URLResponse), Error>] = [:]
    private let ttl: TimeInterval = 95

    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard request.httpMethod == "GET" || request.httpMethod == nil,
              let url = request.url else {
            return try await URLSession.shared.data(for: request)
        }
        if let entry = cached[url], Date().timeIntervalSince(entry.received) < ttl {
            lru.removeAll { $0 == url }
            lru.append(url)
            return (entry.data, entry.response)
        }
        if let job = pending[url] {
            return try await job.value
        }
        let job = Task.detached(priority: .userInitiated) {
            try await URLSession.shared.data(for: request)
        }
        pending[url] = job
        do {
            let result = try await job.value
            pending[url] = nil
            if let http = result.1 as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               result.0.count < 1_500_000 {
                cached[url] = Entry(data: result.0, response: result.1, received: Date())
                lru.removeAll { $0 == url }
                lru.append(url)
                while lru.count > 90 {
                    let oldest = lru.removeFirst()
                    cached[oldest] = nil
                }
            }
            return result
        } catch {
            pending[url] = nil
            throw error
        }
    }
}
