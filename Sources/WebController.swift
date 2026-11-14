import Observation
import UIKit
import WebKit

@Observable
final class WebController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    private(set) var state: LoadState = .loading
    private(set) var canGoBack = false

    @ObservationIgnored private let startURL: URL
    @ObservationIgnored private var backObservation: NSKeyValueObservation?

    init(url: URL = WebController.initialURL()) {
        startURL = url
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(PageRules.userScript())
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.configuration.userContentController.add(WeakMessageHandler(self), name: PageRules.backMessageName)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pulledToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        backObservation = webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] web, _ in
            MainActor.assumeIsolated { self?.canGoBack = web.canGoBack; self?.showBackButton() }
        }
        webView.load(URLRequest(url: url))
    }

    private static func initialURL() -> URL {
        #if DEBUG
        if let s = UserDefaults.standard.string(forKey: "startURL"), let url = URL(string: s) { return url }  // UI tests
        #endif
        return PageRules.startURL
    }

    func reload() {
        state = .loading
        // After a failed first load there is no page to reload yet.
        if webView.url == nil { webView.load(URLRequest(url: startURL)) } else { webView.reload() }
    }

    func goBack() { webView.goBack() }

    /// Tells the page whether its in-page back button is visible.
    private func showBackButton() {
        webView.evaluateJavaScript("document.documentElement.classList.toggle('\(PageRules.canGoBackClass)', \(canGoBack))")
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) { goBack() }

    @objc private func pulledToRefresh() { reload() }

    private func finish(_ error: Error?) {
        webView.scrollView.refreshControl?.endRefreshing()
        guard let error else { state = .loaded; return }
        if let failure = LoadState.failure(for: error) { state = failure; return }
        // A cancelled navigation that no new load follows: settle on the page that is still shown.
        if !webView.isLoading { state = webView.url == nil ? .failed : .loaded }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard action.targetFrame?.isMainFrame ?? true, let url = action.request.url else { return .allow }
        if PageRules.shouldStayInApp(url) || url == startURL {
            if action.targetFrame == nil { webView.load(action.request); return .cancel }  // target=_blank stays in this view
            return .allow
        }
        await UIApplication.shared.open(url)
        return .cancel
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { state = .loading }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(nil); showBackButton() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }
}

/// The user content controller retains its handlers, so it gets a weak proxy to avoid a retain cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}
