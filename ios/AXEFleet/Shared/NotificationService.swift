// AXE Fleet Monitor — Notification Service (iOS)
// Handles notification registration and delivery.
// Uses UNUserNotificationCenter for local push.

import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    // MARK: - Send Notification

    func send(
        title: String,
        body: String,
        category: String = "AXE_INFO",
        sound: UNNotificationSound = .default
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.sound = sound
        content.threadIdentifier = "axe-fleet"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Badge Management

    func clearBadge() async {
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }

    func setBadge(_ count: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }

    // MARK: - Convenience Methods

    func sendNotification(title: String, body: String, data: [String: String] = [:]) {
        Task {
            await send(title: title, body: body)
        }
    }

    func notifyStateChange(target: String, from: TargetState.State, to: TargetState.State) {
        let title: String
        let category: String
        let sound: UNNotificationSound

        switch (from, to) {
        case (_, .down):
            title = "🔴 \(target) DOWN"
            category = "AXE_CRITICAL"
            sound = .defaultCritical
        case (.down, .up):
            title = "✅ \(target) RECOVERED"
            category = "AXE_INFO"
            sound = .default
        default:
            title = "⚠️ \(target) state changed"
            category = "AXE_WARNING"
            sound = .default
        }

        let body = "Transition: \(from) → \(to)"

        Task {
            await send(title: title, body: body, category: category, sound: sound)
        }
    }
}
