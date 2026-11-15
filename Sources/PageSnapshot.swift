import CryptoKit
import Foundation

struct GameInfo: Codable, Equatable {
    var score: String?
    var live: Bool
    var hasLineup: Bool
}

/// One table of the page: its column titles and the cells of every data row.
struct TableData: Codable, Equatable {
    var headers: [String]
    var rows: [[String]]
}

struct PageSnapshot: Codable, Equatable {
    var kind: PageKind
    var title: String        // the page's <h1>, falling back to <title>
    var textHash: String     // hex SHA-256 of the whole visible text
    var game: GameInfo?      // only for kind == .game
    var tables: [TableData]? = nil   // the page tables cell by cell (nil in states saved before this existed)
    var blocks: [String]? = nil   // the page text in blocks, to show exactly what changed (nil in states saved before this existed)
}

/// Reads a page of eishockey.at into a snapshot. Layout facts: docs/notes/monitoring-page-data.md.
enum PageParser {
    static let minimumTextLength = 1000

    /// nil means "cannot read" (error page, redesign, empty): callers must change nothing.
    static func snapshot(html: String, kind: PageKind) -> PageSnapshot? {
        guard let pageTitle = firstGroup(#"(?is)<title[^>]*>(.*?)</title>"#, in: html).map({ plain($0) }),
              pageTitle.hasSuffix("ÖEHV") else { return nil }
        let text = visibleText(html)
        guard text.count >= minimumTextLength else { return nil }
        let heading = firstGroup(#"(?is)<h1[^>]*>(.*?)</h1>"#, in: html).map { plain($0) }.flatMap { $0.isEmpty ? nil : $0 }
        let pageBlocks = blocks(html)
        let hash = SHA256.hash(data: Data(pageBlocks.sorted().joined(separator: "\u{1F}").utf8)).map { String(format: "%02x", $0) }.joined()
        var game: GameInfo?
        if kind == .game {
            let beforeBar = pageTitle.split(separator: "|", maxSplits: 1).first.map(String.init) ?? pageTitle
            let score = firstGroups(#"(\d+):(\d+)"#, in: beforeBar).map { "\($0[0]):\($0[1])" }
            let live = html.contains(#"\"live\":true"#) || html.contains(#""live":true"#)
            game = GameInfo(score: score, live: live, hasLineup: hasHeading("Aufstellung", in: html))
        }
        return PageSnapshot(kind: kind, title: heading ?? pageTitle, textHash: hash, game: game, tables: tables(html), blocks: pageBlocks)
    }

    // MARK: text

    /// The page's text in blocks: every table row as one block, every other text node on its own.
    /// The site streams parts of a page in a changing order, so the hash is taken over the sorted blocks:
    /// the same page hashes the same in any order, while a changed cell or a changed rank still changes it.
    static func blocks(_ html: String) -> [String] {
        let stripped = html.replacingOccurrences(of: #"(?is)<script.*?</script>|<style.*?</style>|<!--.*?-->"#, with: " ", options: .regularExpression)
        let rowPattern = #"(?is)<tr[^>]*>.*?</tr>"#
        var out: [String] = []
        let rows = try! NSRegularExpression(pattern: rowPattern)
        for m in rows.matches(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) {
            if let range = Range(m.range, in: stripped) { let t = plain(String(stripped[range])); if !t.isEmpty { out.append(t) } }
        }
        let rest = stripped.replacingOccurrences(of: rowPattern, with: "<x>", options: .regularExpression)
        let nodes = try! NSRegularExpression(pattern: #">([^<]+)<"#)
        for m in nodes.matches(in: rest, range: NSRange(rest.startIndex..., in: rest)) {
            if let range = Range(m.range(at: 1), in: rest) { let t = collapse(decodeEntities(String(rest[range]))); if !t.isEmpty { out.append(t) } }
        }
        return out
    }

    /// Every <table> with its column titles (the <th> row) and the cells of its data rows.
    static func tables(_ html: String) -> [TableData] {
        let stripped = html.replacingOccurrences(of: #"(?is)<script.*?</script>|<style.*?</style>|<!--.*?-->"#, with: " ", options: .regularExpression)
        func matches(_ pattern: String, in s: String) -> [String] {
            try! NSRegularExpression(pattern: pattern).matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
        }
        return matches(#"(?is)<table[^>]*>.*?</table>"#, in: stripped).compactMap { table in
            var data = TableData(headers: [], rows: [])
            for row in matches(#"(?is)<tr[^>]*>.*?</tr>"#, in: table) {
                let cells = matches(#"(?is)<t[dh][^>]*>.*?</t[dh]>"#, in: row)
                let texts = cells.map { plain($0) }
                guard texts.contains(where: { !$0.isEmpty }) else { continue }
                if cells.allSatisfy({ $0.lowercased().hasPrefix("<th") }) { if data.headers.isEmpty { data.headers = texts } } else { data.rows.append(texts) }
            }
            return data.rows.isEmpty ? nil : data
        }
    }

    static func visibleText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"(?is)<script.*?</script>|<style.*?</style>|<!--.*?-->"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return collapse(decodeEntities(s))
    }
    private static func plain(_ fragment: String) -> String {
        collapse(decodeEntities(fragment.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)))
    }
    private static func collapse(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func hasHeading(_ text: String, in html: String) -> Bool {
        let regex = try! NSRegularExpression(pattern: #"(?is)<h2[^>]*>(.*?)</h2>"#)
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).contains { m in
            Range(m.range(at: 1), in: html).map { plain(String(html[$0])) == text } ?? false
        }
    }
    private static func firstGroup(_ pattern: String, in s: String) -> String? { firstGroups(pattern, in: s)?.first }
    private static func firstGroups(_ pattern: String, in s: String) -> [String]? {
        let regex = try! NSRegularExpression(pattern: pattern)
        guard let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: s).map { String(s[$0]) } }
    }
    private static func decodeEntities(_ s: String) -> String {
        var out = s
        for (name, value) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"), ("&#x27;", "'")] { out = out.replacingOccurrences(of: name, with: value) }
        let numeric = try! NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#)
        for m in numeric.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
            let hex = Range(m.range(at: 1), in: out).map { !out[$0].isEmpty } ?? false
            guard let digits = Range(m.range(at: 2), in: out), let code = UInt32(out[digits], radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code),
                  let whole = Range(m.range, in: out) else { continue }
            out.replaceSubrange(whole, with: String(Character(scalar)))
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")  // last, so "&amp;lt;" stays "&lt;"
    }
}
