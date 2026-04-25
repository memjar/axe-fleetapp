// AXE Fleet Monitor — Events Timeline (iOS)
// Shows recent state changes with timestamps.

import SwiftUI

struct EventsView: View {
    @ObservedObject var monitor: FleetMonitor

    var body: some View {
        NavigationStack {
            ZStack {
                AXETheme.background.ignoresSafeArea()

                if monitor.recentChanges.isEmpty {
                    emptyState
                } else {
                    eventsList
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text("EVENTS")
                            .font(AXETheme.titleFont)
                            .foregroundColor(AXETheme.gold)
                        Text("\(monitor.recentChanges.count)")
                            .font(AXETheme.captionFont)
                            .foregroundColor(AXETheme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AXETheme.surface)
                            .cornerRadius(4)
                    }
                }
            }
            .toolbarBackground(AXETheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private var eventsList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(monitor.recentChanges) { change in
                    eventRow(change)
                }
            }
            .background(AXETheme.surface)
            .cornerRadius(AXETheme.cornerRadius)
            .padding()
        }
    }

    private func eventRow(_ change: StateChange) -> some View {
        HStack(spacing: 12) {
            // Direction indicator
            VStack(spacing: 2) {
                Circle()
                    .fill(AXETheme.statusColor(for: change.from))
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(AXETheme.textSecondary.opacity(0.3))
                    .frame(width: 1, height: 12)
                Circle()
                    .fill(AXETheme.statusColor(for: change.to))
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(change.target)
                    .font(AXETheme.headlineFont)
                    .foregroundColor(AXETheme.textPrimary)
                HStack(spacing: 4) {
                    Text(AXETheme.stateChangeLabel(for: change.from))
                        .font(AXETheme.captionFont)
                        .foregroundColor(AXETheme.statusColor(for: change.from))
                    Text(">")
                        .font(AXETheme.captionFont)
                        .foregroundColor(AXETheme.textSecondary)
                    Text(AXETheme.stateChangeLabel(for: change.to))
                        .font(AXETheme.captionFont)
                        .foregroundColor(AXETheme.statusColor(for: change.to))
                }
            }

            Spacer()

            Text(timeAgo(change.timestamp))
                .font(AXETheme.captionFont)
                .foregroundColor(AXETheme.textSecondary)
        }
        .padding(.horizontal, AXETheme.cardPadding)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 48))
                .foregroundColor(AXETheme.statusUp)
            Text("NO RECENT EVENTS")
                .font(AXETheme.headlineFont)
                .foregroundColor(AXETheme.textSecondary)
            Text("State changes will appear here\nas they are detected")
                .font(AXETheme.captionFont)
                .foregroundColor(AXETheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}
