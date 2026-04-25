// AXE Fleet Monitor — Menu Bar Application Entry Point
// Architecture: AppKit + SwiftUI hybrid via NSStatusItem + NSPopover
// No dock icon (LSUIElement). Polls daemon on :8999 every 15s.

import AppKit
import SwiftUI
import Combine

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    let monitor = FleetMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupClickOutsideMonitor()

        NotificationService.shared.requestAuthorization()
        monitor.startPolling()

        print("[AXE] Fleet Monitor v3.0.0 started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stopPolling()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        print("[AXE] Fleet Monitor stopped")
    }

    // MARK: - Status Bar Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }
        button.title = "[AXE]"
        button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        button.action = #selector(togglePopover)
        button.target = self

        // Live-update menu bar title from fleet state
        monitor.$summary
            .receive(on: RunLoop.main)
            .sink { [weak self] summary in
                self?.updateStatusTitle(summary)
            }
            .store(in: &cancellables)

        monitor.$connectionState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                if !state.isConnected {
                    self?.statusItem.button?.title = "[AXE] --"
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusTitle(_ summary: FleetSummary) {
        let failures = summary.machinesOffline + summary.servicesDown + summary.webDown
        if failures > 0 {
            statusItem.button?.title = "[AXE] \(failures)[-]"
        } else if summary.totalTargets > 0 {
            statusItem.button?.title = "[AXE] \(summary.healthPercent)%"
        } else {
            statusItem.button?.title = "[AXE]"
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        let contentView = FleetMenuView(monitor: monitor)

        popover = NSPopover()
        popover.contentSize = NSSize(
            width: AXETheme.popoverWidth,
            height: AXETheme.popoverHeight
        )
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Click Outside Dismissal

    private func setupClickOutsideMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
