// AXE Fleet Monitor — Theme (iOS)
// AXE brand: dark backgrounds, gold accents, monospaced typography.
// Zero emojis. Text identifiers only: [+] [-] [~] [?]

import SwiftUI

enum AXETheme {
    // MARK: - Colors

    static let background = Color(hex: 0x05080F)
    static let surface = Color(hex: 0x0F1330)
    static let surfaceElevated = Color(hex: 0x1A1F45)
    static let gold = Color(hex: 0xD8AF48)
    static let goldDim = Color(hex: 0xD8AF48).opacity(0.6)

    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0x8890A0)

    static let statusUp = Color(hex: 0x34D058)
    static let statusDown = Color(hex: 0xF85149)
    static let statusFlapping = Color(hex: 0xD29922)
    static let statusUnknown = Color(hex: 0x6E7681)

    // MARK: - Typography (iOS Dynamic Type compatible)

    static let titleFont = Font.system(size: 16, weight: .bold, design: .monospaced)
    static let headlineFont = Font.system(size: 14, weight: .semibold, design: .monospaced)
    static let bodyFont = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let captionFont = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let statFont = Font.system(size: 28, weight: .bold, design: .monospaced)

    // MARK: - Status Labels (zero emojis)

    static func statusLabel(for state: TargetState.State) -> String {
        switch state {
        case .up: return "[+]"
        case .down: return "[-]"
        case .unknown: return "[?]"
        }
    }

    static func statusColor(for state: TargetState.State) -> Color {
        switch state {
        case .up: return statusUp
        case .down: return statusDown
        case .unknown: return statusUnknown
        }
    }

    static func stateChangeLabel(for state: TargetState.State) -> String {
        switch state {
        case .up: return "ONLINE"
        case .down: return "OFFLINE"
        case .unknown: return "UNKNOWN"
        }
    }

    // MARK: - Layout

    static let cornerRadius: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
}

// MARK: - Hex Color Initializer

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
