import Foundation
import Testing
import WebKit
@testable import EishockeyGameCenter

/// Long lists on the site end with a link "Weitere Einträge/Spiele laden" that raises `eintraege=` or `spiele=` in the address.
/// With "load all entries" on, the page script jumps straight to a huge value, so the server returns everything in one request.
@MainActor @Suite struct LoadAllEntriesTests {
    private final class Navigations: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Never>?
        var requested: [URL] = []   // everything after the first (the page itself) is recorded and cancelled
        private var first = true
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            if first { first = false; return .allow }
            if let url = action.request.url { requested.append(url) }
            return .cancel
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { continuation?.resume(); continuation = nil }
    }

    private func load(_ body: String, loadAll: Bool) async -> (WKWebView, Navigations) {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(PageRules.userScript(loadAll: loadAll))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        let log = Navigations()
        web.navigationDelegate = log
        await withCheckedContinuation { continuation in
            log.continuation = continuation
            web.loadHTMLString("<html><head><title>x</title></head><body><main>\(body)</main></body></html>", baseURL: URL(string: "https://www.eishockey.at/game-center/ice/topscorer"))
        }
        return (web, log)
    }
    private func waitForNavigation(_ log: Navigations, seconds: Double = 3) async throws {
        for _ in 0..<Int(seconds * 20) where log.requested.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
    }

    @Test func playerListJumpsToAllEntries() async throws {
        let (web, log) = await load(#"<a href="/game-center/ice/topscorer?saison=2026&amp;eintraege=100">WEITERE EINTRÄGE LADEN</a>"#, loadAll: true)
        try await waitForNavigation(log)
        #expect(log.requested == [URL(string: "https://www.eishockey.at/game-center/ice/topscorer?saison=2026&eintraege=10000")!])
        withExtendedLifetime(web) {}
    }

    @Test func scheduleListUsesTheGamesParameterAndKeepsTheAnchor() async throws {
        let (web, log) = await load(#"<a href="/game-center/ice?spiele=60#alle-spiele"><span>Weitere Spiele laden</span></a>"#, loadAll: true)
        try await waitForNavigation(log)
        #expect(log.requested == [URL(string: "https://www.eishockey.at/game-center/ice?spiele=10000#alle-spiele")!])
        withExtendedLifetime(web) {}
    }

    @Test func doesNothingWhenSwitchedOff() async throws {
        let (web, log) = await load(#"<a href="/game-center/ice/topscorer?eintraege=100">Weitere Einträge laden</a>"#, loadAll: false)
        try await waitForNavigation(log, seconds: 1)
        #expect(log.requested.isEmpty)
        withExtendedLifetime(web) {}
    }

    @Test func ignoresOtherLinksAndFullLists() async throws {
        let body = #"""
        <a href="/news?seite=2">Weitere News laden</a>
        <a href="/game-center/ice/topscorer?eintraege=100">Zur Tabelle</a>
        <a href="/game-center/ice/topscorer?eintraege=10050">Weitere Einträge laden</a>
        """#
        let (web, log) = await load(body, loadAll: true)
        try await waitForNavigation(log, seconds: 1)
        #expect(log.requested.isEmpty)   // no loop: a list that is already complete (or capped) is left alone
        withExtendedLifetime(web) {}
    }

    @Test func canBeSwitchedOnLater() async throws {
        let (web, log) = await load(#"<a href="/game-center/ice/topscorer?eintraege=100">Weitere Einträge laden</a>"#, loadAll: false)
        try await waitForNavigation(log, seconds: 0.5)
        #expect(log.requested.isEmpty)
        _ = try await web.callAsyncJavaScript("window.__egcSet({ 'egc-load-all': true })", contentWorld: .page)
        try await waitForNavigation(log)
        #expect(log.requested.count == 1)
    }
}
