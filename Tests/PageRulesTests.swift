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
    private func load(_ name: String) async throws -> WKWebView {
        let url = try #require(Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html"))
        let html = try String(contentsOf: url, encoding: .utf8)
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(PageRules.userScript())
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

    @Test func shouldStayInAppOnlyForEishockeyAtOverHTTPS() {
        let stay = ["https://www.eishockey.at/game-center/ice/spiel/icehl-8288?saison=2026", "https://eishockey.at/x"]
        let leave = ["https://eishockey.at.example.com/", "http://www.eishockey.at/",
                     "https://www.eishockey.at@evil.example/", "mailto:a@b.at", "https://esports.ice.hockey/"]
        for s in stay { #expect(PageRules.shouldStayInApp(URL(string: s)!), Comment(rawValue: s)) }
        for s in leave { #expect(!PageRules.shouldStayInApp(URL(string: s)!), Comment(rawValue: s)) }
    }
}
