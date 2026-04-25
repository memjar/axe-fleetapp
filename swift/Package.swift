// swift-tools-version:5.9
// AXE Fleet Monitor — Native macOS Menu Bar Application
// Principal: Zero external dependencies. AppKit + SwiftUI hybrid.

import PackageDescription

let package = Package(
    name: "AXEFleet",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AXEFleet",
            path: "Sources"
        )
    ]
)
