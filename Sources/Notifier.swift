import Foundation
import UserNotifications

protocol ChangeNotifying {
    func post(_ changes: [Change]) async
}

/// Posts local notifications; tapping one opens the page (`userInfo["url"]`, see NotificationRouter).
struct SystemNotifier: ChangeNotifying {
    func post(_ changes: [Change]) async {
        let center = UNUserNotificationCenter.current()
        for change in changes {
            let content = UNMutableNotificationContent()
            content.title = change.title
            content.body = change.body
            content.sound = .default
            content.userInfo = ["url": change.page.url.absoluteString]
            content.threadIdentifier = change.page.id
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

enum NotificationAccess {
    /// Asks once; later calls just return the current answer.
    static func request() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
}
