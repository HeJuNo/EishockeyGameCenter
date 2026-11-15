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
    enum Side: String, Codable { case removed, added, changed }
    let side: Side
    let text: String
}

enum ChangeDetector {
    static let maxLines = 100

    /// Exactly what changed: per table row the cells that differ ("Team: Pkt 41 → 43"), rows that are new or gone,
    /// and the other text of the page that is new or gone. Order-free: moved blocks are not a change.
    static func details(old: PageSnapshot, new: PageSnapshot) -> [DiffLine] {
        var out: [DiffLine] = []
        if let a = old.tables, let b = new.tables { out += tableDiff(a, b) }
        let rowTexts = Set(((old.tables ?? []) + (new.tables ?? [])).flatMap { $0.rows.map { $0.joined(separator: " ") } })
        let otherOld = old.blocks.map { $0.filter { !rowTexts.contains($0) } }, otherNew = new.blocks.map { $0.filter { !rowTexts.contains($0) } }
        // A table whose rows were not parsed (states from before tables were kept) falls back to whole blocks.
        out += diff(old: (old.tables == nil || new.tables == nil) ? old.blocks : otherOld, new: (old.tables == nil || new.tables == nil) ? new.blocks : otherNew)
        return Array(out.prefix(maxLines))
    }

    /// Blocks that are only in the old page (removed) or only in the new one (added). Order-free, repeated blocks count.
    static func diff(old: [String]?, new: [String]?) -> [DiffLine] {
        guard let old, let new else { return [] }
        var counts: [String: Int] = [:]
        for b in old { counts[b, default: 0] += 1 }
        var added: [String] = []
        for b in new { if let n = counts[b], n > 0 { counts[b] = n - 1 } else { added.append(b) } }
        var removed: [String] = []
        for b in old { if let n = counts[b], n > 0 { counts[b] = n - 1; removed.append(b) } }
        return removed.map { DiffLine(side: .removed, text: $0) } + added.map { DiffLine(side: .added, text: $0) }
    }

    private static func tableDiff(_ old: [TableData], _ new: [TableData]) -> [DiffLine] {
        var out: [DiffLine] = []
        var used = Set<Int>()
        for table in new {
            // The same table in the old page: same column titles, the first one not matched yet.
            guard let index = old.indices.first(where: { !used.contains($0) && old[$0].headers == table.headers }) else {
                out += table.rows.map { DiffLine(side: .added, text: rowText($0, table.headers)) }; continue
            }
            used.insert(index)
            let beforeList = keyed(old[index].rows), afterList = keyed(table.rows)
            let before = Dictionary(uniqueKeysWithValues: beforeList), after = Dictionary(uniqueKeysWithValues: afterList)
            let labels = table.headers
            for (key, row) in afterList {
                guard let was = before[key] else { out.append(DiffLine(side: .added, text: rowText(row, labels))); continue }
                guard was != row else { continue }
                let parts = row.indices.compactMap { i -> String? in
                    guard i < was.count, was[i] != row[i] else { return nil }
                    let label = i < labels.count && !labels[i].isEmpty ? labels[i] : (i == 0 ? "Rang" : "Spalte \(i + 1)")
                    return "\(label) \(was[i]) → \(row[i])"
                }
                out.append(DiffLine(side: .changed, text: "\(name(of: row)): " + (parts.isEmpty ? rowText(row, labels) : parts.joined(separator: ", "))))
            }
            for (key, row) in beforeList where after[key] == nil { out.append(DiffLine(side: .removed, text: rowText(row, old[index].headers))) }
        }
        for index in old.indices where !used.contains(index) { out += old[index].rows.map { DiffLine(side: .removed, text: rowText($0, old[index].headers)) } }
        return out
    }

    /// A row is recognised by its first cell with letters (team or player), numbered when it repeats.
    private static func keyed(_ rows: [[String]]) -> [(String, [String])] {
        var seen: [String: Int] = [:]
        return rows.map { row in
            let base = name(of: row)
            seen[base, default: 0] += 1
            return (seen[base]! > 1 ? "\(base)#\(seen[base]!)" : base, row)
        }
    }
    private static func name(of row: [String]) -> String { row.first { $0.contains { $0.isLetter } } ?? row.first ?? "" }
    /// "Team: Sp 17, Pkt 58": the row with its column titles (plain cells when the titles do not fit).
    private static func rowText(_ row: [String], _ headers: [String]) -> String {
        guard headers.count == row.count else { return row.joined(separator: " ") }
        let key = name(of: row)
        let rest = row.indices.filter { row[$0] != key || $0 != row.firstIndex(of: key) }.map { headers[$0].isEmpty ? row[$0] : "\(headers[$0]) \(row[$0])" }
        return "\(key): " + rest.joined(separator: ", ")
    }
    /// What changed between two snapshots of the same page. No old snapshot means "first look": nothing to report.
    static func changes(page: WatchedPage, old: PageSnapshot?, new: PageSnapshot) -> [Change] {
        guard let old, old.kind == new.kind else { return [] }
        let textLines = details(old: old, new: new)
        func change(_ kind: ChangeKind, _ body: String, lines: [DiffLine] = []) -> Change { Change(page: page, kind: kind, title: page.title, body: body, lines: lines) }

        guard new.kind == .game else {
            guard old.textHash != new.textHash else { return [] }
            let body: String
            switch new.kind {
            case .table: body = "Tabelle aktualisiert"
            case .goalies: body = "Torhüter-Statistik aktualisiert"
            case .topscorers: body = page.isPenaltyList ? "Strafenliste aktualisiert" : "Spielerstatistik aktualisiert"
            case .teamStats: body = "Team-Statistik aktualisiert"
            default: body = "Team-Seite aktualisiert"
            }
            return [change(.updated, body + summary(of: textLines), lines: textLines)]
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

    /// " – Olimpija Ljubljana: Pkt 41 → 43 (+2 weitere)": the first change in the notification text.
    private static func summary(of lines: [DiffLine]) -> String {
        guard let first = lines.first(where: { $0.side == .changed }) ?? lines.first else { return "" }
        let text = first.side == .added ? "neu: \(first.text)" : first.side == .removed ? "weg: \(first.text)" : first.text
        return " – " + String(text.prefix(90)) + (lines.count > 1 ? " (+\(lines.count - 1) weitere)" : "")
    }
}
