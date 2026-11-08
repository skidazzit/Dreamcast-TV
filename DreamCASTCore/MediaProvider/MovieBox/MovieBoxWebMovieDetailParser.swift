// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import Foundation

/// Read-only movie fields. Playback links and account fields are ignored.
nonisolated struct MovieBoxWebMovieDetail: Sendable, Equatable {
    let id: String
    let title: String
    let year: String?
    let posterURL: URL?
    let synopsis: String?
}

nonisolated enum MovieBoxWebMovieDetailError: LocalizedError, Sendable, Equatable {
    case invalidMovieID
    case signInRequired
    case missingTitle

    var errorDescription: String? {
        switch self {
        case .invalidMovieID:
            "The movie ID was not valid."
        case .signInRequired:
            "MovieBox Pro returned a login page. Open Account and sign in again."
        case .missingTitle:
            "The movie page loaded, but its title was missing. The website layout may have changed."
        }
    }
}

/// Reads only metadata already rendered in the provider's web page.
nonisolated enum MovieBoxWebMovieDetailParser {
    private static let titlePattern = #"<p\b[^>]*class=["']movie_title["'][^>]*>[\s\S]*?<span\b[^>]*class=["']name["'][^>]*>([^<]+)</span>"#
    private static let pageTitlePattern = #"<title\b[^>]*>([^<]+)</title>"#
    private static let yearPattern = #"<span\b[^>]*class=["']year["'][^>]*>\s*([0-9]{4})\s*</span>"#
    private static let posterPattern = #"<img\b[^>]*src=["'](https://[^"']+)["'][^>]*class=["']cover["']"#
    private static let synopsisPattern = #"<p\b[^>]*style=["'][^"']*margin-top:30px[^"']*["'][^>]*>([\s\S]*?)</p>"#
    private static let metaDescriptionPattern = #"<meta\b[^>]*name=["']description["'][^>]*content=["']([^"']+)["']"#

    static func detail(from html: String, id: String) throws -> MovieBoxWebMovieDetail {
        guard !id.isEmpty, id.count <= 20, id.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            throw MovieBoxWebMovieDetailError.invalidMovieID
        }
        if html.contains("id=\"qrcode\"") || html.contains("LOGIN TO ACCESS") {
            throw MovieBoxWebMovieDetailError.signInRequired
        }

        let rawTitle = capture(titlePattern, in: html)
            ?? capture(pageTitlePattern, in: html)?.replacingOccurrences(of: " - MovieBoxPro", with: "")
        guard let rawTitle else { throw MovieBoxWebMovieDetailError.missingTitle }
        let title = cleanText(rawTitle)
        guard !title.isEmpty else { throw MovieBoxWebMovieDetailError.missingTitle }

        let synopsis = capture(synopsisPattern, in: html)
            ?? capture(metaDescriptionPattern, in: html)
        let description = synopsis.map(cleanText).flatMap { $0.isEmpty ? nil : $0 }

        return MovieBoxWebMovieDetail(
            id: id,
            title: title,
            year: capture(yearPattern, in: html),
            posterURL: httpsURL(capture(posterPattern, in: html)),
            synopsis: description
        )
    }

    private static func capture(_ pattern: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    private static func httpsURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    private static func cleanText(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
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
