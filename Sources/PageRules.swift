import Foundation
import WebKit

/// What the app changes on eishockey.at/game-center: start page, hidden site chrome, link policy.
enum PageRules {
    static let startURL = URL(string: "https://www.eishockey.at/game-center")!

    // Page-level selectors only: game cards have their own header and footer, which must stay.
    // shortcut: selectors follow the live page layout (2026-11-14), update them when the site changes.
    private static let hiddenSelectors = ["body > header", "body > footer", "body > #cookieshield-widget-root"]

    static let hideCSS = hiddenSelectors.joined(separator: ", ") + " { display: none !important; }"

    static func userScript() -> WKUserScript {
        // Appended to <html>, so the style survives the site's client-side page changes.
        let source = """
        (function () {
          var style = document.createElement('style');
          style.id = 'egc-hide';
          style.textContent = \(jsStringLiteral(hideCSS));
          document.documentElement.appendChild(style);
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
