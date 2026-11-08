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
    let firstAirDate: String?
    let posterURL: URL?
    let synopsis: String?
    let seasons: [Int]
    let episodes: [MovieBoxWebEpisode]

    func episodes(in season: Int) -> [MovieBoxWebEpisode] {
        episodes.filter { $0.season == season }
    }
}

nonisolated enum MovieBoxWebShowDetailError: LocalizedError, Sendable, Equatable {
    case invalidShowID
    case signInRequired
    case missingTitle
    case missingEpisodeData

    var errorDescription: String? {
        switch self {
        case .invalidShowID:
            "The TV show ID was not valid."
        case .signInRequired:
            "MovieBox Pro returned a login page. Open Account and sign in again."
        case .missingTitle:
            "The show page loaded, but its title was missing. The website layout may have changed."
        case .missingEpisodeData:
            "The show page loaded, but no episodes were found. The website may use another format."
        }
    }
}

/// Parses the browser's show page without evaluating scripts or reading play links.
nonisolated enum MovieBoxWebShowDetailParser {
    private static let titlePattern = #"<p\b[^>]*class=["']movie_title["'][^>]*>[\s\S]*?<span\b[^>]*class=["']name["'][^>]*>([^<]+)</span>"#
    private static let pageTitlePattern = #"<title\b[^>]*>([^<]+)</title>"#
    private static let yearPattern = #"<span\b[^>]*class=["']year["'][^>]*>\s*([0-9]{4})\s*</span>"#
    private static let coverPattern = #"<img\b[^>]*src=["'](https://[^"']+)["'][^>]*class=["']cover["']"#
    private static let synopsisPattern = #"<p\b[^>]*style=["'][^"']*margin-top:30px[^"']*["'][^>]*>([\s\S]*?)</p>"#
    private static let seasonDataPattern = #"\bvar\s+tv_season_list\s*=\s*(\[[\s\S]*?\]);"#
    private static let episodeBlockPattern = #"<div\b[^>]*class=["']tv_episode["'][^>]*>"#
    private static let episodeNumberPattern = #"\bseason=["']([0-9]+)["']\s+episode=["']([0-9]+)["']"#
    private static let episodeTitlePattern = #"<a\b[^>]*class=["'][^"']*start_app_episode[^"']*["'][^>]*>\s*<p\b[^>]*>([^<]+)</p>"#
    private static let episodeThumbnailPattern = #"\bclass=["']chapter_img["'][^>]*?(https://[^"'\s,\)]+)"#
    private static let episodeRuntimePattern = #"\|\s*([0-9]{1,3})\s+minutes"#
    private static let seasonLinkPattern = #"/tvshow/[0-9]+\?season=([0-9]+)"#

    static func detail(from html: String, id: String) throws -> MovieBoxWebShowDetail {
        guard !id.isEmpty, id.count <= 20, id.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            throw MovieBoxWebShowDetailError.invalidShowID
        }
        if html.contains("id=\"qrcode\"") || html.contains("LOGIN TO ACCESS") {
            throw MovieBoxWebShowDetailError.signInRequired
        }
        let rawTitle = capture(titlePattern, from: html)
            ?? capture(pageTitlePattern, from: html)?.replacingOccurrences(of: " - MovieBoxPro", with: "")
        guard let rawTitle else { throw MovieBoxWebShowDetailError.missingTitle }
        let title = cleanText(rawTitle)
        guard !title.isEmpty else { throw MovieBoxWebShowDetailError.missingTitle }

        // This JSON is embedded in the HTML used by the website's season picker.
        // Only the safe display keys are read. Watch progress and play tokens are ignored.
        var seasonNumbers: Set<Int> = []
        var episodes: [MovieBoxWebEpisode] = []
        var seen: Set<String> = []

        if let seasonJSON = capture(seasonDataPattern, from: html),
           let data = seasonJSON.data(using: .utf8),
           let seasonRows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
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
        }

        // Some pages render episode cards but omit the embedded JSON.
        if episodes.isEmpty {
            episodes = parseHTMLCards(from: html)
            seasonNumbers.formUnion(episodes.map(\.season))
            seasonNumbers.formUnion(seasonLinks(from: html))
        }

        guard !episodes.isEmpty else { throw MovieBoxWebShowDetailError.missingEpisodeData }
        episodes.sort { ($0.season, $0.number) < ($1.season, $1.number) }

        let synopsis = capture(synopsisPattern, from: html).map(cleanText)
        return MovieBoxWebShowDetail(
            id: id,
            title: title,
            year: capture(yearPattern, from: html),
            firstAirDate: fullDate(in: html),
            posterURL: httpsURL(capture(coverPattern, from: html)),
            synopsis: synopsis.flatMap { $0.isEmpty ? nil : $0 },
            seasons: seasonNumbers.sorted(),
            episodes: episodes
        )
    }

    private static func parseHTMLCards(from html: String) -> [MovieBoxWebEpisode] {
        guard let blockRegex = try? NSRegularExpression(pattern: episodeBlockPattern, options: [.caseInsensitive]),
              let numberRegex = try? NSRegularExpression(pattern: episodeNumberPattern, options: [.caseInsensitive]) else {
            return []
        }
        let full = NSRange(html.startIndex..<html.endIndex, in: html)
        let starts = blockRegex.matches(in: html, range: full)
        var episodes: [MovieBoxWebEpisode] = []
        var seen: Set<String> = []

        for (index, match) in starts.enumerated() {
            let start = match.range.location
            let end = index + 1 < starts.count ? starts[index + 1].range.location : full.length
            guard let range = Range(NSRange(location: start, length: end - start), in: html) else { continue }
            let block = String(html[range])
            let blockRange = NSRange(block.startIndex..<block.endIndex, in: block)
            guard let numbers = numberRegex.firstMatch(in: block, range: blockRange),
                  let seasonRange = Range(numbers.range(at: 1), in: block),
                  let numberRange = Range(numbers.range(at: 2), in: block),
                  let season = Int(block[seasonRange]), let number = Int(block[numberRange]),
                  season >= 0, season <= 100, number > 0, number <= 1000 else { continue }
            let key = "\(season)-\(number)"
            guard seen.insert(key).inserted else { continue }

            let name = cleanText(capture(episodeTitlePattern, from: block) ?? "")
            let minutes = capture(episodeRuntimePattern, from: block).flatMap { Int($0) }
            episodes.append(MovieBoxWebEpisode(
                season: season,
                number: number,
                title: name.isEmpty ? "Episode \(number)" : name,
                thumbnailURL: httpsURL(capture(episodeThumbnailPattern, from: block)),
                runtimeMinutes: minutes
            ))
        }
        return episodes
    }

    private static func seasonLinks(from html: String) -> Set<Int> {
        guard let regex = try? NSRegularExpression(pattern: seasonLinkPattern) else { return [] }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html))
        return Set(matches.compactMap { match in
            Range(match.range(at: 1), in: html).flatMap { Int(html[$0]) }
        }.filter { $0 >= 0 && $0 <= 100 })
    }

    private static let structuredDatePattern = #"(?i)(?:["'](?:released|release_date|first_air_date|air_date|datePublished)["']\s*[:=]\s*["']|\b(?:datePublished|releaseDate|firstAirDate)\s*=\s*["'])([0-9]{4}-[0-9]{2}-[0-9]{2})"#
    private static let metaDatePattern = #"<meta\b[^>]*(?:itemprop|property|name)=["'](?:datePublished|release_date|first_air_date|air_date)["'][^>]*content=["']([0-9]{4}-[0-9]{2}-[0-9]{2})["']"#
    private static let labeledDatePattern = #"(?i)(?:Release(?:d)?(?:\s+Date)?|First\s+Air(?:ed)?(?:\s+Date)?|Air\s+Date)\s*:?\s*(?:</[^>]+>\s*)?([0-9]{4}-[0-9]{2}-[0-9]{2})"#

    private static func fullDate(in html: String) -> String? {
        let candidate = capture(metaDatePattern, from: html)
            ?? capture(structuredDatePattern, from: html)
            ?? capture(labeledDatePattern, from: html)
        guard let candidate else { return nil }
        let parts = candidate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = components.date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
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
