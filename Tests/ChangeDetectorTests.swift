import Foundation
import Testing
@testable import EishockeyGameCenter

@MainActor @Suite struct ChangeDetectorTests {
    private func page(_ kind: PageKind = .game) -> WatchedPage {
        WatchedPage(url: URL(string: "https://www.eishockey.at/game-center/ice/x")!, kind: kind, title: "Seite")
    }
    private func game(score: String? = nil, live: Bool = false, lineup: Bool = false, hash: String = "h") -> PageSnapshot {
        PageSnapshot(kind: .game, title: "Seite", textHash: hash, game: GameInfo(score: score, live: live, hasLineup: lineup))
    }
    private func other(_ kind: PageKind, hash: String) -> PageSnapshot { PageSnapshot(kind: kind, title: "Seite", textHash: hash, game: nil) }
    private func detect(_ old: PageSnapshot?, _ new: PageSnapshot) -> [Change] { ChangeDetector.changes(page: page(new.kind), old: old, new: new) }

    @Test func noOldMeansBaseline() {
        #expect(detect(nil, game(score: "1:0", live: true)).isEmpty)
        #expect(detect(nil, other(.table, hash: "a")).isEmpty)
    }

    @Test func firstScoreMeansStarted() {
        let c = detect(game(), game(score: "1:0", live: true))
        #expect(c.map(\.kind) == [.started])
        #expect(c.first?.body == "Spiel gestartet, Stand 1:0")
    }

    @Test func scoreChange() {
        let c = detect(game(score: "1:0", live: true), game(score: "1:1", live: true))
        #expect(c.map(\.kind) == [.score])
        #expect(c.first?.body == "Stand 1:1")
    }

    @Test func finishedWhenNoLongerLive() {
        let c = detect(game(score: "3:2", live: true), game(score: "3:2", live: false))
        #expect(c.map(\.kind) == [.finished])
        #expect(c.first?.body == "Endergebnis 3:2")
    }

    @Test func finishedWithLastGoal() {
        #expect(detect(game(score: "2:2", live: true), game(score: "3:2", live: false)).map(\.kind) == [.finished])
    }

    @Test func gameThatStartedAndEndedBetweenChecksIsFinished() {
        #expect(detect(game(), game(score: "4:2", live: false)).map(\.kind) == [.finished])
    }

    @Test func lineupPublished() {
        let c = detect(game(lineup: false), game(lineup: true))
        #expect(c.map(\.kind) == [.lineup])
        #expect(c.first?.body == "Aufstellung veröffentlicht")
    }

    @Test func liveTextChangesAreIgnored() {
        #expect(detect(game(score: "1:0", live: true, hash: "a"), game(score: "1:0", live: true, hash: "b")).isEmpty)
    }

    @Test func statisticsAfterTheGame() {
        let c = detect(game(score: "3:2", hash: "a"), game(score: "3:2", hash: "b"))
        #expect(c.map(\.kind) == [.updated])
        #expect(c.first?.body == "Statistik aktualisiert")
        #expect(detect(game(score: nil, hash: "a"), game(score: nil, hash: "b")).isEmpty)  // planned game: text changes are noise
    }

    @Test func otherKinds() {
        let expected: [(PageKind, String)] = [(.table, "Tabelle aktualisiert"), (.goalies, "Torhüter-Statistik aktualisiert"),
                                              (.topscorers, "Spielerstatistik aktualisiert"), (.team, "Team-Seite aktualisiert"), (.teamStats, "Team-Statistik aktualisiert")]
        for (kind, body) in expected {
            let c = detect(other(kind, hash: "a"), other(kind, hash: "b"))
            #expect(c.map(\.kind) == [.updated], Comment(rawValue: "\(kind)"))
            #expect(c.first?.body == body)
            #expect(detect(other(kind, hash: "a"), other(kind, hash: "a")).isEmpty)
        }
    }

    @Test func categories() {
        let p = page()
        func category(_ k: ChangeKind) -> NotificationCategory { Change(page: p, kind: k, title: "", body: "").category }
        #expect(category(.started) == .score)
        #expect(category(.score) == .score)
        #expect(category(.finished) == .score)
        #expect(category(.lineup) == .lineup)
        #expect(category(.updated) == .statistics)
    }
}

@MainActor @Suite struct ChangeDiffTests {
    private let page = WatchedPage(url: URL(string: "https://www.eishockey.at/game-center/ice/tabelle")!, kind: .table, title: "Tabelle")
    private func table(_ blocks: [String], hash: String) -> PageSnapshot { PageSnapshot(kind: .table, title: "Tabelle", textHash: hash, game: nil, blocks: blocks) }

    @Test func changedRowShowsOldAndNew() {
        let c = ChangeDetector.changes(page: page, old: table(["1 A 10", "2 B 8"], hash: "a"), new: table(["1 A 12", "2 B 8"], hash: "b"))
        #expect(c.first?.lines == [DiffLine(side: .removed, text: "1 A 10"), DiffLine(side: .added, text: "1 A 12")])
    }

