import Foundation

/// One way of reading the dropped text. Ambiguous input produces several readings
/// and the ranker keeps the best-scoring one.
struct Reading: Equatable {
    var title: String
    var version: String?
    var artist: String?
}

struct ParsedQuery: Equatable {
    var cleaned: String
    var url: URL?
    var readings: [Reading]
    /// Free-text term for catalog search.
    var searchTerm: String
}

enum QueryParser {
    private static let dashes = [" - ", " \u{2013} ", " \u{2014} "]

    static func parse(_ raw: String) -> ParsedQuery {
        var s = raw
        for q in ["\"", "\u{201C}", "\u{201D}"] { s = s.replacingOccurrences(of: q, with: "") }
        s = TextUtil.collapse(s)

        // Plain link, no spaces.
        if !s.contains(" "), let url = URL(string: s), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https", url.host != nil {
            return ParsedQuery(cleaned: s, url: url, readings: [], searchTerm: s)
        }

        let g = TitleSplitter.extractGroups(s)
        var readings: [Reading] = []

        func add(title: String, artist: String?) {
            let t = TextUtil.collapse(title)
            guard !t.isEmpty else { return }
            let d = TitleSplitter.dashVersion(t)
            let version = g.version ?? d.version
            let a = artist.map(TextUtil.collapse)
            readings.append(Reading(title: d.base, version: version, artist: (a?.isEmpty ?? true) ? nil : a))
        }

        let stripped = g.stripped

        // "Title by Artist": split on the LAST " by " so "Stand by Me by Ben E. King" works.
        if let r = stripped.range(of: " by ", options: [.caseInsensitive, .backwards]) {
            let left = String(stripped[..<r.lowerBound])
            let right = String(stripped[r.upperBound...])
            if !left.isEmpty && !right.isEmpty { add(title: left, artist: right) }
        }

        // "Artist - Title" (the usual order), then the reverse.
        var firstDash: Range<String.Index>? = nil
        for d in dashes {
            if let r = stripped.range(of: d) {
                if firstDash == nil || r.lowerBound < firstDash!.lowerBound { firstDash = r }
            }
        }
        if let r = firstDash {
            let left = String(stripped[..<r.lowerBound])
            let right = String(stripped[r.upperBound...])
            if !left.isEmpty && !right.isEmpty {
                add(title: right, artist: left)
                add(title: left, artist: right)
            }
        }

        // Always keep the whole string as a title-only reading.
        add(title: stripped, artist: nil)

        return ParsedQuery(cleaned: s, url: nil, readings: readings, searchTerm: TextUtil.normalize(s))
    }
}
