import Foundation

/// Small text helpers shared by the parser and the ranker. Foundation only.
enum TextUtil {
    static func collapse(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Lowercase, strip accents and punctuation, "&" -> "and", collapse spaces.
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var out = ""
        for ch in folded {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
            } else if ch == "&" {
                out += " and "
            } else if ch == "'" || ch == "\u{2019}" {
                continue            // don't -> dont
            } else {
                out.append(" ")
            }
        }
        return collapse(out)
    }

    static func tokens(_ s: String) -> [String] {
        normalize(s).split(separator: " ").map(String.init)
    }

    static func tokenSet(_ s: String) -> Set<String> { Set(tokens(s)) }

    /// 2|A∩B| / (|A|+|B|)
    static func dice(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        return 2.0 * Double(a.intersection(b).count) / Double(a.count + b.count)
    }

    /// Fraction of `a` that appears in `b`.
    static func containment(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty { return 0 }
        return Double(a.intersection(b).count) / Double(a.count)
    }
}

struct VersionSplit: Equatable {
    var base: String
    var version: String?
    var featuring: String?
}

/// Splits "Missing (Todd Terry Club Mix)" into base title + version tag.
enum TitleSplitter {
    static let versionWords: Set<String> = [
        "mix", "remix", "edit", "version", "dub", "live", "remaster", "remastered",
        "acoustic", "instrumental", "extended", "radio", "club", "demo", "reprise",
        "rework", "bootleg", "vip", "session", "unplugged"
    ]
    static let dashes = [" - ", " \u{2013} ", " \u{2014} "]

    static func isFeaturing(_ s: String) -> Bool {
        let l = s.lowercased()
        return ["feat.", "feat ", "ft.", "ft ", "featuring ", "with "].contains { l.hasPrefix($0) }
    }

    /// Removes (...) and [...] groups. "feat." groups are dropped; the rest become the version.
    static func extractGroups(_ input: String) -> (stripped: String, version: String?, featuring: String?) {
        let chars = Array(input)
        var base = ""
        var versions: [String] = []
        var feat: String? = nil
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "(" || c == "[" {
                let close: Character = (c == "(") ? ")" : "]"
                if let j = chars[(i + 1)...].firstIndex(of: close) {
                    let inner = TextUtil.collapse(String(chars[(i + 1)..<j]))
                    if isFeaturing(inner) {
                        feat = inner
                    } else if !inner.isEmpty {
                        versions.append(inner)
                    }
                    i = j + 1
                    continue
                }
            }
            base.append(c)
            i += 1
        }
        return (TextUtil.collapse(base), versions.isEmpty ? nil : versions.joined(separator: " "), feat)
    }

    /// "Missing - Todd Terry Club Mix" -> ("Missing", "Todd Terry Club Mix"), only when the
    /// suffix contains a version word, so "Daft Punk - Get Lucky" is left alone.
    static func dashVersion(_ s: String) -> (base: String, version: String?) {
        var best: Range<String.Index>? = nil
        for d in dashes {
            if let r = s.range(of: d, options: .backwards) {
                if best == nil || r.lowerBound > best!.lowerBound { best = r }
            }
        }
        guard let r = best else { return (s, nil) }
        let suffix = TextUtil.collapse(String(s[r.upperBound...]))
        let prefix = TextUtil.collapse(String(s[..<r.lowerBound]))
        if !prefix.isEmpty, TextUtil.tokens(suffix).contains(where: { versionWords.contains($0) }) {
            return (prefix, suffix)
        }
        return (s, nil)
    }

    static func split(_ input: String) -> VersionSplit {
        let g = extractGroups(input)
        if g.version != nil {
            return VersionSplit(base: g.stripped, version: g.version, featuring: g.featuring)
        }
        let d = dashVersion(g.stripped)
        return VersionSplit(base: d.base, version: d.version, featuring: g.featuring)
    }
}
