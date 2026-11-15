import SwiftUI
import UserNotifications

@main
struct EishockeyGameCenterApp: App {
    @Environment(\.scenePhase) private var scenePhase
    // While the app is open the watched pages are checked at once and then every minute; in the background iOS decides.
    @State private var autoChecker = AutoChecker(interval: .seconds(60)) {
        let store = WatchStore.shared
        guard !store.pages.isEmpty else { return }
        _ = await SiteChecker(notifier: SystemNotifier()).run(store: store)
    }

    init() {
        BackgroundRefresh.register()
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
                .onAppear { if scenePhase == .active { autoChecker.start() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { autoChecker.start() } else { autoChecker.stop() }
            if phase == .background { BackgroundRefresh.schedule() }
        }
    }
}
