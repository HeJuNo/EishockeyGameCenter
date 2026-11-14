import SwiftUI
import UserNotifications

@main
struct EishockeyGameCenterApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared   // before launch finishes, so a tapped notification is not missed
        #if DEBUG
        // UI tests: "-watchSeed game" starts with one watched game, "-watchSeed none" with nothing watched.
        if let seed = UserDefaults.standard.string(forKey: "watchSeed") {
            let page = WatchedPage(url: URL(string: "https://www.eishockey.at/game-center/ice/spiel/seed-1?saison=2026")!, kind: .game, title: "Seed game")
            WatchStore.shared.reset(pages: seed == "game" ? [page] : [])
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            GameCenterView()
        }
    }
}
