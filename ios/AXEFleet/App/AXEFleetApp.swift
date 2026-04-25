// AXE Fleet Monitor — iOS App Entry
// SwiftUI lifecycle. Background task registration. Notification setup.

import SwiftUI
import BackgroundTasks
import UserNotifications

@main
struct AXEFleetApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        registerBackgroundTasks()
        requestNotificationPermission()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // MARK: - Background Tasks

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.axe.fleet-monitor.refresh",
            using: nil
        ) { task in
            self.handleBackgroundRefresh(task as! BGAppRefreshTask)
        }
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleNextRefresh()

        let operation = Task {
            do {
                let status = try await APIClient.shared.fetchStatus()
                let summary = status.computeSummary()

                // Notify if fleet health dropped
                if summary.healthPercent < 80 {
                    let content = UNMutableNotificationContent()
                    content.title = "[AXE] Fleet Health Alert"
                    content.body = "Health at \(summary.healthPercent)% — \(summary.machinesOffline) machines offline, \(summary.servicesDown) services down"
                    content.sound = .default
                    content.threadIdentifier = "axe-fleet"

                    let request = UNNotificationRequest(
                        identifier: "fleet-health-\(Date().timeIntervalSince1970)",
                        content: content,
                        trigger: nil
                    )
                    try? await UNUserNotificationCenter.current().add(request)
                }

                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            operation.cancel()
        }
    }

    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.axe.fleet-monitor.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[AXE] Background refresh scheduling failed: \(error)")
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("[AXE] Notification permission granted")
            }
            if let error = error {
                print("[AXE] Notification permission error: \(error)")
            }
        }

        // Register categories
        let acknowledgeAction = UNNotificationAction(
            identifier: "ACKNOWLEDGE",
            title: "Acknowledge",
            options: .destructive
        )
        let dashboardAction = UNNotificationAction(
            identifier: "OPEN_DASHBOARD",
            title: "Open Dashboard",
            options: .foreground
        )

        let criticalCategory = UNNotificationCategory(
            identifier: "AXE_CRITICAL",
            actions: [acknowledgeAction, dashboardAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        let infoCategory = UNNotificationCategory(
            identifier: "AXE_INFO",
            actions: [acknowledgeAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([criticalCategory, infoCategory])
    }

    // MARK: - Foreground Notification Delivery

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .badge, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.actionIdentifier == "OPEN_DASHBOARD" {
            if let url = URL(string: "https://axe.observer/dashboard") {
                await UIApplication.shared.open(url, options: [:])
            }
        }
    }
}
