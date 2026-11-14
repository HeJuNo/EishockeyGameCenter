import SwiftUI
import UserNotifications

@main
struct EishockeyGameCenterApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared   // before launch finishes, so a tapped notification is not missed
    }

    var body: some Scene {
        WindowGroup {
            GameCenterView()
        }
    }
}
