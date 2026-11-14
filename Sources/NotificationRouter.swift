import Foundation
import UserNotifications

/// Shows notifications while the app is open and hands a tapped notification's page to the web view.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    private var pending: URL?   // tapped before the web view was ready
    var onOpen: ((URL) -> Void)? {
        didSet { if let url = pending, let onOpen { pending = nil; onOpen(url) } }
    }

    private func open(_ url: URL) { if let onOpen { onOpen(url) } else { pending = url } }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: text) else { return }
        await MainActor.run { open(url) }
    }
}
