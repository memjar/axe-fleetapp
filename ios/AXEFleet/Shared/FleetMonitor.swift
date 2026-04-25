// AXE Fleet Monitor — Polling Engine (iOS)
// ObservableObject drives SwiftUI views. Polls daemon every 15s.
// State change detection diffs previous vs current StatusResponse.
// Fires local notifications on transitions.

import Foundation
import Combine
import UserNotifications

@MainActor
final class FleetMonitor: ObservableObject {
    // MARK: - Published State

    @Published private(set) var health: HealthResponse?
    @Published private(set) var status: StatusResponse?
    @Published private(set) var summary: FleetSummary = .empty
    @Published private(set) var targets: [TargetState] = []
    @Published private(set) var connectionState: ConnectionState = .connecting
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var recentChanges: [StateChange] = []
    @Published private(set) var aiSummary: SummaryResponse?

    // MARK: - Configuration

    private let maxChangeHistory = 50
    private let maxConsecutiveFailures = 3
    private let summaryPollInterval: TimeInterval = 60

    // MARK: - Internal State

    private var pollTimer: Timer?
    private var previousStatus: StatusResponse?
    private var consecutiveFailures = 0
    private var summaryPollCount = 0

    // MARK: - Lifecycle

    func startPolling() {
        connectionState = .connecting
        triggerPoll()

        let interval = TimeInterval(UserDefaults.standard.integer(forKey: "poll_interval"))
        let resolvedInterval = interval > 0 ? interval : 15

        pollTimer = Timer.scheduledTimer(
            withTimeInterval: resolvedInterval,
            repeats: true
        ) { [weak self] _ in
            self?.triggerPoll()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func forceRefresh() {
        triggerPoll()
    }

    // MARK: - Poll Dispatch

    private func triggerPoll() {
        Task { await executePoll() }
    }

    private func executePoll() async {
        do {
            async let healthReq = APIClient.shared.fetchHealth()
            async let statusReq = APIClient.shared.fetchStatus()
            let (h, s) = try await (healthReq, statusReq)

            await MainActor.run {
                self.health = h
                self.status = s
                self.targets = s.allTargets()
                self.summary = s.computeSummary()
                self.lastUpdate = Date()
                self.connectionState = .connected
                self.consecutiveFailures = 0

                if let prev = self.previousStatus {
                    self.detectChanges(from: prev, to: s)
                }
                self.previousStatus = s
                self.summaryPollCount += 1
            }

            // Fetch AI summary at slower cadence (every 4th poll)
            if summaryPollCount % 4 == 1 {
                if let s = try? await APIClient.shared.fetchSummary() {
                    await MainActor.run { self.aiSummary = s }
                }
            }
        } catch {
            await MainActor.run {
                self.consecutiveFailures += 1
                if self.consecutiveFailures >= self.maxConsecutiveFailures {
                    self.connectionState = .disconnected
                } else {
                    self.connectionState = .error(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - State Change Detection

    private func detectChanges(from old: StatusResponse, to new: StatusResponse) {
        let oldMap = Dictionary(
            old.allTargets().map { ($0.id, $0.state) },
            uniquingKeysWith: { first, _ in first }
        )

        for target in new.allTargets() {
            guard let oldState = oldMap[target.id], oldState != target.state else {
                continue
            }

            let change = StateChange(
                target: target.displayName,
                from: oldState,
                to: target.state,
                timestamp: Date()
            )
            recentChanges.insert(change, at: 0)
            sendLocalNotification(target: target.displayName, from: oldState, to: target.state)
        }

        if recentChanges.count > maxChangeHistory {
            recentChanges = Array(recentChanges.prefix(maxChangeHistory))
        }
    }

    // MARK: - Local Notifications

    private func sendLocalNotification(target: String, from: TargetState.State, to: TargetState.State) {
        guard UserDefaults.standard.bool(forKey: "notifications_enabled") != false else { return }

        let content = UNMutableNotificationContent()
        content.threadIdentifier = "axe-fleet"

        if to == .down {
            content.title = "[AXE] \(target) went OFFLINE"
            content.body = "State changed from \(from.rawValue.uppercased()) to OFFLINE"
            content.categoryIdentifier = "AXE_CRITICAL"
            content.sound = .default
        } else if to == .up && from == .down {
            content.title = "[AXE] \(target) RECOVERED"
            content.body = "State changed from OFFLINE to ONLINE"
            content.categoryIdentifier = "AXE_INFO"
            content.sound = .default
        } else {
            return
        }

        let request = UNNotificationRequest(
            identifier: "state-\(target)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}
