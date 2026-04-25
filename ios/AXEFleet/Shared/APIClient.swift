// AXE Fleet Monitor — API Client (iOS)
// Actor-isolated network layer. Connects to axiom.com.vc cloud backend.
// Default: https://axiom.com.vc/api/fleet

import Foundation

actor APIClient {
    static let shared = APIClient()

    private var baseURL: String
    private let session: URLSession

    private init() {
        self.baseURL = UserDefaults.standard.string(forKey: "server_url")
            ?? "https://axiom.com.vc/api/fleet"

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: - Reconfigure

    func updateServer(url: String) {
        self.baseURL = url
        UserDefaults.standard.set(url, forKey: "server_url")
    }

    func getServerURL() -> String {
        return baseURL
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
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

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
        case invalidURL
        case invalidResponse
        case httpError(Int)
        case decodingFailed(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid server URL"
            case .invalidResponse: return "Invalid response from server"
            case .httpError(let code): return "HTTP \(code)"
            case .decodingFailed(let err): return "Decode error: \(err.localizedDescription)"
            }
        }
    }
}
