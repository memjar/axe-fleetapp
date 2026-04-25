// AXE Fleet Monitor — Service Row Component
// Displays: status dot + text label [+]/[-]/[?] + clean name + raw state.
// Compact single-row layout for fleet/web/wireguard/droplet targets.

import SwiftUI

struct ServiceRow: View {
    let target: TargetState

    var body: some View {
        HStack(spacing: 8) {
            // Status dot
            Circle()
                .fill(AXETheme.statusColor(for: target.state))
                .frame(width: 6, height: 6)

            // Text status label
            Text(AXETheme.statusLabel(for: target.state))
                .font(AXETheme.captionFont)
                .foregroundColor(AXETheme.statusColor(for: target.state))
                .frame(width: 24, alignment: .leading)

            // Target name
            Text(target.displayName)
                .font(AXETheme.bodyFont)
                .foregroundColor(AXETheme.textPrimary)
                .lineLimit(1)

            Spacer()

            // Raw state value
            Text(target.rawValue)
                .font(AXETheme.captionFont)
                .foregroundColor(AXETheme.textSecondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(AXETheme.surface.opacity(0.5))
        .cornerRadius(4)
    }
}
