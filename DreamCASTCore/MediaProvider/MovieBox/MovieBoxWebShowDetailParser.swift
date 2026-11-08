// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import Foundation

/// Public display fields only. The site's play links and account fields are ignored.
nonisolated struct MovieBoxWebEpisode: Identifiable, Sendable, Equatable {
    let season: Int
    let number: Int
    let title: String
    let thumbnailURL: URL?
    let runtimeMinutes: Int?

    var id: String { "\(season)-\(number)" }
}

nonisolated struct MovieBoxWebShowDetail: Sendable, Equatable {
    let id: String
    let title: String
    let year: String?
    let posterURL: URL?
    let synopsis: String?
    let seasons: [Int]
    let episodes: [MovieBoxWebEpisode]

    func episodes(in season: Int) -> [MovieBoxWebEpisode] {
        episodes.filter { $0.season == season }
    }
}

nonisolated enum MovieBoxWebShowDetailError: LocalizedError, Sendable {
    case invalidShowID
    case missingDetails

    var errorDescription: String? {
        switch self {
        case .invalidShowID:
            "The TV show ID was not valid."
        case .missingDetails:
            "MovieBox Pro did not return show details or episodes. The page may have changed."
        }
    }
}

/// Parses the browser's show page without evaluating scripts or reading play links.
nonisolated enum MovieBoxWebShowDetailParser {
    private static let titlePattern = #"<p\b[^>]*class=["']movie_title["'][^>]*>[\s\S]*?<span\b[^>]*class=["']name["'][^>]*>([^<]+)</span>"#
    private static let yearPattern = #"<span\b[^>]*class=["']year["'][^>]*>\s*([0-9]{4})\s*</span>"#
    private static let coverPattern = #"<img\b[^>]*src=["'](https://[^"']+)["'][^>]*class=["']cover["']"#
    private static let synopsisPattern = #"<p\b[^>]*style=["'][^"']*margin-top:30px[^"']*["'][^>]*>([\s\S]*?)</p>"#
    private static let seasonDataPattern = #"\bvar\s+tv_season_list\s*=\s*(\[[\s\S]*?\]);"#

    static func detail(from html: String, id: String) throws -> MovieBoxWebShowDetail {
        guard !id.isEmpty, id.count <= 20, id.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            throw MovieBoxWebShowDetailError.invalidShowID
        }
        guard let rawTitle = capture(titlePattern, from: html) else {
            throw MovieBoxWebShowDetailError.missingDetails
        }
        let title = cleanText(rawTitle)
        guard !title.isEmpty else { throw MovieBoxWebShowDetailError.missingDetails }

        // This JSON is embedded in the HTML used by the website's season picker.
        // Only the safe display keys are read. Watch progress and play tokens are ignored.
        guard let seasonJSON = capture(seasonDataPattern, from: html),
              let data = seasonJSON.data(using: .utf8),
              let seasonRows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw MovieBoxWebShowDetailError.missingDetails
        }

        var seasonNumbers: Set<Int> = []
        var episodes: [MovieBoxWebEpisode] = []
        var seen: Set<String> = []

        for seasonRow in seasonRows {
            guard let season = (seasonRow["season"] as? NSNumber)?.intValue,
                  season >= 0, season <= 100,
                  let episodeRows = seasonRow["episode_list"] as? [[String: Any]] else { continue }
            seasonNumbers.insert(season)

            for row in episodeRows.prefix(500) {
                guard let number = (row["episode"] as? NSNumber)?.intValue,
                      number > 0, number <= 1000 else { continue }
                let key = "\(season)-\(number)"
                guard seen.insert(key).inserted else { continue }

                let rawName = row["title"] as? String ?? ""
                let name = cleanText(rawName)
                let runtime = (row["runtime"] as? NSNumber)?.intValue
                episodes.append(MovieBoxWebEpisode(
                    season: season,
                    number: number,
                    title: name.isEmpty ? "Episode \(number)" : name,
                    thumbnailURL: httpsURL(row["thumbs"] as? String),
                    runtimeMinutes: runtime.flatMap { $0 > 0 ? $0 : nil }
                ))
            }
        }

        guard !episodes.isEmpty else { throw MovieBoxWebShowDetailError.missingDetails }
        episodes.sort { ($0.season, $0.number) < ($1.season, $1.number) }

        let synopsis = capture(synopsisPattern, from: html).map(cleanText)
        return MovieBoxWebShowDetail(
            id: id,
            title: title,
            year: capture(yearPattern, from: html),
            posterURL: httpsURL(capture(coverPattern, from: html)),
            synopsis: synopsis.flatMap { $0.isEmpty ? nil : $0 },
            seasons: seasonNumbers.sorted(),
            episodes: episodes
        )
    }

    private static func capture(_ pattern: String, from html: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    private static func httpsURL(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    private static func cleanText(_ text: String) -> String {
        text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
