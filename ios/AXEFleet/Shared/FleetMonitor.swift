import Foundation

class FleetMonitor: ObservableObject {
    @Published private(set) var health: HealthResponse?
    @Published private(set) var status: StatusResponse?
    @Published private(set) var summary: FleetSummary = .empty
    @Published private(set) var targets: [TargetState] = []
    @Published private(set) var connectionState: ConnectionState = .connecting
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var recentChanges: [StateChange] = []
    @Published private(set) var aiSummary: SummaryResponse?
    @Published var events: [FleetEvent] = []
    @Published var isConnected = false
    @Published var error: String?
    @Published var newEventCount: Int = 0

    let apiClient = APIClient()
    private var statusTimer: Timer?
    private var eventTimer: Timer?
    private var lastEventTimestamp: String?
    private var seenEventIds: Set<String> = []
    private var previousStatus: StatusResponse?
    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 3
    private let maxChangeHistory = 50
    
    // MARK: - Status Polling (30s)
    
    func startPolling(interval: TimeInterval = 30) {
        stopPolling()
        statusTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.fetchStatus() }
        }
        Task { await fetchStatus() }
    }
    
    func stopPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
    }
    
    // MARK: - Event Polling (5s)
    
    func startEventPolling(interval: TimeInterval = 5) {
        eventTimer?.invalidate()
        eventTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.fetchNewEvents() }
        }
        Task { await fetchNewEvents() }
    }
    
    func stopEventPolling() {
        eventTimer?.invalidate()
        eventTimer = nil
    }
    
    // MARK: - Fetch Status

    @MainActor
    func fetchStatus() async {
        do {
            let health = try await apiClient.fetchHealth()
            let status = try await apiClient.fetchStatus()

            self.health = health
            self.status = status
            self.targets = status.allTargets()
            self.summary = status.computeSummary()
            self.lastUpdate = Date()
            self.connectionState = .connected
            self.isConnected = true
            self.error = nil
            self.consecutiveFailures = 0

            if let prev = self.previousStatus {
                self.detectChanges(from: prev, to: status)
            }
            self.previousStatus = status
        } catch {
            self.error = error.localizedDescription
            self.isConnected = false
            self.consecutiveFailures += 1
            if self.consecutiveFailures >= self.maxConsecutiveFailures {
                self.connectionState = .disconnected
            } else {
                self.connectionState = .error(error.localizedDescription)
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

            NotificationService.shared.notifyStateChange(
                target: target.displayName,
                from: oldState,
                to: target.state
            )
        }

        // Cap history
        if recentChanges.count > maxChangeHistory {
            recentChanges = Array(recentChanges.prefix(maxChangeHistory))
        }
    }
    
    // MARK: - Fetch New Events
    
    @MainActor
    func fetchNewEvents() async {
        do {
            let newEvents = try await apiClient.fetchEvents(since: lastEventTimestamp)
            
            for event in newEvents {
                guard !seenEventIds.contains(event.id) else { continue }
                seenEventIds.insert(event.id)
                events.insert(event, at: 0)
                newEventCount += 1
                
                // Fire notification + haptic based on severity
                switch event.severity.lowercased() {
                case "critical":
                    sendNotification(for: event, critical: true)
                    Haptics.notification(.error)
                case "warning":
                    sendNotification(for: event, critical: false)
                    Haptics.notification(.warning)
                default:
                    Haptics.impact(.light)
                }
            }
            
            // Update cursor
            if let latest = newEvents.first {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                lastEventTimestamp = formatter.string(from: latest.timestamp)
            }
            
            // Cap events at 200
            if events.count > 200 {
                events = Array(events.prefix(200))
            }
            if seenEventIds.count > 300 {
                seenEventIds = Set(events.prefix(200).map { $0.id })
            }
        } catch {
            print("[AXE] Event fetch error: \(error)")
        }
    }
    
    // MARK: - Notifications
    
    private func sendNotification(for event: FleetEvent, critical: Bool) {
        NotificationService.shared.sendNotification(
            title: critical ? "🚨 Fleet Alert" : "⚠️ Fleet Warning",
            body: event.message,
            data: ["event_id": event.id, "severity": event.severity, "source": event.source]
        )
    }
    
    // MARK: - Actions
    
    func refreshStatus() async {
        await fetchStatus()
        await fetchNewEvents()
    }
    
    func clearEvents() {
        events.removeAll()
        seenEventIds.removeAll()
        newEventCount = 0
    }
    
    func resetNewEventCount() {
        newEventCount = 0
    }

    func forceRefresh() {
        Task {
            await fetchStatus()
            await fetchNewEvents()
        }
    }
}
