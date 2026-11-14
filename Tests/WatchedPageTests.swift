import Foundation
import Testing
@testable import EishockeyGameCenter

@MainActor @Suite struct WatchedPageTests {
    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test func kindOfWatchableURLs() {
        #expect(Watchable.kind(of: url("https://www.eishockey.at/game-center/ice/spiel/icehl-8287?saison=2026")) == .game)
        #expect(Watchable.kind(of: url("https://www.eishockey.at/game-center/ice/team/1?saison=2026")) == .team)
        #expect(Watchable.kind(of: url("https://www.eishockey.at/game-center/ice/tabelle")) == .table)
        #expect(Watchable.kind(of: url("https://www.eishockey.at/game-center/alps/torhueter?saison=21947")) == .goalies)
        #expect(Watchable.kind(of: url("https://www.eishockey.at/game-center/u14/topscorer")) == .topscorers)
        #expect(Watchable.kind(of: url("https://eishockey.at/game-center/ice/tabelle")) == .table)
    }

    @Test func notWatchable() {
        let urls = ["https://www.eishockey.at/game-center", "https://www.eishockey.at/game-center/ice", "https://www.eishockey.at/game-center/ice/teams",
                    "https://www.eishockey.at/game-center/ice/spiel/", "http://www.eishockey.at/game-center/ice/tabelle",
                    "https://eishockey.at.example.com/game-center/ice/tabelle", "https://www.eishockey.at@evil.example/game-center/ice/tabelle"]
        for u in urls { #expect(Watchable.kind(of: url(u)) == nil, Comment(rawValue: u)) }
    }

    @Test func normalizationMakesOneEntry() {
        #expect(Watchable.normalized(url("https://eishockey.at/game-center/ice/tabelle/?utm=1#x")) == url("https://www.eishockey.at/game-center/ice/tabelle"))
        #expect(Watchable.normalized(url("https://www.eishockey.at/game-center/ice/tabelle?saison=2026&utm=1")) == url("https://www.eishockey.at/game-center/ice/tabelle?saison=2026"))
    }
}
