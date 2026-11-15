import Observation
import UIKit
import WebKit

@Observable
final class WebController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    private(set) var state: LoadState = .loading
    private(set) var canGoBack = false
    private(set) var isDark = false
    private(set) var loadAll = true   // "load all list entries" (the setting)
    var showSettings = false  // the settings sheet, opened by the in-page settings button
    @ObservationIgnored private var started = false
    @ObservationIgnored private var launchURL: URL?    // a page to open instead of the start page (notification tapped before the first load)
    @ObservationIgnored var store: WatchStore = .shared
    @ObservationIgnored var requestNotificationAccess: () async -> Bool = NotificationAccess.request

    @ObservationIgnored private let startURL: URL
    @ObservationIgnored private var backObservation: NSKeyValueObservation?
    @ObservationIgnored private var urlObservation: NSKeyValueObservation?

    init(url: URL = WebController.initialURL()) {
        startURL = url
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(PageRules.userScript())
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        for name in [PageRules.backMessageName, PageRules.settingsMessageName, PageRules.watchMessageName] {
            webView.configuration.userContentController.add(WeakMessageHandler(self), name: name)
        }
        webView.isOpaque = false                       // no white flash before the page is ready: the app's page-colored background shows through
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pulledToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        backObservation = webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] web, _ in
            MainActor.assumeIsolated { self?.canGoBack = web.canGoBack; self?.syncPageState() }
        }
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in   // also fires for the site's client-side page changes
            MainActor.assumeIsolated { self?.syncPageState() }
        }
    }

    private static func initialURL() -> URL {
        #if DEBUG
        if let s = UserDefaults.standard.string(forKey: "startURL"), let url = URL(string: s) { return url }  // UI tests
        #endif
        return PageRules.startURL
    }

    /// Starts the first load, once the app knows whether the page must be dark (so it never flashes light).
    func start(dark: Bool, loadAll: Bool = true) {
        guard !started else { return }
        started = true
        self.loadAll = loadAll
        setDark(dark)
        webView.load(URLRequest(url: launchURL ?? startURL))
    }

    /// Opens a watched page (from a tapped notification).
    func open(_ url: URL) {
        guard Watchable.kind(of: url) != nil else { return }
        if started { webView.load(URLRequest(url: url)) } else { launchURL = url }
    }

    func setDark(_ dark: Bool) {
        isDark = dark
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(PageRules.userScript(dark: dark, loadAll: loadAll))  // later page loads start in the right mode
        webView.underPageBackgroundColor = dark ? DarkTheme.pageBackground : DarkTheme.lightPageBackground
        syncPageState()
    }

    func setLoadAll(_ on: Bool) {
        loadAll = on
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(PageRules.userScript(dark: isDark, loadAll: on))
        syncPageState()
    }

    func reload() {
        state = .loading
        // After a failed first load there is no page to reload yet.
        if webView.url == nil { webView.load(URLRequest(url: startURL)) } else { webView.reload() }
    }

    func goBack() { webView.goBack() }

    /// Starts or stops watching the page that is shown (the in-page bell).
    func toggleWatch() async {
        guard let url = webView.url, let kind = Watchable.kind(of: url) else { return }
        let heading = try? await webView.evaluateJavaScript("((document.querySelector('h1') || {}).textContent || document.title || '')") as? String
        let title = (heading ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let page = WatchedPage(url: Watchable.normalized(url), kind: kind, title: title.isEmpty ? "Seite" : title)
        let wasWatching = store.isWatching(url)
        store.toggle(page)
        if !wasWatching { _ = await requestNotificationAccess() }   // asks the first time only
        syncPageState()
    }

    /// Tells the page about the state its in-page buttons and the dark theme depend on.
    func syncPageState() {
        let watchable = webView.url.map { Watchable.kind(of: $0) != nil } ?? false
        let watching = webView.url.map { store.isWatching($0) } ?? false
        webView.evaluateJavaScript("""
        window.__egcSet && window.__egcSet({ '\(PageRules.canGoBackClass)': \(canGoBack), '\(DarkTheme.className)': \(isDark),
          '\(PageRules.watchableClass)': \(watchable), '\(PageRules.watchingClass)': \(watching),
          '\(PageRules.loadAllClass)': \(loadAll) });
        """)
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case PageRules.settingsMessageName: showSettings = true
        case PageRules.watchMessageName: Task { await toggleWatch() }
        default: goBack()
        }
    }

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
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(nil); syncPageState() }
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
