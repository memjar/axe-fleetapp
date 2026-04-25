// AXE Fleet Monitor — Data Models
// Shared between macOS and iOS. Matches Python daemon API on port 9999.
// All types are Codable + Sendable for safe cross-actor transfer.

import Foundation

// MARK: - Health Endpoint (/health)

struct HealthResponse: Codable, Sendable {
    let status: String
    let version: String
    let uptimeStart: String
    let checksTotal: Int
    let checksFailed: Int
    let notificationsSent: Int
    let eventsLogged: Int
    let fleet: FleetCount
    let services: ServiceCount
    let web: WebCount
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case status, version, timestamp, fleet, services, web
        case uptimeStart = "uptime_start"
        case checksTotal = "checks_total"
        case checksFailed = "checks_failed"
        case notificationsSent = "notifications_sent"
        case eventsLogged = "events_logged"
    }
}

struct FleetCount: Codable, Sendable {
    let online: Int
    let offline: Int
}

struct ServiceCount: Codable, Sendable {
    let up: Int
    let down: Int
}

struct WebCount: Codable, Sendable {
    let up: Int
    let down: Int
}

// MARK: - Status Endpoint (/status)

struct StatusResponse: Codable, Sendable {
    let fleet: [String: String]
    let web: [String: String]
    let wireguard: [String: String]
    let droplets: [String: String]

    func allTargets() -> [TargetState] {
        var result: [TargetState] = []

        for (key, value) in fleet {
            let name = key
                .replacingOccurrences(of: "fleet_", with: "")
                .replacingOccurrences(of: "_ping", with: "")
                .replacingOccurrences(of: "_ssh", with: " SSH")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            result.append(TargetState(id: key, category: .fleet, displayName: name, state: TargetState.parseState(value), rawValue: value))
        }

        for (key, value) in web {
            let name = key
                .replacingOccurrences(of: "web_", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            result.append(TargetState(id: key, category: .web, displayName: name, state: TargetState.parseState(value), rawValue: value))
        }

        for (key, value) in wireguard {
            let name = key
                .replacingOccurrences(of: "wg_", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            result.append(TargetState(id: key, category: .wireguard, displayName: name, state: TargetState.parseState(value), rawValue: value))
        }

        for (key, value) in droplets {
            let name = key
                .replacingOccurrences(of: "droplet_", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            result.append(TargetState(id: key, category: .droplets, displayName: name, state: TargetState.parseState(value), rawValue: value))
        }

        return result.sorted { $0.displayName < $1.displayName }
    }

    func computeSummary() -> FleetSummary {
        let targets = allTargets()
        let fleetTargets = targets.filter { $0.category == .fleet }
        let webTargets = targets.filter { $0.category == .web }
        let serviceTargets = targets.filter { $0.category != .fleet && $0.category != .web }

        return FleetSummary(
            machinesOnline: fleetTargets.filter { $0.state == .up }.count,
            machinesOffline: fleetTargets.filter { $0.state == .down }.count,
            servicesUp: serviceTargets.filter { $0.state == .up }.count,
            servicesDown: serviceTargets.filter { $0.state == .down }.count,
            webUp: webTargets.filter { $0.state == .up }.count,
            webDown: webTargets.filter { $0.state == .down }.count,
            totalTargets: targets.count,
            totalHealthy: targets.filter { $0.state == .up }.count
        )
    }
}

// MARK: - Parsed Target State

struct TargetState: Identifiable, Sendable {
    let id: String
    let category: TargetCategory
    let displayName: String
    let state: State
    let rawValue: String

    enum State: String, Sendable {
        case up, down, unknown
    }

    enum TargetCategory: String, Sendable, CaseIterable {
        case fleet, web, wireguard, droplets
    }

    static func parseState(_ raw: String) -> State {
        switch raw.lowercased() {
        case "up", "online", "healthy", "running": return .up
        case "down", "offline", "unhealthy", "stopped", "unreachable": return .down
        default: return .unknown
        }
    }
}

// MARK: - Fleet Summary

struct FleetSummary: Sendable {
    let machinesOnline: Int
    let machinesOffline: Int
    let servicesUp: Int
    let servicesDown: Int
    let webUp: Int
    let webDown: Int
    let totalTargets: Int
    let totalHealthy: Int

    var healthPercent: Int {
        guard totalTargets > 0 else { return 0 }
        return Int(Double(totalHealthy) / Double(totalTargets) * 100)
    }

    static let empty = FleetSummary(
        machinesOnline: 0, machinesOffline: 0,
        servicesUp: 0, servicesDown: 0,
        webUp: 0, webDown: 0,
        totalTargets: 0, totalHealthy: 0
    )
}

// MARK: - State Change Events

struct StateChange: Identifiable, Sendable {
    let id = UUID()
    let target: String
    let from: TargetState.State
    let to: TargetState.State
    let timestamp: Date
}

// MARK: - Connection State

enum ConnectionState: Sendable, Equatable {
    case connecting
    case connected
    case disconnected
    case error(String)
}

// MARK: - AI Summary (/summary)

struct SummaryResponse: Codable, Sendable {
    let fleetSummary: String
    let lastGenerated: Int?
    let incidents: [IncidentEntry]
    let modelAvailable: Bool
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case fleetSummary = "fleet_summary"
        case lastGenerated = "last_generated"
        case incidents
        case modelAvailable = "model_available"
        case timestamp
    }
}

struct IncidentEntry: Codable, Sendable, Identifiable {
    let target: String
    let transition: String
    let analysis: String
    let timestamp: String

    var id: String { "\(target)-\(timestamp)" }
}
