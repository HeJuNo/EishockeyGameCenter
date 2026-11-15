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
    /// Name of the script message the in-page watch button (bell) sends; WebController starts or stops watching the page.
    static let watchMessageName = "egcWatch"
    /// The app toggles these classes on <html>: the shown page can be watched / is watched.
    static let watchableClass = "egc-watchable"
    static let watchingClass = "egc-watching"
    /// The app sets this class on <html> while "load all list entries" is on.
    static let loadAllClass = "egc-load-all"
    /// The "load more" links raise one of these address parameters; the script sets it to this value so everything comes at once.
    static let allEntriesCount = 10000
    /// The app toggles this class on <html> while the web view can go back.
    static let canGoBackClass = "egc-can-go-back"

    // The back button sits inside the site's sticky tab bar, left of the tabs (navy = the site's 4,30,66).
    private static let barCSS = """
    .egc-bar { display: flex !important; align-items: center; }
    .egc-bar > :not(#egc-back):not(#egc-gear):not(#egc-watch) { flex: 1 1 0; min-width: 0; }
    #egc-back, #egc-gear, #egc-watch { flex: none; width: 44px; height: 44px; padding: 0; border: 0;
      background: transparent; color: rgb(4, 30, 66); align-items: center; justify-content: center; display: flex; }
    #egc-back { display: none; margin-left: 4px; }
    html.\(canGoBackClass) #egc-back { display: flex; }
    #egc-watch { display: none; }
    html.\(watchableClass) #egc-watch { display: flex; }
    #egc-watch .egc-bell-fill { display: none; }
    html.\(watchingClass) #egc-watch .egc-bell-fill { display: block; }
    #egc-gear { margin-right: 4px; }
    #egc-gear.egc-hero { position: absolute; top: 8px; right: 8px; z-index: 2; margin: 0; color: #fff; }
    """

    static func userScript(dark: Bool = false, loadAll: Bool = false) -> WKUserScript {
        // The style is appended to <html>, so it survives the site's client-side page changes.
        // The site sticks its league tabs (and the table header below them) at an offset made for the
        // header we hide; shift every such offset up by the smallest one, so the tabs stick at the top.
        // shortcut: finds the bars by the "sticky" utility class under <main>, update when the site changes.
        let source = """
        (function () {
          // The site rewrites the class of <html> while it loads, shortly after the load event. The classes the app
          // wants are therefore kept here and put back whenever the page changes the attribute.
          var wanted = {};
          function applyClasses() { var l = document.documentElement.classList; for (var k in wanted) l.toggle(k, wanted[k]); }
          window.__egcSet = function (state) { for (var k in state) wanted[k] = !!state[k]; applyClasses(); expandIfNeeded(); };
          // Long lists end with a link "Weitere Einträge/Spiele laden" that raises eintraege= or spiele= in the address.
          // With the option on, one jump to a huge value makes the server return everything at once.
          var expanding = false;
          function expandIfNeeded() {
            if (expanding || !document.documentElement.classList.contains('\(loadAllClass)')) return;
            var links = document.querySelectorAll('a[href*="eintraege="], a[href*="spiele="]');
            for (var i = 0; i < links.length; i++) {
              var a = links[i];
              if (!/weitere.*laden/i.test(a.textContent)) continue;
              var u; try { u = new URL(a.href, location.href); } catch (e) { continue; }
              var name = u.searchParams.has('eintraege') ? 'eintraege' : 'spiele';
              if (parseInt(u.searchParams.get(name), 10) >= \(allEntriesCount)) continue;   // already everything (or capped): no loop
              u.searchParams.set(name, '\(allEntriesCount)');
              expanding = true;
              location.replace(u.href);
              return;
            }
          }
          new MutationObserver(applyClasses).observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });
          if (\(dark)) window.__egcSet({ '\(DarkTheme.className)': true });
          if (\(loadAll)) window.__egcSet({ '\(loadAllClass)': true });
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
          function addWatch(bar) {
            if (bar.querySelector(':scope > #egc-watch')) return;
            var w = document.createElement('button');
            w.id = 'egc-watch';
            w.type = 'button';
            w.setAttribute('aria-label', 'Watch this page');
            w.innerHTML = '<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path class="egc-bell-fill" fill="currentColor" d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>';
            w.addEventListener('click', function () { window.webkit.messageHandlers.\(watchMessageName).postMessage(0); });
            bar.insertBefore(w, document.getElementById('egc-gear'));  // between the tabs and the settings button
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
              if (top === base) { addBack(e); addGear(e, false); addWatch(e); }  // the top bar only, not the table headers stuck below it
            });
            if (found.length === 0) {  // start page: no tab bar, the settings button goes into the hero
              var hero = Array.prototype.find.call(document.querySelectorAll('main header'), function (h) { return !h.closest('article, section'); });
              if (hero) addGear(hero, true);
            }
          }
          function schedule() { if (!queued) { queued = true; setTimeout(function () { shift(); expandIfNeeded(); }, 30); } }
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
