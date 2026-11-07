import Foundation
import MusicKit

/// Finds songs in the Apple Music catalog with MusicKit and keeps the `Song` objects so the
/// player can queue exactly the one the user (or the ranker) picked.
@MainActor
final class CatalogResolver {
    enum ResolverError: LocalizedError {
        case unsupported(String)
        var errorDescription: String? {
            switch self { case .unsupported(let m): return m }
        }
    }

    private var songs: [String: Song] = [:]

    func song(for candidate: Candidate) -> Song? { songs[candidate.id] }

    func candidates(for q: ParsedQuery) async throws -> [Candidate] {
        songs = [:]
        if let url = q.url { return try await fromLink(url) }

        // First the cleanest reading ("title version artist"), then the raw text as a backstop.
        var terms = [Self.primaryTerm(q)]
        if q.searchTerm != terms[0] { terms.append(q.searchTerm) }

        var all: [Candidate] = []
        var seen = Set<String>()
        for term in terms {
            var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
            request.limit = 25
            let response = try await request.response()
            for c in remember(response.songs) where seen.insert(c.id).inserted {
                all.append(c)
            }
        }
        return all
    }

    private static func primaryTerm(_ q: ParsedQuery) -> String {
        guard let r = q.readings.first else { return q.searchTerm }
        let term = [r.title, r.version, r.artist].compactMap { $0 }.joined(separator: " ")
        return TextUtil.normalize(term)
    }

    private func fromLink(_ url: URL) async throws -> [Candidate] {
        guard let host = url.host, host.hasSuffix("music.apple.com") else {
            throw ResolverError.unsupported("Only Apple Music links or song titles are supported for now.")
        }
        var id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "i" })?.value
        if id == nil, url.pathComponents.contains("song"),
           let last = url.pathComponents.last, last.allSatisfy(\.isNumber) {
            id = last
        }
        guard let trackID = id else {
            throw ResolverError.unsupported("That link isn't a single song. Drop a song link or a title.")
        }
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(trackID))
        let response = try await request.response()
        return remember(response.items)
    }

    private func remember(_ items: MusicItemCollection<Song>) -> [Candidate] {
        items.map { song in
            songs[song.id.rawValue] = song
            return Candidate(
                id: song.id.rawValue,
                title: song.title,
                artist: song.artistName,
                album: song.albumTitle,
                artworkURL: song.artwork?.url(width: 240, height: 240),
                durationMs: song.duration.map { Int($0 * 1000) },
                pageURL: song.url ?? URL(string: "https://music.apple.com")!
            )
        }
    }
}
