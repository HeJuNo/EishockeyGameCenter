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
    private func load(_ name: String, dark: Bool = false, handlers: [String: WKScriptMessageHandler] = [:]) async throws -> WKWebView {
        let url = try #require(Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html"))
        let html = try String(contentsOf: url, encoding: .utf8)
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(PageRules.userScript(dark: dark))
        for (name, handler) in handlers { config.userContentController.add(handler, name: name) }
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
        let web = try await load("game-center-structure", handlers: [PageRules.backMessageName: recorder])
        for _ in 0..<40 where try await !hasElement("#egc-back", in: web) { try await Task.sleep(for: .milliseconds(50)) }
        _ = try await web.callAsyncJavaScript("document.getElementById('egc-back').click()", contentWorld: .page)
        for _ in 0..<20 where recorder.taps == 0 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(recorder.taps == 1)
    }

    private func style(_ selector: String, _ property: String, in webView: WKWebView) async throws -> String {
        let result = try await webView.callAsyncJavaScript(
            "return getComputedStyle(document.querySelector(sel)).getPropertyValue(prop)", arguments: ["sel": selector, "prop": property], contentWorld: .page)
        return result as? String ?? ""
    }

    /// Dark mode: page, cards and headings turn dark/light; white text and icons stay white. Without the class nothing changes.
    @Test func darkClassRecolorsPageCardsAndText() async throws {
        let web = try await load("game-center-structure", dark: true)
        #expect(try await style("body", "background-color", in: web) == "rgb(7, 17, 31)")
        #expect(try await style("#title", "color", in: web) == "rgb(232, 240, 250)")
        #expect(try await style("article", "--color-white", in: web) == "#0d1b2f")  // cards (bg-white) follow the dark card color
        #expect(try await style("#white-text", "--color-white", in: web) == "#fff") // text-white stays white
    }

    @Test func lightPageIsUntouchedWithoutTheDarkClass() async throws {
        let web = try await load("game-center-structure")
        #expect(try await style("#title", "color", in: web) != "rgb(232, 240, 250)")
        #expect(try await style("article", "--color-white", in: web) == "")
    }

    @Test func darkClassCanBeSwitchedAtRuntime() async throws {
        let web = try await load("game-center-structure")
        _ = try await web.callAsyncJavaScript("document.documentElement.classList.add('egc-dark')", contentWorld: .page)
        #expect(try await style("body", "background-color", in: web) == "rgb(7, 17, 31)")
        _ = try await web.callAsyncJavaScript("document.documentElement.classList.remove('egc-dark')", contentWorld: .page)
        #expect(try await style("body", "background-color", in: web) != "rgb(7, 17, 31)")
    }

    /// The settings button sits in the tab bar, right of the tabs, always visible.
    @Test func settingsButtonSitsRightOfTheTabsInTheBar() async throws {
        let web = try await load("game-center-structure")
        for _ in 0..<40 where try await !hasElement("#tabs > #egc-gear", in: web) { try await Task.sleep(for: .milliseconds(50)) }
        #expect(try await hasElement("#tabs > #egc-gear", in: web))
        #expect(try await isVisible("#egc-gear", in: web))
        #expect(try await !hasElement("#hero-head #egc-gear", in: web))  // one button only, the bar has it
        let gear = try await rect("#egc-gear", in: web), tabs = try await rect("#tabs-inner", in: web), bar = try await rect("#tabs", in: web)
        #expect(gear[0] >= tabs[2])                          // starts where the tabs end
        #expect(gear[1] >= bar[1] && gear[3] <= bar[3])      // inside the bar
    }

    /// The start page has no tab bar: the button goes into the top corner of the hero.
    @Test func startPageGetsSettingsButtonInTheHero() async throws {
        let web = try await load("game-center-hero-only")
        for _ in 0..<40 where try await !hasElement("#hero-head > #egc-gear", in: web) { try await Task.sleep(for: .milliseconds(50)) }
        #expect(try await hasElement("#hero-head > #egc-gear", in: web))
        #expect(try await isVisible("#egc-gear", in: web))
        #expect(try await !hasElement("article #egc-gear", in: web))  // not inside a game card
        let gear = try await rect("#egc-gear", in: web), hero = try await rect("#hero-head", in: web)
        #expect(gear[2] <= hero[2] && gear[0] > hero[2] - 80)  // near the right edge
        #expect(gear[1] >= hero[1] && gear[3] <= hero[3])
    }

    @Test func settingsButtonTellsTheApp() async throws {
        let recorder = BackRecorder()
        let web = try await load("game-center-hero-only", handlers: [PageRules.settingsMessageName: recorder])
        for _ in 0..<40 where try await !hasElement("#egc-gear", in: web) { try await Task.sleep(for: .milliseconds(50)) }
        _ = try await web.callAsyncJavaScript("document.getElementById('egc-gear').click()", contentWorld: .page)
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
