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

    /// The site streams parts of a page in a changing order and moves content between inline and streamed blocks:
    /// the same page must hash the same, whatever the order of its blocks.
    @Test func hashIgnoresTheOrderOfBlocks() throws {
        let rows = "<tr><td>1</td><td>Salzburg</td><td>41</td></tr><tr><td>2</td><td>Villach</td><td>39</td></tr>"
        let rowsReordered = "<tr><td>2</td><td>Villach</td><td>39</td></tr><tr><td>1</td><td>Salzburg</td><td>41</td></tr>"
        let a = document(text: "<p>Torhüter</p><table>\(rows)</table><p>Spielplan</p>")
        let b = document(text: "<p>Spielplan</p><table>\(rowsReordered)</table><p>Torhüter</p>")
        let ha = try #require(PageParser.snapshot(html: a, kind: .team)).textHash
        let hb = try #require(PageParser.snapshot(html: b, kind: .team)).textHash
        #expect(ha == hb)
    }

    @Test func hashSeesChangedCellsAndSwappedRanks() throws {
        func hash(_ rows: String) throws -> String { try #require(PageParser.snapshot(html: document(text: "<table>\(rows)</table>"), kind: .table)).textHash }
        let base = try hash("<tr><td>1</td><td>Salzburg</td><td>41</td></tr><tr><td>2</td><td>Villach</td><td>39</td></tr>")
        #expect(base != (try hash("<tr><td>1</td><td>Salzburg</td><td>42</td></tr><tr><td>2</td><td>Villach</td><td>39</td></tr>")))   // a point more
        #expect(base != (try hash("<tr><td>1</td><td>Villach</td><td>39</td></tr><tr><td>2</td><td>Salzburg</td><td>41</td></tr>")))   // the two teams swapped ranks
    }

    @Test func unreadablePagesGiveNil() throws {
        #expect(PageParser.snapshot(html: try fixture("error"), kind: .table) == nil)
        #expect(PageParser.snapshot(html: "", kind: .table) == nil)
        let wrongTitle = try fixture("table").replacingOccurrences(of: "<title>Tabelle | ICE | ÖEHV</title>", with: "<title>Tabelle | ICE</title>")
        #expect(PageParser.snapshot(html: wrongTitle, kind: .table) == nil)
    }
}
