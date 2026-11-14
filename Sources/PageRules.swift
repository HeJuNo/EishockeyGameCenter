import Foundation
import WebKit

/// What the app changes on eishockey.at/game-center: start page, hidden site chrome, link policy.
enum PageRules {
    static let startURL = URL(string: "https://www.eishockey.at/game-center")!

    // Page-level selectors only: game cards have their own header and footer, which must stay.
    // shortcut: selectors follow the live page layout (2026-11-14), update them when the site changes.
    private static let hiddenSelectors = ["body > header", "body > footer", "body > #cookieshield-widget-root"]

    static let hideCSS = hiddenSelectors.joined(separator: ", ") + " { display: none !important; }"

    /// Name of the script message the in-page back button sends; WebController answers it with goBack().
    static let backMessageName = "egcBack"
    /// The app toggles this class on <html> while the web view can go back.
    static let canGoBackClass = "egc-can-go-back"

    // The back button sits inside the site's sticky tab bar, left of the tabs (navy = the site's 4,30,66).
    private static let barCSS = """
    .egc-bar { display: flex !important; align-items: center; }
    .egc-bar > :not(#egc-back) { flex: 1 1 0; min-width: 0; }
    #egc-back { display: none; flex: none; width: 44px; height: 44px; margin-left: 4px; padding: 0; border: 0;
      background: transparent; color: rgb(4, 30, 66); align-items: center; justify-content: center; }
    html.\(canGoBackClass) #egc-back { display: flex; }
    """

    static func userScript() -> WKUserScript {
        // The style is appended to <html>, so it survives the site's client-side page changes.
        // The site sticks its league tabs (and the table header below them) at an offset made for the
        // header we hide; shift every such offset up by the smallest one, so the tabs stick at the top.
        // shortcut: finds the bars by the "sticky" utility class under <main>, update when the site changes.
        let source = """
        (function () {
          var style = document.createElement('style');
          style.id = 'egc-hide';
          style.textContent = \(jsStringLiteral(hideCSS + "\n" + barCSS));
          document.documentElement.appendChild(style);

          var base = null, queued = false;
          function addBack(bar) {
            if (bar.querySelector(':scope > #egc-back')) return;
            var b = document.createElement('button');
            b.id = 'egc-back';
            b.type = 'button';
            b.setAttribute('aria-label', 'Back');
            b.innerHTML = '<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M15 5l-7 7 7 7"/></svg>';
            b.addEventListener('click', function () { window.webkit.messageHandlers.\(backMessageName).postMessage(0); });
            bar.classList.add('egc-bar');
            bar.insertBefore(b, bar.firstChild);
          }
          function shift() {
            queued = false;
            var found = [];
            document.querySelectorAll('main [class~="sticky"]').forEach(function (e) {
              if (e.dataset.egcTop === undefined) {
                var cs = getComputedStyle(e), t = parseFloat(cs.top);
                e.dataset.egcTop = (cs.position === 'sticky' && t > 0) ? String(t) : '';
              }
              if (e.dataset.egcTop !== '') found.push(e);
            });
            found.forEach(function (e) { var t = parseFloat(e.dataset.egcTop); if (base === null || t < base) base = t; });
            found.forEach(function (e) {
              var top = parseFloat(e.dataset.egcTop);
              e.style.setProperty('top', (top - base) + 'px', 'important');
              if (top === base) addBack(e);  // the top bar only, not the table headers stuck below it
            });
          }
          function schedule() { if (!queued) { queued = true; setTimeout(shift, 30); } }
          new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
          document.addEventListener('DOMContentLoaded', schedule);
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    static func shouldStayInApp(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil else { return false }
        return url.host == "www.eishockey.at" || url.host == "eishockey.at"
    }

    private static func jsStringLiteral(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s])
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }
}
