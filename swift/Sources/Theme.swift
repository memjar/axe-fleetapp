// AXE Fleet Monitor — Brand Theme
// AXE dark theme: #05080f background, #d8af48 gold accents.
// Monospaced fonts throughout. Text identifiers [+] [-] [~] [?] — no emojis.

import SwiftUI

enum AXETheme {
    // MARK: - Colors

    static let background    = Color(hex: 0x05080F)
    static let surface       = Color(hex: 0x0F1330)
    static let surfaceLight  = Color(hex: 0x1A1F45)
    static let gold          = Color(hex: 0xD8AF48)
    static let goldDim       = Color(hex: 0x8B7530)
    static let textPrimary   = Color.white
    static let textSecondary = Color(hex: 0x8890A0)

    static let statusUp       = Color(hex: 0x34D058)
    static let statusDown     = Color(hex: 0xF85149)
    static let statusFlapping = Color(hex: 0xD29922)
    static let statusUnknown  = Color(hex: 0x6E7681)

    // MARK: - Fonts

    static let titleFont   = Font.system(size: 13, weight: .bold, design: .monospaced)
    static let bodyFont    = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let captionFont = Font.system(size: 10, weight: .regular, design: .monospaced)
    static let statFont    = Font.system(size: 18, weight: .bold, design: .monospaced)

    // MARK: - Layout

    static let popoverWidth: CGFloat  = 380
    static let popoverHeight: CGFloat = 520
    static let cornerRadius: CGFloat  = 8
    static let spacing: CGFloat       = 8
    static let padding: CGFloat       = 12

    // MARK: - Status Helpers

    static func statusColor(for state: TargetState.State) -> Color {
        switch state {
        case .up:      return statusUp
        case .down:    return statusDown
        case .unknown: return statusUnknown
        }
    }

    static func statusLabel(for state: TargetState.State) -> String {
        switch state {
        case .up:      return "[+]"
        case .down:    return "[-]"
        case .unknown: return "[?]"
        }
    }

    static func stateChangeLabel(for state: TargetState.State) -> String {
        switch state {
        case .up:      return "ONLINE"
        case .down:    return "OFFLINE"
        case .unknown: return "UNKNOWN"
        }
    }
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
