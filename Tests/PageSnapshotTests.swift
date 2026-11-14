import Foundation
import Testing
@testable import EishockeyGameCenter

@MainActor @Suite struct PageSnapshotTests {
    private final class BundleAnchor {}
    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html"))
        return try String(contentsOf: url, encoding: .utf8)
    }
    /// A readable page around some visible text.
    private func document(text: String, script: String = "", attrs: String = "", title: String = "Tabelle | ICE | ÖEHV") -> String {
        let filler = String(repeating: "Lorem ipsum Eishockey Spielstand Tabelle. ", count: 40)
        return "<html><head><title>\(title)</title></head><body><main \(attrs)><h1>Tabelle</h1><p \(attrs)>\(text) \(filler)</p></main><script>\(script)</script></body></html>"
    }

    @Test func finalGame() throws {
        let s = try #require(PageParser.snapshot(html: try fixture("game-final"), kind: .game))
        #expect(s.game == GameInfo(score: "2:4", live: false, hasLineup: true))
        #expect(s.title == "HCB Südtirol Alperia gegen Moser Medical Graz99ers")
    }

    @Test func plannedGame() throws {
        let s = try #require(PageParser.snapshot(html: try fixture("game-planned"), kind: .game))
        #expect(s.game == GameInfo(score: nil, live: false, hasLineup: false))  // the plural "Aufstellungen" sentence must not count
    }

    @Test func liveGame() throws {
        let s = try #require(PageParser.snapshot(html: try fixture("game-live"), kind: .game))
        #expect(s.game?.score == "1:0")
        #expect(s.game?.live == true)
    }

    @Test func tablePage() throws {
        let s = try #require(PageParser.snapshot(html: try fixture("table"), kind: .table))
        #expect(s.game == nil)
        #expect(!s.textHash.isEmpty)
    }

    @Test func hashIgnoresScriptsAndMarkup() throws {
        let a = try #require(PageParser.snapshot(html: document(text: "Platz 1 Salzburg", script: "var a = 1;"), kind: .table))
        let b = try #require(PageParser.snapshot(html: document(text: "Platz 1 Salzburg", script: "console.log('other')", attrs: "class=\"x\" data-v=\"2\""), kind: .table))
        let c = try #require(PageParser.snapshot(html: document(text: "Platz 1 Villach", script: "var a = 1;"), kind: .table))
        #expect(a.textHash == b.textHash)
        #expect(a.textHash != c.textHash)
    }

    @Test func unreadablePagesGiveNil() throws {
        #expect(PageParser.snapshot(html: try fixture("error"), kind: .table) == nil)
        #expect(PageParser.snapshot(html: "", kind: .table) == nil)
        let wrongTitle = try fixture("table").replacingOccurrences(of: "<title>Tabelle | ICE | ÖEHV</title>", with: "<title>Tabelle | ICE</title>")
        #expect(PageParser.snapshot(html: wrongTitle, kind: .table) == nil)
    }
}
