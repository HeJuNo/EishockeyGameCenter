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
    /// Name of the script message the in-page settings button sends; WebController shows the settings menu.
    static let settingsMessageName = "egcSettings"
    /// The app toggles this class on <html> while the web view can go back.
    static let canGoBackClass = "egc-can-go-back"

    // The back button sits inside the site's sticky tab bar, left of the tabs (navy = the site's 4,30,66).
    private static let barCSS = """
    .egc-bar { display: flex !important; align-items: center; }
    .egc-bar > :not(#egc-back):not(#egc-gear) { flex: 1 1 0; min-width: 0; }
    #egc-back, #egc-gear { flex: none; width: 44px; height: 44px; padding: 0; border: 0;
      background: transparent; color: rgb(4, 30, 66); align-items: center; justify-content: center; display: flex; }
    #egc-back { display: none; margin-left: 4px; }
    html.\(canGoBackClass) #egc-back { display: flex; }
    #egc-gear { margin-right: 4px; }
    #egc-gear.egc-hero { position: absolute; top: 8px; right: 8px; z-index: 2; margin: 0; color: #fff; }
    """

    static func userScript(dark: Bool = false) -> WKUserScript {
        // The style is appended to <html>, so it survives the site's client-side page changes.
        // The site sticks its league tabs (and the table header below them) at an offset made for the
        // header we hide; shift every such offset up by the smallest one, so the tabs stick at the top.
        // shortcut: finds the bars by the "sticky" utility class under <main>, update when the site changes.
        let source = """
        (function () {
          if (\(dark)) document.documentElement.classList.add('\(DarkTheme.className)');
          var style = document.createElement('style');
          style.id = 'egc-hide';
          style.textContent = \(jsStringLiteral(hideCSS + "\n" + barCSS + "\n" + DarkTheme.css));
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
          function addGear(host, hero) {
            if (document.getElementById('egc-gear')) return;
            var g = document.createElement('button');
            g.id = 'egc-gear';
            g.type = 'button';
            g.setAttribute('aria-label', 'Settings');
            g.innerHTML = '<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M4 6h8M16 6h4M4 12h2M10 12h10M4 18h10M18 18h2"/><circle cx="14" cy="6" r="2"/><circle cx="8" cy="12" r="2"/><circle cx="16" cy="18" r="2"/></svg>';
            g.addEventListener('click', function () { window.webkit.messageHandlers.\(settingsMessageName).postMessage(0); });
            if (hero) {
              g.classList.add('egc-hero');
              if (getComputedStyle(host).position === 'static') host.style.position = 'relative';
              host.appendChild(g);
            } else {
              host.appendChild(g);
            }
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
              if (top === base) { addBack(e); addGear(e, false); }  // the top bar only, not the table headers stuck below it
            });
            if (found.length === 0) {  // start page: no tab bar, the settings button goes into the hero
              var hero = Array.prototype.find.call(document.querySelectorAll('main header'), function (h) { return !h.closest('article, section'); });
              if (hero) addGear(hero, true);
            }
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
