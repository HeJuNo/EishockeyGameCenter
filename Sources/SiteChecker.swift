import Foundation

/// Fetches every watched page, compares it with the stored state and posts the changes.
struct SiteChecker {
    var fetch: (URL) async throws -> String
    let notifier: ChangeNotifying

    init(fetch: @escaping (URL) async throws -> String = SiteChecker.liveFetch, notifier: ChangeNotifying) {
        self.fetch = fetch
        self.notifier = notifier
    }

    static func liveFetch(_ url: URL) async throws -> String {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("de-AT,de;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let html = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }
        return html
    }

    /// One page after the other. A page that cannot be fetched or read is skipped and keeps its stored state.
    func run(store: WatchStore, now: Date = .now) async -> [Change] {
        // The automatic check, "Check now" and the background task can start together: only one run may work on the store.
        guard !store.isChecking else { return [] }
        store.isChecking = true
        defer { store.isChecking = false }
        var all: [Change] = []
        for page in store.pages {
            guard let html = try? await fetch(page.url), let snapshot = PageParser.snapshot(html: html, kind: page.kind) else { continue }
            if let old = store.snapshots[page.id], Self.looksLikeADataHiccup(old: old, new: snapshot) { continue }
            all += ChangeDetector.changes(page: page, old: store.snapshots[page.id], new: snapshot)
            store.setSnapshot(snapshot, for: page)   // also when the category is switched off, so switching it on does not replay
        }
        let wanted = all.filter { store.enabledCategories.contains($0.category) }
        if !wanted.isEmpty { await notifier.post(wanted) }
        store.markChecked(now)
        return wanted
    }

    /// A game never loses its score or its lineup. Such a page is treated like an unreadable one, otherwise the next
    /// good page would look like a new final result or a newly published lineup.
    private static func looksLikeADataHiccup(old: PageSnapshot, new: PageSnapshot) -> Bool {
        guard let before = old.game, let now = new.game else { return false }
        return (before.score != nil && now.score == nil) || (before.hasLineup && !now.hasLineup)
    }
}
