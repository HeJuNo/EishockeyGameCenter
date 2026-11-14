import Foundation
import Testing
@testable import EishockeyGameCenter

@MainActor @Suite struct WatchStoreTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("watchstore-\(UUID().uuidString)")
    }
    private let table = WatchedPage(url: URL(string: "https://www.eishockey.at/game-center/ice/tabelle")!, kind: .table, title: "Tabelle")
    private let snapshot = PageSnapshot(kind: .table, title: "Tabelle", textHash: "abc", game: nil)

    @Test func toggleAddsAndRemoves() {
        let store = WatchStore(directory: tempDirectory())
        store.toggle(table)
        #expect(store.isWatching(table.url))
        #expect(store.isWatching(URL(string: "https://eishockey.at/game-center/ice/tabelle/?utm=1")!))  // another spelling of the same page
        store.toggle(table)
        #expect(!store.isWatching(table.url))
        #expect(store.pages.isEmpty)
    }

    @Test func persistsAcrossInstances() {
        let dir = tempDirectory()
        let store = WatchStore(directory: dir)
        store.toggle(table)
        store.setSnapshot(snapshot, for: table)
        store.setCategory(.lineup, enabled: false)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        store.markChecked(date)

        let again = WatchStore(directory: dir)
        #expect(again.pages == [table])
        #expect(again.snapshots[table.id] == snapshot)
        #expect(again.enabledCategories == [.score, .statistics])
        #expect(again.lastCheck == date)
    }

    @Test func removeDropsSnapshot() {
        let store = WatchStore(directory: tempDirectory())
        store.toggle(table)
        store.setSnapshot(snapshot, for: table)
        store.remove(table)
        #expect(store.pages.isEmpty)
        #expect(store.snapshots.isEmpty)
    }

    @Test func brokenFileStartsEmpty() throws {
        let dir = tempDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("state.json"))
        let store = WatchStore(directory: dir)
        #expect(store.pages.isEmpty)
        #expect(store.enabledCategories == Set(NotificationCategory.allCases))
    }
}
