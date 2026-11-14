import Foundation
import Testing
import WebKit
@testable import EishockeyGameCenter

@MainActor @Suite struct PageRulesTests {
    private final class Loader: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Never>?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { continuation?.resume(); continuation = nil }
    }
    private final class BundleAnchor {}

    /// Loads a fixture into a web view that carries the app's user script.
    private func load(_ name: String, backHandler: WKScriptMessageHandler? = nil) async throws -> WKWebView {
        let url = try #require(Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html"))
        let html = try String(contentsOf: url, encoding: .utf8)
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(PageRules.userScript())
        if let backHandler { config.userContentController.add(backHandler, name: PageRules.backMessageName) }
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        let loader = Loader()
        webView.navigationDelegate = loader
        await withCheckedContinuation { continuation in
            loader.continuation = continuation
            webView.loadHTMLString(html, baseURL: URL(string: "https://www.eishockey.at/game-center"))
        }
        withExtendedLifetime(loader) {}
        return webView
    }

    /// True when every element matching the selector takes up space (and at least one exists).
    private func isVisible(_ selector: String, in webView: WKWebView) async throws -> Bool {
        let result = try await webView.callAsyncJavaScript(
            "const all = [...document.querySelectorAll(sel)]; return all.length > 0 && all.every(e => e.getClientRects().length > 0)",
            arguments: ["sel": selector], contentWorld: .page)
        return result as? Bool ?? false
    }

    @Test func hidesSiteHeaderFooterAndCookieBanner() async throws {
        let web = try await load("game-center-structure")
        #expect(try await !isVisible("body > header", in: web))
        #expect(try await !isVisible("body > footer", in: web))
        #expect(try await !isVisible("#banner", in: web))
    }

    @Test func keepsChipsSectionsAndGameCardChrome() async throws {
        let web = try await load("game-center-structure")
        #expect(try await isVisible("main nav", in: web))
        #expect(try await isVisible("section[id]", in: web))
        #expect(try await isVisible("section[id] article > header", in: web))
        #expect(try await isVisible("section[id] article > footer", in: web))
        #expect(try await isVisible("#hero-head", in: web))
    }

    @Test func leavesPageUntouchedWhenChromeIsMissing() async throws {
        let web = try await load("game-center-no-chrome")
        #expect(try await isVisible("section[id]", in: web))
        #expect(try await isVisible("section[id] article > footer", in: web))
    }

    private func stickyTop(_ selector: String, in webView: WKWebView) async throws -> String {
        let result = try await webView.callAsyncJavaScript(
            "return getComputedStyle(document.querySelector(sel)).top", arguments: ["sel": selector], contentWorld: .page)
        return result as? String ?? ""
    }

    /// The site sticks its league tabs at 56 pt (under the header we hide); without the header they must stick at the top.
    @Test func movesStickyBarsUpByTheHiddenHeader() async throws {
        let web = try await load("game-center-structure")
        for _ in 0..<40 where try await stickyTop("#tabs", in: web) != "0px" { try await Task.sleep(for: .milliseconds(50)) }
        #expect(try await stickyTop("#tabs", in: web) == "0px")
        #expect(try await stickyTop("#thead", in: web) == "45px")  // stays below the tabs, offset kept
    }

    private final class BackRecorder: NSObject, WKScriptMessageHandler {
        var taps = 0
        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) { taps += 1 }
    }

    private func rect(_ selector: String, in webView: WKWebView) async throws -> [Double] {
        let result = try await webView.callAsyncJavaScript(
            "const r = document.querySelector(sel).getBoundingClientRect(); return [r.left, r.top, r.right, r.bottom]",
            arguments: ["sel": selector], contentWorld: .page)
        return result as? [Double] ?? []
    }

    /// The back button lives in the tab bar, left of the tabs, and only shows when the app says the page can go back.
    @Test func backButtonSitsLeftOfTheTabsInTheBar() async throws {
        let web = try await load("game-center-structure")
        for _ in 0..<40 where try await !hasElement("#tabs > #egc-back", in: web) { try await Task.sleep(for: .milliseconds(50)) }
        #expect(try await hasElement("#tabs > #egc-back", in: web))
        #expect(try await !hasElement("#thead #egc-back", in: web))  // only the top bar gets it, not the table header
        #expect(try await !isVisible("#egc-back", in: web))
        _ = try await web.callAsyncJavaScript("document.documentElement.classList.add('egc-can-go-back')", contentWorld: .page)
        #expect(try await isVisible("#egc-back", in: web))
        let button = try await rect("#egc-back", in: web), tabs = try await rect("#tabs-inner", in: web), bar = try await rect("#tabs", in: web)
        #expect(button[2] <= tabs[0])                       // button ends where the tabs start
        #expect(button[1] >= bar[1] && button[3] <= bar[3]) // inside the bar, not above it
    }

    @Test func backButtonTellsTheApp() async throws {
        let recorder = BackRecorder()
        let web = try await load("game-center-structure", backHandler: recorder)
        for _ in 0..<40 where try await !hasElement("#egc-back", in: web) { try await Task.sleep(for: .milliseconds(50)) }
        _ = try await web.callAsyncJavaScript("document.getElementById('egc-back').click()", contentWorld: .page)
        for _ in 0..<20 where recorder.taps == 0 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(recorder.taps == 1)
    }

    private func hasElement(_ selector: String, in webView: WKWebView) async throws -> Bool {
        let result = try await webView.callAsyncJavaScript("return document.querySelector(sel) !== null", arguments: ["sel": selector], contentWorld: .page)
        return result as? Bool ?? false
    }

    @Test func shouldStayInAppOnlyForEishockeyAtOverHTTPS() {
        let stay = ["https://www.eishockey.at/game-center/ice/spiel/icehl-8288?saison=2026", "https://eishockey.at/x"]
        let leave = ["https://eishockey.at.example.com/", "http://www.eishockey.at/",
                     "https://www.eishockey.at@evil.example/", "mailto:a@b.at", "https://esports.ice.hockey/"]
        for s in stay { #expect(PageRules.shouldStayInApp(URL(string: s)!), Comment(rawValue: s)) }
        for s in leave { #expect(!PageRules.shouldStayInApp(URL(string: s)!), Comment(rawValue: s)) }
    }
}
