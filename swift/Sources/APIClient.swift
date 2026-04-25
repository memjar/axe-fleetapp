// AXE Fleet Monitor — Network Layer
// Actor-isolated for thread safety. Ephemeral URLSession (no caching).
// Connects to Python daemon health server on localhost:9999.

import Foundation

// MARK: - API Client (Actor)

actor APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(host: String = "127.0.0.1", port: Int = 9999) {
        self.baseURL = URL(string: "http://\(host):\(port)")!

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    // MARK: - Public Endpoints

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
            let _ = try await fetchHealth()
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
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:       return "Invalid response from daemon"
        case .httpError(let code):   return "HTTP \(code) from daemon"
        case .decodingFailed(let e): return "Decode: \(e.localizedDescription)"
        }
    }
}
