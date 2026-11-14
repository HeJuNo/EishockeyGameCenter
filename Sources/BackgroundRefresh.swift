import BackgroundTasks
import Foundation

/// Checks the watched pages when iOS grants background time. iOS decides when (about every 15 minutes at the earliest).
enum BackgroundRefresh {
    /// Listed in Info.plist (`BGTaskSchedulerPermittedIdentifiers`) as "$(PRODUCT_BUNDLE_IDENTIFIER).refresh".
    static var taskIdentifier: String { (Bundle.main.bundleIdentifier ?? "") + ".refresh" }

    static func nextDate(after now: Date) -> Date { now.addingTimeInterval(15 * 60) }

    /// Must run before the app finishes launching (called from the App initializer).
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: .main) { task in
            MainActor.assumeIsolated { handle(task) }   // the handler queue is .main
        }
    }

    /// Asks iOS for the next run. Nothing is scheduled while nothing is watched.
    static func schedule() {
        guard !WatchStore.shared.pages.isEmpty else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = nextDate(after: .now)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGTask) {
        schedule()   // first, so a failed run still leads to the next one
        let work = Task {
            let store = WatchStore.shared
            if !store.pages.isEmpty { _ = await SiteChecker(notifier: SystemNotifier()).run(store: store) }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
