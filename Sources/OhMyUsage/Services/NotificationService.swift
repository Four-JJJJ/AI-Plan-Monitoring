import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    private var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    func requestPermissionIfNeeded() {
        guard canUseUserNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            // Ignore in v1. We still run even if permission is denied.
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        guard canUseUserNotifications else {
            return .denied
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    func notify(title: String, body: String, identifier: String) {
        guard canUseUserNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
