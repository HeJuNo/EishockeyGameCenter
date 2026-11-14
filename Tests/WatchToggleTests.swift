import Foundation
import Testing
import WebKit
@testable import EishockeyGameCenter

@MainActor @Suite struct WatchToggleTests {
    private func controllerShowing(_ url: String, h1: String) async throws -> (WebController, WatchStore) {
        let store = WatchStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("toggle-\(UUID().uuidString)"))
        let controller = WebController(url: URL(string: url)!)
        controller.store = store
        controller.requestNotificationAccess = { true }   // no system prompt in tests
        controller.webView.loadHTMLString("<html><body><h1> \(h1) </h1></body></html>", baseURL: URL(string: url))
        for _ in 0..<100 where controller.webView.isLoading || controller.webView.url == nil { try await Task.sleep(for: .milliseconds(50)) }
        return (controller, store)
    }

    @Test func toggleWatchesAndUnwatchesTheShownPage() async throws {
        let (controller, store) = try await controllerShowing("https://eishockey.at/game-center/ice/tabelle/?utm=1", h1: "Tabelle")
        await controller.toggleWatch()
        #expect(store.pages == [WatchedPage(url: URL(string: "https://www.eishockey.at/game-center/ice/tabelle")!, kind: .table, title: "Tabelle")])
        await controller.toggleWatch()
        #expect(store.pages.isEmpty)
    }

    @Test func unwatchablePageIsIgnored() async throws {
        let (controller, store) = try await controllerShowing("https://www.eishockey.at/game-center", h1: "Game Center")
        await controller.toggleWatch()
        #expect(store.pages.isEmpty)
    }
}
