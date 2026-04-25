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

struct StatusResponse: Codable, Sendable, Equatable {
    let fleet: [String: String]
    let web: [String: String]
    let wireguard: [String: String]
    let droplets: [String: String]

    var isEmpty: Bool {
        fleet.isEmpty && web.isEmpty && wireguard.isEmpty && droplets.isEmpty
    }

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

// MARK: - Parsed Target State

struct TargetState: Identifiable, Sendable, Equatable {
    let id: String
    let category: TargetCategory
    let displayName: String
    let state: State
    let rawValue: String

    enum State: Equatable, Sendable {
        case up, down, unknown

        init(raw: String) {
            switch raw.lowercased() {
            case "online", "up": self = .up
            case "offline", "down": self = .down
            default: self = .unknown
            }
        }
    }

    enum TargetCategory: String, Sendable, CaseIterable {
        case fleet, web, wireguard, droplets
    }
}

// MARK: - Fleet Summary

struct FleetSummary: Sendable, Equatable {
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

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - AI Summary (/summary)

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

// MARK: - FleetStatus and FleetEvent (for compatibility)

typealias FleetStatus = StatusResponse
struct FleetEvent: Identifiable, Codable, Sendable {
    let id: String
    let message: String
    let severity: String
    let source: String
    let timestamp: Date
    let eventType: String?
    let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, message, severity, source, timestamp
        case eventType = "event_type"
        case metadata
    }

    var icon: String {
        switch severity.lowercased() {
        case "critical": return "exclamationmark.triangle.fill"
        case "warning": return "exclamationmark.circle.fill"
        case "info": return "info.circle.fill"
        default: return "circle.fill"
        }
    }
}
