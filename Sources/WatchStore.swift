import Foundation
import Observation

/// The pages the user watches, their last known state and the notification switches. Saved after every change.
@Observable
final class WatchStore {
    static let shared: WatchStore = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return WatchStore(directory: base.appendingPathComponent("Watch"))
    }()

    private struct State: Codable {
        var pages: [WatchedPage]
        var snapshots: [String: PageSnapshot]
        var enabled: [NotificationCategory]
        var lastCheck: Date?
    }

    private(set) var pages: [WatchedPage] = []
    private(set) var snapshots: [String: PageSnapshot] = [:]
    private(set) var enabledCategories = Set(NotificationCategory.allCases)
    private(set) var lastCheck: Date?
    @ObservationIgnored private let file: URL

    init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("state.json")
        // A missing or broken file means: start empty.
        if let data = try? Data(contentsOf: file), let state = try? JSONDecoder().decode(State.self, from: data) {
            pages = state.pages; snapshots = state.snapshots; enabledCategories = Set(state.enabled); lastCheck = state.lastCheck
        }
    }

    func isWatching(_ url: URL) -> Bool {
        let normalized = Watchable.normalized(url)
        return pages.contains { $0.url == normalized }
    }

    /// Starts or stops watching the page.
    func toggle(_ page: WatchedPage) {
        let normalized = WatchedPage(url: Watchable.normalized(page.url), kind: page.kind, title: page.title)
        if let existing = pages.first(where: { $0.id == normalized.id }) { remove(existing) } else { pages.append(normalized); save() }
    }

    func remove(_ page: WatchedPage) {
        pages.removeAll { $0.id == page.id }
        snapshots[page.id] = nil
        save()
    }

    func setSnapshot(_ snapshot: PageSnapshot, for page: WatchedPage) { snapshots[page.id] = snapshot; save() }
    func markChecked(_ date: Date) { lastCheck = date; save() }
    func setCategory(_ category: NotificationCategory, enabled: Bool) {
        if enabled { enabledCategories.insert(category) } else { enabledCategories.remove(category) }
        save()
    }

    /// Replaces everything with the given pages and no snapshots (debug seeding for UI tests).
    func reset(pages seed: [WatchedPage]) { pages = seed; snapshots = [:]; enabledCategories = Set(NotificationCategory.allCases); lastCheck = nil; save() }

    private func save() {
        let state = State(pages: pages, snapshots: snapshots, enabled: NotificationCategory.allCases.filter(enabledCategories.contains), lastCheck: lastCheck)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
