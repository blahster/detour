import Foundation

struct Candidate: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let artworkURL: URL?
    let durationMs: Int?
    let pageURL: URL
}

struct Ranked {
    let candidate: Candidate
    let score: Double
}

enum Decision {
    case play(Candidate)
    case choose([Candidate])
    case none
}

enum Ranker {
    /// Alternate takes the user almost never wants unless they asked for them.
    private static let junk = [
        "karaoke", "tribute", "cover", "instrumental", "lullaby", "8bit", "8 bit",
        "backing track", "originally performed", "made famous"
    ]

    static func rank(_ q: ParsedQuery, _ candidates: [Candidate]) -> [Ranked] {
        var seen = Set<String>()
        var out: [(Int, Ranked)] = []
        for (i, c) in candidates.enumerated() {
            let key = TextUtil.normalize(c.title) + "|" + TextUtil.normalize(c.artist)
            if !seen.insert(key).inserted { continue }     // same song on a compilation etc.
            out.append((i, Ranked(candidate: c, score: score(q, c))))
        }
        out.sort { a, b in a.1.score != b.1.score ? a.1.score > b.1.score : a.0 < b.0 }
        return out.map { $0.1 }
    }

    static func score(_ q: ParsedQuery, _ c: Candidate) -> Double {
        let cp = TitleSplitter.split(c.title)
        var best = 0.0
        for r in q.readings { best = max(best, score(r, c, cp)) }

        // Penalise karaoke/tribute/cover versions unless the query mentions them.
        let hay = " " + TextUtil.normalize([c.title, c.artist, c.album ?? ""].joined(separator: " ")) + " "
        let query = " " + TextUtil.normalize(q.cleaned) + " "
        for j in junk where hay.contains(" " + j + " ") && !query.contains(" " + j + " ") {
            best *= 0.5
            break
        }
        return best
    }

    private static func score(_ r: Reading, _ c: Candidate, _ cp: VersionSplit) -> Double {
        let titleS = TextUtil.dice(TextUtil.tokenSet(r.title), TextUtil.tokenSet(cp.base))
        var num = 0.4 * titleS
        var den = 0.4

        if let a = r.artist {
            let qa = TextUtil.tokenSet(a)
            let ca = TextUtil.tokenSet(c.artist)
            // Containment forgives "Daft Punk" vs "Daft Punk & Pharrell Williams", but only for
            // multi-word artists; a lone word like "Me" must not match "Me First" outright.
            let contained = qa.count >= 2 ? 0.9 * TextUtil.containment(qa, ca) : 0
            num += 0.3 * max(TextUtil.dice(qa, ca), contained)
            den += 0.3
        }

        let qv = TextUtil.tokenSet(r.version ?? "")
        let cv = TextUtil.tokenSet(cp.version ?? "")
        if !qv.isEmpty {
            // The user named a specific mix: it has to match.
            let vs: Double = cv.isEmpty ? 0 : (qv.isSubset(of: cv) ? 1.0 : TextUtil.dice(qv, cv))
            num += 0.3 * vs
            den += 0.3
        } else {
            // No mix named: mild preference for the original.
            num += 0.15 * (cv.isEmpty ? 1.0 : 0.4)
            den += 0.15
        }
        return num / den
    }

    /// Auto-play only when the top hit is clearly right; otherwise let the user pick.
    static func decide(_ ranked: [Ranked]) -> Decision {
        guard let best = ranked.first else { return .none }
        if best.score >= 0.9 && (ranked.count < 2 || best.score - ranked[1].score >= 0.05) {
            return .play(best.candidate)
        }
        if best.score >= 0.35 {
            return .choose(ranked.prefix(3).map { $0.candidate })
        }
        return .none
    }
}
