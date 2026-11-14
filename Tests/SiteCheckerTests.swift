import Foundation
import Testing
@testable import EishockeyGameCenter

@MainActor @Suite struct SiteCheckerTests {
    private final class BundleAnchor {}
    @MainActor private final class Recorder: ChangeNotifying {
        var posted: [[Change]] = []
        func post(_ changes: [Change]) async { posted.append(changes) }
    }
    /// Serves fixtures by URL; a URL mapped to nil throws like a network error.
    @MainActor private final class FakeSite {
        var responses: [URL: String?] = [:]
        func fetch(_ url: URL) async throws -> String {
            guard let entry = responses[url], let html = entry else { throw URLError(.notConnectedToInternet) }
            return html
        }
    }
    private func fixture(_ name: String) -> String {
        let url = Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html")!
        return try! String(contentsOf: url, encoding: .utf8)
    }
    private let tableURL = URL(string: "https://www.eishockey.at/game-center/ice/tabelle")!
    private let gameURL = URL(string: "https://www.eishockey.at/game-center/ice/spiel/icehl-8287")!
    private func page(_ url: URL, _ kind: PageKind) -> WatchedPage { WatchedPage(url: url, kind: kind, title: "Seite") }
    private func setup() -> (store: WatchStore, site: FakeSite, recorder: Recorder, checker: SiteChecker) {
        let store = WatchStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("checker-\(UUID().uuidString)"))
        let site = FakeSite(), recorder = Recorder()
        return (store, site, recorder, SiteChecker(fetch: { try await site.fetch($0) }, notifier: recorder))
    }

    @Test func firstRunOnlyRecords() async {
        let (store, site, recorder, checker) = setup()
        site.responses[tableURL] = fixture("table")
        store.toggle(page(tableURL, .table))
        let changes = await checker.run(store: store)
        #expect(changes.isEmpty)
        #expect(recorder.posted.isEmpty)
        #expect(store.snapshots[store.pages[0].id] != nil)
    }

    @Test func changePostsOnceAndNotTwice() async {
        let (store, site, recorder, checker) = setup()
        store.toggle(page(gameURL, .game))
        site.responses[gameURL] = fixture("game-live")
        _ = await checker.run(store: store)                       // baseline: 1:0, live
        site.responses[gameURL] = fixture("game-final")           // 2:4, no longer live
        let first = await checker.run(store: store)
        #expect(first.map(\.kind) == [.finished])
        #expect(recorder.posted.count == 1)
        let second = await checker.run(store: store)
        #expect(second.isEmpty)
        #expect(recorder.posted.count == 1)
    }

    @Test func unreadablePageChangesNothing() async {
        let (store, site, recorder, checker) = setup()
        let table = page(tableURL, .table), game = page(gameURL, .game)
        store.toggle(table); store.toggle(game)
        let old = PageSnapshot(kind: .table, title: "Tabelle", textHash: "old", game: nil)
        store.setSnapshot(old, for: store.pages[0])
        site.responses[tableURL] = fixture("error")               // answers, but not readable
        site.responses[gameURL] = fixture("game-final")
        _ = await checker.run(store: store)
        #expect(store.snapshots[store.pages[0].id] == old)
        #expect(recorder.posted.isEmpty)
        #expect(store.snapshots[store.pages[1].id] != nil)        // the other page was still checked

        site.responses[tableURL] = .some(nil)                      // network error
        _ = await checker.run(store: store)
        #expect(store.snapshots[store.pages[0].id] == old)
        #expect(recorder.posted.isEmpty)
    }

    @Test func disabledCategoryIsStillRecorded() async {
        let (store, site, recorder, checker) = setup()
        store.toggle(page(tableURL, .table))
        store.setCategory(.statistics, enabled: false)
        site.responses[tableURL] = fixture("table")
        _ = await checker.run(store: store)
        let changed = fixture("table").replacingOccurrences(of: "Milano HC", with: "HC Fehervar")
        site.responses[tableURL] = changed
        let result = await checker.run(store: store)
        #expect(result.isEmpty)
        #expect(recorder.posted.isEmpty)
        let recorded = store.snapshots[store.pages[0].id]?.textHash
        #expect(recorded == PageParser.snapshot(html: changed, kind: .table)?.textHash)
        store.setCategory(.statistics, enabled: true)
        #expect(await checker.run(store: store).isEmpty)           // the old change is not replayed
    }

    @Test func lastCheckIsSet() async {
        let (store, _, _, checker) = setup()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        _ = await checker.run(store: store, now: now)
        #expect(store.lastCheck == now)
    }
}
