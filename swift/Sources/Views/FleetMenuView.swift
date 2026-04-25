// AXE Fleet Monitor — Main Popover View
// 380x520 popover with header, summary cards, collapsible sections, events, footer.
// AXE dark theme. No emojis. Text identifiers only.

import SwiftUI

struct FleetMenuView: View {
    @ObservedObject var monitor: FleetMonitor

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            if monitor.connectionState.isConnected {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: AXETheme.spacing) {
                        summaryCards

                        // MARK: - AI Fleet Summary
                        if let summary = monitor.aiSummary {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("[AI]")
                                        .font(AXETheme.captionFont)
                                        .foregroundColor(AXETheme.gold)
                                    Text("FLEET ANALYSIS")
                                        .font(AXETheme.captionFont)
                                        .foregroundColor(AXETheme.gold)
                                    Spacer()
                                    Circle()
                                        .fill(summary.modelAvailable ? AXETheme.statusUp : AXETheme.statusUnknown)
                                        .frame(width: 5, height: 5)
                                    Text(summary.modelAvailable ? "LOCAL" : "FALLBACK")
                                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                                        .foregroundColor(AXETheme.textSecondary)
                                }

                                Text(summary.fleetSummary)
                                    .font(AXETheme.bodyFont)
                                    .foregroundColor(AXETheme.textPrimary)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)

                                if !summary.incidents.isEmpty {
                                    Divider()
                                        .background(AXETheme.textSecondary)
                                    ForEach(summary.incidents.prefix(3)) { incident in
                                        HStack(alignment: .top, spacing: 6) {
                                            Text("[>]")
                                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                                .foregroundColor(AXETheme.gold)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(incident.target)
                                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                                    .foregroundColor(AXETheme.textPrimary)
                                                Text(incident.analysis)
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundColor(AXETheme.textSecondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(10)
                            .background(AXETheme.surface.opacity(0.8))
                            .cornerRadius(AXETheme.cornerRadius)
                        }

                        categorySection(.fleet)
                        categorySection(.web)
                        categorySection(.wireguard)
                        categorySection(.droplets)
                        recentChangesSection
                    }
                    .padding(AXETheme.padding)
                }
            } else {
                disconnectedView
            }

            footerBar
        }
        .frame(width: AXETheme.popoverWidth, height: AXETheme.popoverHeight)
        .background(AXETheme.background)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("AXE FLEET")
                .font(AXETheme.titleFont)
                .foregroundColor(AXETheme.gold)

            Spacer()

            Circle()
                .fill(connectionColor)
                .frame(width: 6, height: 6)
                .padding(.trailing, 4)

            Button(action: { monitor.forceRefresh() }) {
                Text("[~]")
                    .font(AXETheme.captionFont)
                    .foregroundColor(AXETheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AXETheme.padding)
        .padding(.vertical, 8)
        .background(AXETheme.surface)
    }

    private var connectionColor: Color {
        switch monitor.connectionState {
        case .connected:    return AXETheme.statusUp
        case .connecting:   return AXETheme.statusFlapping
        case .disconnected: return AXETheme.statusDown
        case .error:        return AXETheme.statusFlapping
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: AXETheme.spacing) {
            StatCard(
                label: "MACHINES",
                value: "\(monitor.summary.machinesOnline)",
                color: monitor.summary.machinesOffline > 0 ? AXETheme.statusFlapping : AXETheme.statusUp
            )
            StatCard(
                label: "SERVICES",
                value: "\(monitor.summary.servicesUp)",
                color: monitor.summary.servicesDown > 0 ? AXETheme.statusFlapping : AXETheme.statusUp
            )
            StatCard(
                label: "WEB",
                value: "\(monitor.summary.webUp)",
                color: monitor.summary.webDown > 0 ? AXETheme.statusFlapping : AXETheme.statusUp
            )
            StatCard(
                label: "HEALTH",
                value: "\(monitor.summary.healthPercent)%",
                color: healthColor
            )
        }
    }

    private var healthColor: Color {
        let pct = monitor.summary.healthPercent
        if pct >= 90 { return AXETheme.statusUp }
        if pct >= 50 { return AXETheme.statusFlapping }
        return AXETheme.statusDown
    }

    // MARK: - Category Section

    @ViewBuilder
    private func categorySection(_ category: TargetState.Category) -> some View {
        let items = monitor.targets.filter { $0.category == category }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(category.sectionTitle)
                    .font(AXETheme.captionFont)
                    .foregroundColor(AXETheme.gold)
                    .padding(.top, 4)

                ForEach(items) { target in
                    ServiceRow(target: target)
                }
            }
        }
    }

    // MARK: - Recent Changes

    @ViewBuilder
    private var recentChangesSection: some View {
        if !monitor.recentChanges.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("RECENT EVENTS")
                    .font(AXETheme.captionFont)
                    .foregroundColor(AXETheme.gold)
                    .padding(.top, 4)

                ForEach(monitor.recentChanges.prefix(5)) { change in
                    HStack(spacing: 4) {
                        Text(AXETheme.stateChangeLabel(for: change.to))
                            .font(AXETheme.captionFont)
                            .foregroundColor(AXETheme.statusColor(for: change.to))
                            .frame(width: 52, alignment: .leading)

                        Text(change.target)
                            .font(AXETheme.captionFont)
                            .foregroundColor(AXETheme.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text(Self.timeAgo(change.timestamp))
                            .font(AXETheme.captionFont)
                            .foregroundColor(AXETheme.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Disconnected State

    private var disconnectedView: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("[-] DAEMON UNREACHABLE")
                .font(AXETheme.titleFont)
                .foregroundColor(AXETheme.statusDown)

            Text("Fleet notify daemon not responding on :8999")
                .font(AXETheme.captionFont)
                .foregroundColor(AXETheme.textSecondary)
                .multilineTextAlignment(.center)

            if case .error(let msg) = monitor.connectionState {
                Text(msg)
                    .font(AXETheme.captionFont)
                    .foregroundColor(AXETheme.textSecondary)
                    .lineLimit(2)
                    .padding(.horizontal)
            }

            Button(action: { monitor.forceRefresh() }) {
                Text("[RETRY]")
                    .font(AXETheme.bodyFont)
                    .foregroundColor(AXETheme.gold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(AXETheme.surfaceLight)
                    .cornerRadius(AXETheme.cornerRadius)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            if let lastUpdate = monitor.lastUpdate {
                Text("Updated: \(Self.timeAgo(lastUpdate))")
                    .font(AXETheme.captionFont)
                    .foregroundColor(AXETheme.textSecondary)
            } else {
                Text("Connecting...")
                    .font(AXETheme.captionFont)
                    .foregroundColor(AXETheme.textSecondary)
            }

            Spacer()

            if let health = monitor.health {
                Text("v\(health.version)")
                    .font(AXETheme.captionFont)
                    .foregroundColor(AXETheme.textSecondary)
                    .padding(.trailing, 4)
            }

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("[QUIT]")
                    .font(AXETheme.captionFont)
                    .foregroundColor(AXETheme.statusDown)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AXETheme.padding)
        .padding(.vertical, 6)
        .background(AXETheme.surface)
    }

    // MARK: - Helpers

    static func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AXETheme.statFont)
                .foregroundColor(color)
            Text(label)
                .font(AXETheme.captionFont)
                .foregroundColor(AXETheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(AXETheme.surface)
        .cornerRadius(AXETheme.cornerRadius)
    }
}