    @Test func movedBlocksAreNotAChange() {
        #expect(ChangeDetector.diff(old: ["a", "b"], new: ["b", "a"]).isEmpty)
        #expect(ChangeDetector.diff(old: ["a", "a"], new: ["a"]) == [DiffLine(side: .removed, text: "a")])
    }

    @Test func statesWithoutBlocksStillNotify() {
        let c = ChangeDetector.changes(page: page, old: table([], hash: "a").withoutBlocks(), new: table(["x"], hash: "b"))
        #expect(c.count == 1 && c[0].lines.isEmpty)
    }

    @Test func scoreChangeShowsScoreLines() {
        func game(_ s: String) -> PageSnapshot { PageSnapshot(kind: .game, title: "G", textHash: "h", game: GameInfo(score: s, live: true, hasLineup: true)) }
        let c = ChangeDetector.changes(page: page, old: game("1:0"), new: game("2:0"))
        #expect(c.first?.lines == [DiffLine(side: .removed, text: "Stand 1:0"), DiffLine(side: .added, text: "Stand 2:0")])
    }

    @Test func historyIsKeptNewestFirstAndSurvivesReload() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WatchStore(directory: dir)
        store.record([Change(page: page, kind: .updated, title: "Tabelle", body: "Tabelle aktualisiert", lines: [DiffLine(side: .added, text: "x")])], at: Date(timeIntervalSince1970: 1))
        store.record([Change(page: page, kind: .updated, title: "Tabelle", body: "zweite", lines: [])], at: Date(timeIntervalSince1970: 2))
        let again = WatchStore(directory: dir)
        #expect(again.history.map(\.summary) == ["zweite", "Tabelle aktualisiert"])
        #expect(again.history[1].lines.count == 1)
    }
}

private extension PageSnapshot {
    func withoutBlocks() -> PageSnapshot { var s = self; s.blocks = nil; return s }
}

@MainActor @Suite struct TableDetailTests {
    private let page = WatchedPage(url: URL(string: "https://www.eishockey.at/game-center/ice/tabelle")!, kind: .table, title: "Tabelle")
    private func snap(_ rows: [[String]], headers: [String] = ["#", "Team", "Sp", "Pkt"], hash: String) -> PageSnapshot {
        PageSnapshot(kind: .table, title: "Tabelle", textHash: hash, game: nil, tables: [TableData(headers: headers, rows: rows)], blocks: rows.map { $0.joined(separator: " ") } + ["Stand: Montag"])
    }
    private func lines(_ a: PageSnapshot, _ b: PageSnapshot) -> [DiffLine] { ChangeDetector.changes(page: page, old: a, new: b).first?.lines ?? [] }

    @Test func changedCellsAreNamedByColumn() {
        let l = lines(snap([["1", "Salzburg", "10", "20"], ["2", "Linz", "10", "18"]], hash: "a"),
                      snap([["1", "Salzburg", "11", "23"], ["2", "Linz", "10", "18"]], hash: "b"))
        #expect(l == [DiffLine(side: .changed, text: "Salzburg: Sp 10 → 11, Pkt 20 → 23")])
    }

    @Test func rankChangeIsShownAsRankAndMovedRowsAreNotAChange() {
        let l = lines(snap([["1", "Salzburg", "10", "20"], ["2", "Linz", "10", "18"]], hash: "a"),
                      snap([["1", "Linz", "11", "21"], ["2", "Salzburg", "10", "20"]], hash: "b"))
        #expect(l.contains(DiffLine(side: .changed, text: "Linz: # 2 → 1, Sp 10 → 11, Pkt 18 → 21")))
        #expect(l.contains(DiffLine(side: .changed, text: "Salzburg: # 1 → 2")))
        #expect(l.count == 2)
    }

    @Test func newAndGoneRowsAndOtherTextAreListed() {
        let a = snap([["1", "Salzburg", "10", "20"]], hash: "a")
        var b = snap([["1", "Linz", "1", "3"]], hash: "b"); b.blocks = (b.blocks ?? []) + ["Neuer Hinweis"]
        let l = lines(a, b)
        #expect(l.contains(DiffLine(side: .removed, text: "Salzburg: # 1, Sp 10, Pkt 20")))
        #expect(l.contains(DiffLine(side: .added, text: "Linz: # 1, Sp 1, Pkt 3")))
        #expect(l.contains(DiffLine(side: .added, text: "Neuer Hinweis")))
    }

    @Test func notificationNamesTheFirstChange() {
        let c = ChangeDetector.changes(page: page, old: snap([["1", "Salzburg", "10", "20"], ["2", "Linz", "10", "18"]], hash: "a"),
                                       new: snap([["1", "Salzburg", "11", "23"], ["2", "Linz", "11", "19"]], hash: "b"))
        #expect(c.first?.body == "Tabelle aktualisiert – Salzburg: Sp 10 → 11, Pkt 20 → 23 (+1 weitere)")
    }

    @Test func parserReadsHeadersAndCells() throws {
        let html = "<table><tr><th>#</th><th><button><span>Team</span></button></th></tr><tr><td>1</td><td>EC&nbsp;KAC</td></tr></table>"
        #expect(PageParser.tables(html) == [TableData(headers: ["#", "Team"], rows: [["1", "EC KAC"]])])
    }
}
