// AXE Fleet Monitor — Dashboard (iOS)
// Main fleet overview: connection status, summary cards, target list.
// Pull-to-refresh. Grouped by category.

import SwiftUI

struct DashboardView: View {
    @ObservedObject var monitor: FleetMonitor

    var body: some View {
        NavigationStack {
            ZStack {
                AXETheme.background.ignoresSafeArea()

                switch monitor.connectionState {
                case .connected:
                    connectedView
                case .connecting:
                    connectingView
                case .disconnected:
                    disconnectedView
                case .error(let msg):
                    errorView(msg)
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text("AXE FLEET")
                            .font(AXETheme.titleFont)
                            .foregroundColor(AXETheme.gold)
                        connectionDot
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { monitor.forceRefresh() }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(AXETheme.gold)
                    }
                }
            }
            .toolbarBackground(AXETheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Connected

    private var connectedView: some View {
        ScrollView {
            VStack(spacing: AXETheme.sectionSpacing) {
                summaryCards
                    .padding(.horizontal)

                if let health = monitor.health {
                    healthBanner(health)
                        .padding(.horizontal)
                }

                ForEach(TargetState.TargetCategory.allCases, id: \.rawValue) { category in
                    let targets = monitor.targets.filter { $0.category == category }
                    if !targets.isEmpty {
                        categorySection(category: category, targets: targets)
                    }
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            monitor.forceRefresh()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            StatCard(
                title: "MACHINES",
                value: "\(monitor.summary.machinesOnline)",
                subtitle: "\(monitor.summary.machinesOffline) offline",
                color: monitor.summary.machinesOffline > 0 ? AXETheme.statusDown : AXETheme.statusUp
            )
            StatCard(
                title: "SERVICES",
                value: "\(monitor.summary.servicesUp)",
                subtitle: "\(monitor.summary.servicesDown) down",
                color: monitor.summary.servicesDown > 0 ? AXETheme.statusDown : AXETheme.statusUp
            )
            StatCard(
                title: "WEB",
                value: "\(monitor.summary.webUp)",
                subtitle: "\(monitor.summary.webDown) down",
                color: monitor.summary.webDown > 0 ? AXETheme.statusDown : AXETheme.statusUp
            )
            StatCard(
                title: "HEALTH",
                value: "\(monitor.summary.healthPercent)%",
                subtitle: "\(monitor.summary.totalTargets) targets",
                color: monitor.summary.healthPercent >= 80 ? AXETheme.statusUp :
                       monitor.summary.healthPercent >= 50 ? AXETheme.statusFlapping : AXETheme.statusDown
            )
        }
    }

    // MARK: - Health Banner

    private func healthBanner(_ health: HealthResponse) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("v\(health.version)")
                    .font(AXETheme.captionFont)
                    .foregroundColor(AXETheme.gold)
                Text("\(health.checksTotal) checks | \(health.notificationsSent) alerts")
                    .font(AXETheme.captionFont)
                    .foregroundColor(AXETheme.textSecondary)
            }
            Spacer()
            if let lastUpdate = monitor.lastUpdate {
                Text(timeAgo(lastUpdate))
                    .font(AXETheme.captionFont)
                    .foregroundColor(AXETheme.textSecondary)
            }
        }
        .padding(12)
        .background(AXETheme.surface)
        .cornerRadius(AXETheme.cornerRadius)
    }

    // MARK: - Category Section

    private func categorySection(category: TargetState.TargetCategory, targets: [TargetState]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(category.rawValue.uppercased())
                    .font(AXETheme.headlineFont)
                    .foregroundColor(AXETheme.gold)
                Spacer()
                let upCount = targets.filter { $0.state == .up }.count
                Text("\(upCount)/\(targets.count)")
                    .font(AXETheme.captionFont)
                    .foregroundColor(AXETheme.textSecondary)
            }
            .padding(.horizontal)

            VStack(spacing: 1) {
                ForEach(targets, id: \.id) { target in
                    TargetRow(target: target)
                }
            }
            .background(AXETheme.surface)
            .cornerRadius(AXETheme.cornerRadius)
            .padding(.horizontal)
        }
    }

    // MARK: - Connection States

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(AXETheme.gold)
                .scaleEffect(1.5)
            Text("CONNECTING TO DAEMON")
                .font(AXETheme.headlineFont)
                .foregroundColor(AXETheme.textSecondary)
        }
    }

    private var disconnectedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundColor(AXETheme.statusDown)
            Text("[-] DAEMON UNREACHABLE")
                .font(AXETheme.titleFont)
                .foregroundColor(AXETheme.statusDown)
            Text("Check that axe-fleet-notify is running\non your fleet network")
                .font(AXETheme.bodyFont)
                .foregroundColor(AXETheme.textSecondary)
                .multilineTextAlignment(.center)
            Button(action: { monitor.forceRefresh() }) {
                Text("RETRY CONNECTION")
                    .font(AXETheme.headlineFont)
                    .foregroundColor(AXETheme.background)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AXETheme.gold)
                    .cornerRadius(AXETheme.cornerRadius)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(AXETheme.statusFlapping)
            Text("[!] CONNECTION ERROR")
                .font(AXETheme.titleFont)
                .foregroundColor(AXETheme.statusFlapping)
            Text(message)
                .font(AXETheme.captionFont)
                .foregroundColor(AXETheme.textSecondary)
            Button("RETRY") { monitor.forceRefresh() }
                .font(AXETheme.headlineFont)
                .foregroundColor(AXETheme.gold)
        }
    }

    // MARK: - Connection Dot

    private var connectionDot: some View {
        Circle()
            .fill(connectionColor)
            .frame(width: 8, height: 8)
    }

    private var connectionColor: Color {
        switch monitor.connectionState {
        case .connected: return AXETheme.statusUp
        case .connecting: return AXETheme.statusFlapping
        case .disconnected: return AXETheme.statusDown
        case .error: return AXETheme.statusDown
        }
    }

    // MARK: - Helpers

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AXETheme.captionFont)
                .foregroundColor(AXETheme.textSecondary)
            Text(value)
                .font(AXETheme.statFont)
                .foregroundColor(color)
            Text(subtitle)
                .font(AXETheme.captionFont)
                .foregroundColor(AXETheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AXETheme.cardPadding)
        .background(AXETheme.surface)
        .cornerRadius(AXETheme.cornerRadius)
    }
}

// MARK: - Target Row

struct TargetRow: View {
    let target: TargetState

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(AXETheme.statusColor(for: target.state))
                .frame(width: 8, height: 8)
            Text(AXETheme.statusLabel(for: target.state))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(AXETheme.statusColor(for: target.state))
                .frame(width: 28, alignment: .leading)
            Text(target.displayName)
                .font(AXETheme.bodyFont)
                .foregroundColor(AXETheme.textPrimary)
            Spacer()
            Text(target.rawValue.uppercased())
                .font(AXETheme.captionFont)
                .foregroundColor(AXETheme.textSecondary)
        }
        .padding(.horizontal, AXETheme.cardPadding)
        .padding(.vertical, 10)
    }
}
