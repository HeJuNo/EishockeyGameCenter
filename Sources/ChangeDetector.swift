import Foundation

enum ChangeKind: Equatable { case started, score, finished, lineup, updated }

/// The notification switches in the settings.
enum NotificationCategory: String, Codable, CaseIterable { case score, lineup, statistics }

struct Change: Equatable {
    let page: WatchedPage
    let kind: ChangeKind
    let title: String   // the page title
    let body: String    // German text

    var category: NotificationCategory {
        switch kind {
        case .started, .score, .finished: .score
        case .lineup: .lineup
        case .updated: .statistics
        }
    }
}

enum ChangeDetector {
    /// What changed between two snapshots of the same page. No old snapshot means "first look": nothing to report.
    static func changes(page: WatchedPage, old: PageSnapshot?, new: PageSnapshot) -> [Change] {
        guard let old, old.kind == new.kind else { return [] }
        func change(_ kind: ChangeKind, _ body: String) -> Change { Change(page: page, kind: kind, title: page.title, body: body) }

        guard new.kind == .game else {
            guard old.textHash != new.textHash else { return [] }
            let body: String
            switch new.kind {
            case .table: body = "Tabelle aktualisiert"
            case .goalies: body = "Torhüter-Statistik aktualisiert"
            case .topscorers: body = "Topscorer aktualisiert"
            default: body = "Team-Seite aktualisiert"
            }
            return [change(.updated, body)]
        }
        guard let before = old.game, let now = new.game else { return [] }

        var out: [Change] = []
        if let score = now.score {
            if before.score == nil {
                out.append(now.live ? change(.started, "Spiel gestartet, Stand \(score)") : change(.finished, "Endergebnis \(score)"))
            } else if before.live && !now.live {
                out.append(change(.finished, "Endergebnis \(score)"))
            } else if before.score != score {
                out.append(change(.score, "Stand \(score)"))
            }
        }
        if !before.hasLineup && now.hasLineup { out.append(change(.lineup, "Aufstellung veröffentlicht")) }
        // While a game runs its text changes constantly: only after the game does a text change count.
        if out.isEmpty, !now.live, now.score != nil, old.textHash != new.textHash { out.append(change(.updated, "Statistik aktualisiert")) }
        return out
    }
}
