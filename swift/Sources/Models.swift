// AXE Fleet Monitor — Data Models
// Matches Python daemon API response shapes from :8999 endpoints.
// All types are Codable + Sendable for safe cross-actor transfer.

import Foundation

// MARK: - /health Response

struct HealthResponse: Codable, Sendable {
    let status: String
    let version: String
    let uptimeStart: String
    let checksTotal: Int
    let checksFailed: Int
    let notificationsSent: Int
    let eventsLogged: Int
    let fleet: FleetCounts
    let services: ServiceCounts
    let web: ServiceCounts
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

struct FleetCounts: Codable, Sendable {
    let online: Int
    let offline: Int
}

struct ServiceCounts: Codable, Sendable {
    let up: Int
    let down: Int
}

// MARK: - /status Response

struct StatusResponse: Codable, Sendable, Equatable {
    let fleet: [String: String]
    let web: [String: String]
    let wireguard: [String: String]
    let droplets: [String: String]

    var isEmpty: Bool {
        fleet.isEmpty && web.isEmpty && wireguard.isEmpty && droplets.isEmpty
    }
}

// MARK: - Parsed Target State

struct TargetState: Identifiable, Equatable {
    let id: String
    let category: Category
    let displayName: String
    let state: State
    let rawValue: String

    enum Category: String, CaseIterable {
        case fleet, web, wireguard, droplets

        var sectionTitle: String {
            switch self {
            case .fleet:     return "FLEET MACHINES"
            case .web:       return "WEB SERVICES"
            case .wireguard: return "WIREGUARD"
            case .droplets:  return "DROPLETS"
            }
        }
    }

    enum State: Equatable {
        case up, down, unknown

        init(raw: String) {
            switch raw.lowercased() {
            case "online", "up": self = .up
            case "offline", "down": self = .down
            default: self = .unknown
            }
        }
    }
}

// MARK: - Fleet Summary (Derived)

struct FleetSummary: Equatable {
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
        return Int((Double(totalHealthy) / Double(totalTargets)) * 100)
    }

    static let empty = FleetSummary(
        machinesOnline: 0, machinesOffline: 0,
        servicesUp: 0, servicesDown: 0,
        webUp: 0, webDown: 0,
        totalTargets: 0, totalHealthy: 0
    )
}

// MARK: - State Change Event

struct StateChange: Identifiable {
    let id = UUID()
    let target: String
    let from: TargetState.State
    let to: TargetState.State
    let timestamp: Date
}

// MARK: - Connection State

enum ConnectionState: Equatable {
    case connecting
    case connected
    case disconnected
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - StatusResponse Parsing

extension StatusResponse {
    func allTargets() -> [TargetState] {
        var targets: [TargetState] = []

        for (key, value) in fleet.sorted(by: { $0.key < $1.key }) {
            targets.append(TargetState(
                id: key, category: .fleet,
                displayName: Self.cleanName(key, prefix: "fleet_"),
                state: .init(raw: value), rawValue: value
            ))
        }
        for (key, value) in web.sorted(by: { $0.key < $1.key }) {
            targets.append(TargetState(
                id: key, category: .web,
                displayName: Self.cleanName(key, prefix: "web_"),
                state: .init(raw: value), rawValue: value
            ))
        }
        for (key, value) in wireguard.sorted(by: { $0.key < $1.key }) {
            targets.append(TargetState(
                id: key, category: .wireguard,
                displayName: Self.cleanName(key, prefix: "wg_"),
                state: .init(raw: value), rawValue: value
            ))
        }
        for (key, value) in droplets.sorted(by: { $0.key < $1.key }) {
            targets.append(TargetState(
                id: key, category: .droplets,
                displayName: Self.cleanName(key, prefix: "droplet_"),
                state: .init(raw: value), rawValue: value
            ))
        }

        return targets
    }

    private static func cleanName(_ key: String, prefix: String) -> String {
        var name = key
        if name.hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        return name
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    func computeSummary() -> FleetSummary {
        let targets = allTargets()

        let fleetTargets = targets.filter { $0.category == .fleet }
        let webTargets = targets.filter { $0.category == .web }
        let otherTargets = targets.filter { $0.category == .wireguard || $0.category == .droplets }

        let machinesOnline = fleetTargets.filter { $0.state == .up }.count
        let machinesOffline = fleetTargets.filter { $0.state == .down }.count
        let webUp = webTargets.filter { $0.state == .up }.count
        let webDown = webTargets.filter { $0.state == .down }.count
        let svcUp = otherTargets.filter { $0.state == .up }.count
        let svcDown = otherTargets.filter { $0.state == .down }.count

        return FleetSummary(
            machinesOnline: machinesOnline, machinesOffline: machinesOffline,
            servicesUp: svcUp, servicesDown: svcDown,
            webUp: webUp, webDown: webDown,
            totalTargets: targets.count,
            totalHealthy: machinesOnline + webUp + svcUp
        )
    }
}

// MARK: - AI Summary (Local Model via Carmack Pattern)

struct SummaryResponse: Codable, Sendable {
    let fleetSummary: String
    let lastGenerated: String?
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
