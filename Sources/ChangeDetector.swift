import Foundation

enum ChangeKind: Equatable { case started, score, finished, lineup, updated }

/// The notification switches in the settings.
enum NotificationCategory: String, Codable, CaseIterable { case score, lineup, statistics }

struct Change: Equatable {
    let page: WatchedPage
    let kind: ChangeKind
    let title: String   // the page title
    let body: String    // German text
    var lines: [DiffLine] = []   // exactly what changed on the page

    var category: NotificationCategory {
        switch kind {
        case .started, .score, .finished: .score
        case .lineup: .lineup
        case .updated: .statistics
        }
    }
}

/// One line of the page that is gone (removed) or new (added).
struct DiffLine: Codable, Equatable {
    enum Side: String, Codable { case removed, added }
    let side: Side
    let text: String
}

enum ChangeDetector {
    static let maxLines = 60

    /// Blocks that are only in the old page (removed) or only in the new one (added). Order-free, repeated blocks count.
    static func diff(old: [String]?, new: [String]?) -> [DiffLine] {
        guard let old, let new else { return [] }
        var counts: [String: Int] = [:]
        for b in old { counts[b, default: 0] += 1 }
        var added: [String] = []
        for b in new { if let n = counts[b], n > 0 { counts[b] = n - 1 } else { added.append(b) } }
        var removed: [String] = []
        for b in old { if let n = counts[b], n > 0 { counts[b] = n - 1; removed.append(b) } }
        return Array((removed.map { DiffLine(side: .removed, text: $0) } + added.map { DiffLine(side: .added, text: $0) }).prefix(maxLines))
    }

    /// What changed between two snapshots of the same page. No old snapshot means "first look": nothing to report.
    static func changes(page: WatchedPage, old: PageSnapshot?, new: PageSnapshot) -> [Change] {
        guard let old, old.kind == new.kind else { return [] }
        let textLines = diff(old: old.blocks, new: new.blocks)
        func change(_ kind: ChangeKind, _ body: String, lines: [DiffLine] = []) -> Change { Change(page: page, kind: kind, title: page.title, body: body, lines: lines) }

        guard new.kind == .game else {
            guard old.textHash != new.textHash else { return [] }
            let body: String
            switch new.kind {
            case .table: body = "Tabelle aktualisiert"
            case .goalies: body = "Torhüter-Statistik aktualisiert"
            case .topscorers: body = "Topscorer aktualisiert"
            default: body = "Team-Seite aktualisiert"
            }
            return [change(.updated, body, lines: textLines)]
        }
        guard let before = old.game, let now = new.game else { return [] }

        var out: [Change] = []
        func scoreLines() -> [DiffLine] {
            guard before.score != now.score, let score = now.score else { return [] }
            return (before.score.map { [DiffLine(side: .removed, text: "Stand \($0)")] } ?? []) + [DiffLine(side: .added, text: "Stand \(score)")]
        }
        if let score = now.score {
            if before.score == nil {
                out.append(now.live ? change(.started, "Spiel gestartet, Stand \(score)", lines: scoreLines()) : change(.finished, "Endergebnis \(score)", lines: scoreLines()))
            } else if before.live && !now.live {
                out.append(change(.finished, "Endergebnis \(score)", lines: scoreLines()))
            } else if before.score != score {
                out.append(change(.score, "Stand \(score)", lines: scoreLines()))
            }
        }
        if !before.hasLineup && now.hasLineup { out.append(change(.lineup, "Aufstellung veröffentlicht", lines: textLines)) }
        // While a game runs its text changes constantly: only after the game does a text change count.
        if out.isEmpty, !now.live, now.score != nil, old.textHash != new.textHash { out.append(change(.updated, "Statistik aktualisiert", lines: textLines)) }
        return out
    }
}
