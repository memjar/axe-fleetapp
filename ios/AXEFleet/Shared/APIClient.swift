// AXE Fleet Monitor — API Client (iOS)
// Actor-isolated network layer. Configurable host for LAN/remote access.
// Connects to Python daemon health server.

import Foundation

actor APIClient {
    static let shared = APIClient()

    private var baseURL: URL
    private let session: URLSession

    init() {
        let host = UserDefaults.standard.string(forKey: "daemon_host") ?? "192.168.1.149"
        let port = UserDefaults.standard.integer(forKey: "daemon_port")
        let resolvedPort = port > 0 ? port : 9999
        self.baseURL = URL(string: "http://\(host):\(resolvedPort)")!

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: - Reconfigure

    func updateHost(_ host: String, port: Int = 9999) {
        self.baseURL = URL(string: "http://\(host):\(port)")!
        UserDefaults.standard.set(host, forKey: "daemon_host")
        UserDefaults.standard.set(port, forKey: "daemon_port")
    }

    // MARK: - Endpoints

    func fetchHealth() async throws -> HealthResponse {
        try await get("/health")
    }

    func fetchStatus() async throws -> StatusResponse {
        try await get("/status")
    }

    func fetchSummary() async throws -> SummaryResponse {
        try await get("/summary")
    }

    func isDaemonReachable() async -> Bool {
        do {
            _ = try await fetchHealth()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Generic GET

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        let (data, response) = try await session.data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    // MARK: - Errors

    enum APIError: LocalizedError {
        case invalidResponse
        case httpError(Int)
        case decodingFailed(Error)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid response from daemon"
            case .httpError(let code): return "HTTP \(code)"
            case .decodingFailed(let err): return "Decode error: \(err.localizedDescription)"
            }
        }
    }
}
