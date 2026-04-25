import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .invalidResponse: return "Invalid server response"
        case .decodingError(let e): return "Data error: \(e.localizedDescription)"
        }
    }
}

class APIClient {
    static let shared = APIClient()

    let baseURL: String

    init(baseURL: String? = nil) {
        self.baseURL = baseURL ?? UserDefaults.standard.string(forKey: "api_base_url") ?? "https://axiom.com.vc"
    }
    
    // MARK: - Fleet Status

    func fetchHealth() async throws -> HealthResponse {
        guard let url = URL(string: "\(baseURL)/api/fleet/health") else {
            throw APIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }

        let decoder = JSONDecoder()
        return try decoder.decode(HealthResponse.self, from: data)
    }

    func fetchStatus() async throws -> StatusResponse {
        guard let url = URL(string: "\(baseURL)/api/fleet/status") else {
            throw APIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }

        let decoder = JSONDecoder()
        return try decoder.decode(StatusResponse.self, from: data)
    }

    func fetchFleetStatus() async throws -> FleetStatus {
        try await fetchStatus()
    }
    
    // MARK: - Fleet Events
    
    func fetchEvents(since: String? = nil, limit: Int = 100) async throws -> [FleetEvent] {
        var components = URLComponents(string: "\(baseURL)/api/fleet/events")
        var queryItems: [URLQueryItem] = []
        
        if let since = since {
            queryItems.append(URLQueryItem(name: "since", value: since))
        }
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            throw APIError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        
        struct EventsResponse: Codable {
            let events: [FleetEvent]
            let total: Int
            let filtered: Int
            let timestamp: Date
        }
        
        let result = try decoder.decode(EventsResponse.self, from: data)
        return result.events
    }

    // MARK: - Configuration

    func updateServer(url: String) async {
        UserDefaults.standard.set(url, forKey: "api_base_url")
    }

    func isDaemonReachable() async -> Bool {
        do {
            _ = try await fetchHealth()
            return true
        } catch {
            return false
        }
    }
}
