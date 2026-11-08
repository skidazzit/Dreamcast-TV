// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import Foundation

/// A read-only movie card from the website's HTML catalog page.
nonisolated struct MovieBoxWebMovieCard: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let posterURL: URL?
}

/// A read-only show card from the website's TV catalog page.
nonisolated struct MovieBoxWebShowCard: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let posterURL: URL?
}

nonisolated enum MovieBoxWebCatalogParser {
    // Both catalogs render numeric links with titles and CSS poster backgrounds.
    // This parser does not interpret any embedded scripts or account data.
    private static let moviePattern = #"<a\b([^>]*\bhref\s*=\s*["']/movie/([0-9]+)["'][^>]*)>([\s\S]*?)</a>"#
    private static let showPattern = #"<a\b([^>]*\bhref\s*=\s*["']/tvshow/([0-9]+)["'][^>]*)>([\s\S]*?)</a>"#
    private static let titlePattern = #"\btitle\s*=\s*\"([^\"]+)\""#
    private static let posterPattern = #"background-image\s*:\s*url\(\s*["']?(https://[^'"\s\)]+)"#

    static func movies(from html: String) throws -> [MovieBoxWebMovieCard] {
        try parseCards(from: html, pattern: moviePattern).map {
            MovieBoxWebMovieCard(id: $0.id, title: $0.title, posterURL: $0.posterURL)
        }
    }

    static func shows(from html: String) throws -> [MovieBoxWebShowCard] {
        try parseCards(from: html, pattern: showPattern).map {
            MovieBoxWebShowCard(id: $0.id, title: $0.title, posterURL: $0.posterURL)
        }
    }

    private struct ParsedCard {
        let id: String
        let title: String
        let posterURL: URL?
    }

    private static func parseCards(from html: String, pattern: String) throws -> [ParsedCard] {
        let cardRegex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let titleRegex = try NSRegularExpression(pattern: titlePattern, options: [.caseInsensitive])
        let posterRegex = try NSRegularExpression(pattern: posterPattern, options: [.caseInsensitive])
        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var cards: [ParsedCard] = []
        var seen: Set<String> = []

        for match in cardRegex.matches(in: html, range: fullRange).prefix(100) {
            guard let idRange = Range(match.range(at: 2), in: html),
                  let attrsRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 3), in: html) else { continue }

            let id = String(html[idRange])
            let attributes = String(html[attrsRange])
            let body = String(html[bodyRange])
            let attributesRange = NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
            guard let titleMatch = titleRegex.firstMatch(in: attributes, range: attributesRange),
                  let titleRange = Range(titleMatch.range(at: 1), in: attributes) else { continue }
            let title = decodeBasicHTMLEntities(String(attributes[titleRange]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            guard seen.insert(id).inserted else { continue }

            let bodyNSRange = NSRange(body.startIndex..<body.endIndex, in: body)
            var posterURL: URL?
            if let posterMatch = posterRegex.firstMatch(in: body, range: bodyNSRange),
               let posterRange = Range(posterMatch.range(at: 1), in: body),
               let candidate = URL(string: String(body[posterRange])),
               candidate.scheme?.lowercased() == "https" {
                posterURL = candidate
            }

            cards.append(ParsedCard(id: id, title: title, posterURL: posterURL))
        }
        return cards
    }

    private static func decodeBasicHTMLEntities(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

nonisolated enum MovieBoxWebCatalogError: LocalizedError, Sendable {
    case noSavedSession
    case noMovieCards
    case noShowCards

    var errorDescription: String? {
        switch self {
        case .noSavedSession:
            "Sign in with a TV code before loading the MovieBox catalog."
        case .noMovieCards:
            "MovieBox Pro returned no movie cards. Your session may have expired, or the site may have changed."
        case .noShowCards:
            "MovieBox Pro returned no TV show cards. Your session may have expired, or the site may have changed."
        }
    }
}
