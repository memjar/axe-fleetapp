// AXE Fleet Monitor — Native Notification Service
// UNUserNotificationCenter with custom categories (AXE_CRITICAL, AXE_INFO).
// No emojis — uses [AXE] text prefix. Action: open axe.observer dashboard.

import Foundation
import UserNotifications
import AppKit

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Authorization

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[AXE] Notification auth error: \(error.localizedDescription)")
            }
            print("[AXE] Notifications \(granted ? "granted" : "denied")")
        }
        registerCategories()
    }

    private func registerCategories() {
        let acknowledgeAction = UNNotificationAction(
            identifier: "ACKNOWLEDGE",
            title: "Acknowledge",
            options: []
        )
        let dashboardAction = UNNotificationAction(
            identifier: "OPEN_DASHBOARD",
            title: "Open Dashboard",
            options: [.foreground]
        )

        let critical = UNNotificationCategory(
            identifier: "AXE_CRITICAL",
            actions: [acknowledgeAction, dashboardAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let info = UNNotificationCategory(
            identifier: "AXE_INFO",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([critical, info])
    }

    // MARK: - State Change Notifications

    func notifyStateChange(target: String, from: TargetState.State, to: TargetState.State) {
        let content = UNMutableNotificationContent()
        content.threadIdentifier = "axe-fleet"

        let isDown = (to == .down)
        let isRecovery = (from == .down && to == .up)

        if isDown {
            content.title = "[AXE] Target Down"
            content.body = "\(target) is now OFFLINE"
            content.categoryIdentifier = "AXE_CRITICAL"
            content.sound = .defaultCritical
        } else if isRecovery {
            content.title = "[AXE] Target Recovered"
            content.body = "\(target) is back ONLINE"
            content.categoryIdentifier = "AXE_INFO"
            content.sound = .default
        } else {
            content.title = "[AXE] State Change"
            content.body = "\(target) state changed"
            content.categoryIdentifier = "AXE_INFO"
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "axe-\(target)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error = error {
                print("[AXE] Notification send error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Test Notification

    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "[AXE] Test Notification"
        content.body = "AXE Fleet Monitor is active. Notifications working."
        content.categoryIdentifier = "AXE_INFO"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "axe-test-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    // MARK: - Delegate (foreground delivery)

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "OPEN_DASHBOARD" {
            if let url = URL(string: "https://axe.observer/dashboard") {
                NSWorkspace.shared.open(url)
            }
        }
        completionHandler()
    }
}
