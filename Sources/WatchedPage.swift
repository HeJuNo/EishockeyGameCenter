import Foundation

enum PageKind: String, Codable, CaseIterable { case game, team, table, goalies, topscorers, teamStats }

/// A page the user asked the app to watch.
struct WatchedPage: Codable, Hashable, Identifiable {
    let url: URL      // normalized
    let kind: PageKind
    var title: String
    var id: String { url.absoluteString }

    /// The player page also serves the penalty list (`wertung=strafen`): they are two different pages.
    var isPenaltyList: Bool {
        kind == .topscorers && URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "wertung" && $0.value == "strafen" } == true
    }

    /// What kind of page this is, in the settings: the site title is the league name for every league page.
    var kindLabel: String {
        switch kind {
        case .game: "Game"
        case .team: "Team"
        case .table: "Table"
        case .goalies: "Goalies"
        case .topscorers: isPenaltyList ? "Penalty list" : "Players"
        case .teamStats: "Team statistics"
        }
    }

    /// The league from the address (ice, alps, ...), as the site writes it on its tabs.
    var leagueLabel: String? {
        let parts = url.path.split(separator: "/")
        return parts.count > 1 ? parts[1].uppercased() : nil
    }
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
        case "teams": return .teamStats   // the "Team-Statistik" page
        default: return nil
        }
    }

    /// One spelling per page: https, www host, no trailing slash, only the saison, runde and wertung query items, no fragment.
    static func normalized(_ url: URL) -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        c.scheme = "https"; c.host = "www.eishockey.at"; c.fragment = nil
        while c.path.count > 1, c.path.hasSuffix("/") { c.path.removeLast() }
        // saison, runde and wertung (e.g. wertung=strafen for the penalty list) make up the page; list sizes and tracking do not.
        let kept = (c.queryItems ?? []).filter { ["saison", "runde", "wertung"].contains($0.name) }
        c.queryItems = kept.isEmpty ? nil : kept
        return c.url ?? url
    }
}
