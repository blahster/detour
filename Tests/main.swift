import Foundation

// Plain-assertion test runner so no XCTest / Xcode project is needed:
//   ./build.sh test

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("ok   \(msg)") } else { print("FAIL \(msg)"); failures += 1 }
}

func cand(_ id: String, _ title: String, _ artist: String, album: String? = nil) -> Candidate {
    Candidate(id: id, title: title, artist: artist, album: album, artworkURL: nil,
              durationMs: 300_000, pageURL: URL(string: "https://music.apple.com/in/album/x?i=\(id)")!)
}

// --- Parser ---------------------------------------------------------------

let p1 = QueryParser.parse("\"Missing\" (Todd Terry Club Mix) by Everything But The Girl")
check(p1.readings.first == Reading(title: "Missing", version: "Todd Terry Club Mix", artist: "Everything But The Girl"),
      "by-form with quotes and mix tag")

let p2 = QueryParser.parse("Everything But The Girl - Missing (Todd Terry Club Mix)")
check(p2.readings.first == Reading(title: "Missing", version: "Todd Terry Club Mix", artist: "Everything But The Girl"),
      "artist - title form")

let p3 = QueryParser.parse("Stand by Me by Ben E. King")
check(p3.readings.first == Reading(title: "Stand by Me", version: nil, artist: "Ben E. King"),
      "last ' by ' wins")

let p4 = QueryParser.parse("Daft Punk – Get Lucky (feat. Pharrell Williams)")
check(p4.readings.first == Reading(title: "Get Lucky", version: nil, artist: "Daft Punk"),
      "feat. group dropped, en dash handled")

let p5 = QueryParser.parse("https://music.apple.com/in/album/missing/123?i=456")
check(p5.url != nil && p5.readings.isEmpty, "URL passes through")

let p6 = QueryParser.parse("Missing - Todd Terry Club Mix")
check(p6.readings.contains(Reading(title: "Missing", version: "Todd Terry Club Mix", artist: nil)),
      "dash-suffix mix tag")

// --- Ranker ---------------------------------------------------------------

let pool = [
    cand("1", "Missing (Todd Terry Club Mix)", "Everything But The Girl"),
    cand("2", "Missing (Todd Terry Remix)", "Everything But The Girl"),
    cand("3", "Missing", "Everything But The Girl"),
    cand("4", "Missing (Todd Terry Club Mix)", "Everything But The Girl", album: "Compilation"),
    cand("5", "Missing", "Missing Persons"),
    cand("6", "Missing (Karaoke Version)", "Party Tyme Karaoke"),
]

let q1 = QueryParser.parse("\"Missing\" (Todd Terry Club Mix) by Everything But The Girl")
let r1 = Ranker.rank(q1, pool)
if case .play(let c) = Ranker.decide(r1) { check(c.id == "1", "exact mix auto-plays") }
else { check(false, "exact mix auto-plays") }
check(r1.count == 5, "duplicate title+artist collapsed")

let q2 = QueryParser.parse("Missing by Everything But The Girl")
if case .play(let c) = Ranker.decide(Ranker.rank(q2, pool)) { check(c.id == "3", "no mix named -> original") }
else { check(false, "no mix named -> original") }

let onlyOriginal = [cand("3", "Missing", "Everything But The Girl"), cand("5", "Missing", "Missing Persons")]
if case .choose = Ranker.decide(Ranker.rank(q1, onlyOriginal)) { check(true, "named mix absent -> ask, don't guess") }
else { check(false, "named mix absent -> ask, don't guess") }

let q3 = QueryParser.parse("Missing")
if case .choose(let cs) = Ranker.decide(Ranker.rank(q3, pool)) { check(cs.count >= 2, "bare title is ambiguous") }
else { check(false, "bare title is ambiguous") }

let q4 = QueryParser.parse("Stand By Me")
let sbm = [cand("9", "Stand by Me", "Ben E. King"), cand("10", "Stand", "Me First")]
if case .play(let c) = Ranker.decide(Ranker.rank(q4, sbm)) { check(c.id == "9", "title containing 'by' still resolves") }
else { check(false, "title containing 'by' still resolves") }

print(failures == 0 ? "\nAll tests passed." : "\n\(failures) failure(s).")
exit(failures == 0 ? 0 : 1)
