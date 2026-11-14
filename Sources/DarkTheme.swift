import UIKit

/// The site has no dark theme, so the app paints one. The site's utility classes read their colors from
/// CSS variables; `--color-white` is the card/table/ring color, so one override darkens all of them, and
/// elements with white text or icons get the real white back. Page and text colors are set by class.
/// shortcut: follows the live site's class names (2026-11-14), recheck the dark pages when the site changes.
enum DarkTheme {
    static let className = "egc-dark"

    // The page's light colors are rgb(244, 247, 251) and rgb(231, 237, 244).
    static let pageBackground = UIColor(red: 7 / 255, green: 17 / 255, blue: 31 / 255, alpha: 1)
    static let lightPageBackground = UIColor(red: 244 / 255, green: 247 / 255, blue: 251 / 255, alpha: 1)

    static let css = """
    html.egc-dark {
      color-scheme: dark;
      --color-white: #0d1b2f;
      --text-primary: #e8f0fa;
      --text-secondary: #9db2c9;
    }
    html.egc-dark [class*="text-white"], html.egc-dark [class*="fill-white"], html.egc-dark [class*="stroke-white"],
    html.egc-dark [class~="bg-white/10"] { --color-white: #fff; }
    html.egc-dark body, html.egc-dark [class~="rink"], html.egc-dark [class~="bg-ice-50"] { background-color: #07111f !important; }
    html.egc-dark [class*="bg-ice-50/"] { background-color: rgb(7 17 31 / .9) !important; }
    html.egc-dark [class~="bg-ice-100"] { background-color: #0e1d33 !important; }
    html.egc-dark [class~="bg-ice-200"] { background-color: #1d3250 !important; }
    html.egc-dark [class~="border-ice-200"] { border-color: #1d3250 !important; }
    html.egc-dark [class~="text-navy-900"], html.egc-dark [class~="text-navy-950"], html.egc-dark [class~="text-navy-800"] { color: #e8f0fa !important; }
    html.egc-dark [class~="text-navy-700"] { color: #a9c3e6 !important; }
    html.egc-dark [class~="text-red-600"] { color: #ff6a5e !important; }
    html.egc-dark [class~="fill-navy-900"] { fill: #e8f0fa !important; }
    html.egc-dark [class~="stroke-navy-900"] { stroke: #e8f0fa !important; }
    html.egc-dark td:not([class*="bg-"]) { background-color: #0d1b2f !important; }
    html.egc-dark th:not([class*="bg-"]) { background-color: #0e1d33 !important; }
    html.egc-dark #egc-back, html.egc-dark #egc-gear { color: #e8f0fa; }
    """
}
