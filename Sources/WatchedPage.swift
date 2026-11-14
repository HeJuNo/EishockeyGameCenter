import Foundation

enum PageKind: String, Codable, CaseIterable { case game, team, table, goalies, topscorers }

/// A page the user asked the app to watch.
struct WatchedPage: Codable, Hashable, Identifiable {
    let url: URL      // normalized
    let kind: PageKind
    var title: String
    var id: String { url.absoluteString }
}

enum Watchable {
    private static func isSite(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && (url.host == "www.eishockey.at" || url.host == "eishockey.at")
    }

    /// nil means the page cannot be watched. Same strict host rule as `PageRules.shouldStayInApp`.
    static func kind(of url: URL) -> PageKind? {
        guard isSite(url) else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 3, parts[0] == "game-center" else { return nil }
        if parts.count == 4, parts[2] == "spiel" { return .game }
        if parts.count == 4, parts[2] == "team" { return .team }
        guard parts.count == 3 else { return nil }
        switch parts[2] {
        case "tabelle": return .table
        case "torhueter": return .goalies
        case "topscorer": return .topscorers
        default: return nil
        }
    }

    /// One spelling per page: https, www host, no trailing slash, only the `saison` query item, no fragment.
    static func normalized(_ url: URL) -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        c.scheme = "https"; c.host = "www.eishockey.at"; c.fragment = nil
        while c.path.count > 1, c.path.hasSuffix("/") { c.path.removeLast() }
        let saison = c.queryItems?.first { $0.name == "saison" }
        c.queryItems = saison.map { [$0] }
        return c.url ?? url
    }
}
