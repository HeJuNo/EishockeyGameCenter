import Foundation
import Testing
@testable import EishockeyGameCenter

@MainActor @Suite struct LoadStateTests {
    @Test func cancelledNavigationIsNotAFailure() {
        #expect(LoadState.failure(for: URLError(.cancelled)) == nil)
        #expect(LoadState.failure(for: NSError(domain: "WebKitErrorDomain", code: 102)) == nil)  // frame load interrupted by policy change
    }

    @Test func realNetworkErrorsFail() {
        #expect(LoadState.failure(for: URLError(.notConnectedToInternet)) == .failed)
        #expect(LoadState.failure(for: URLError(.timedOut)) == .failed)
        #expect(LoadState.failure(for: URLError(.cannotFindHost)) == .failed)
    }
}

@MainActor @Suite struct WebControllerStateTests {
    /// A navigation that starts and is then cancelled (external redirect, file WebKit cannot show) must not leave the spinner on.
    @Test func cancelledNavigationAfterLoadingSettlesOnLoaded() async throws {
        let c = WebController(url: URL(string: "about:blank")!)
        c.webView.loadHTMLString("<p>x</p>", baseURL: URL(string: "https://www.eishockey.at/"))
        for _ in 0..<100 where c.state != .loaded || c.webView.url == nil { try await Task.sleep(for: .milliseconds(50)) }
        try #require(c.state == .loaded)
        c.webView(c.webView, didStartProvisionalNavigation: nil)
        #expect(c.state == .loading)
        c.webView(c.webView, didFailProvisionalNavigation: nil, withError: URLError(.cancelled))
        #expect(c.state == .loaded)
    }
}
