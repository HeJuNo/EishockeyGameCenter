import Foundation
import Observation

/// One detected change, kept so the app can show exactly what changed on the page.
struct ChangeRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let pageID: String
    let pageTitle: String
    let date: Date
    let summary: String
    let lines: [DiffLine]
}

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
        var history: [ChangeRecord]?
    }

    private(set) var pages: [WatchedPage] = []
    private(set) var snapshots: [String: PageSnapshot] = [:]
    private(set) var enabledCategories = Set(NotificationCategory.allCases)
    private(set) var lastCheck: Date?
    private(set) var history: [ChangeRecord] = []   // newest first
    static let maxHistory = 100
    @ObservationIgnored private let file: URL
    @ObservationIgnored var isChecking = false   // a check is running on this store (see SiteChecker.run)

    init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("state.json")
        // A missing or broken file means: start empty.
        if let data = try? Data(contentsOf: file), let state = try? JSONDecoder().decode(State.self, from: data) {
            pages = state.pages; snapshots = state.snapshots; enabledCategories = Set(state.enabled); lastCheck = state.lastCheck; history = state.history ?? []
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
    func record(_ changes: [Change], at date: Date) {
        guard !changes.isEmpty else { return }
        let records = changes.map { ChangeRecord(id: UUID(), pageID: $0.page.id, pageTitle: $0.title, date: date, summary: $0.body, lines: $0.lines) }
        history = Array((records.reversed() + history).prefix(Self.maxHistory))
        save()
    }
    func clearHistory() { history = []; save() }
    func markChecked(_ date: Date) { lastCheck = date; save() }
    func setCategory(_ category: NotificationCategory, enabled: Bool) {
        if enabled { enabledCategories.insert(category) } else { enabledCategories.remove(category) }
        save()
    }

    /// Replaces everything with the given pages and no snapshots (debug seeding for UI tests).
    func reset(pages seed: [WatchedPage]) { pages = seed; snapshots = [:]; history = []; enabledCategories = Set(NotificationCategory.allCases); lastCheck = nil; save() }

    private func save() {
        let state = State(pages: pages, snapshots: snapshots, enabled: NotificationCategory.allCases.filter(enabledCategories.contains), lastCheck: lastCheck, history: history)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
