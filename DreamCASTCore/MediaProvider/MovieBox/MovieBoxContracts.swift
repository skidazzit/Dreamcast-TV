// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import Foundation

// The app-facing shapes for a future MovieBox Pro provider. These are NOT the
// service's wire formats: the 16.5 iOS binary exposes operation names but does
// not establish a supported request or authentication contract.

nonisolated enum MovieBoxTitleKind: String, Codable, Hashable, Sendable {
    case movie
    case series
    case episode
}

nonisolated struct MovieBoxCatalogTitle: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let kind: MovieBoxTitleKind
    let title: String
    let synopsis: String?
    let releaseYear: Int?
    let posterURL: URL?
}

nonisolated struct MovieBoxEpisode: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let seriesID: String
    let seasonNumber: Int
    let episodeNumber: Int
    let title: String
    let synopsis: String?
}

nonisolated enum MovieBoxStreamFormat: String, Codable, Hashable, Sendable {
    case hls
    case progressiveMP4
    case mpegDash
    case unknown
}

/// A playback link granted by the service for the current account. No code
/// constructs one from hidden CDN paths or changes subscription entitlements.
nonisolated struct MovieBoxPlaybackLink: Hashable, Sendable {
    let url: URL
    let format: MovieBoxStreamFormat
    let expiresAt: Date?

    init?(url: URL, format: MovieBoxStreamFormat, expiresAt: Date? = nil) {
        guard url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        self.url = url
        self.format = format
        self.expiresAt = expiresAt
    }
}

/// App-facing seam only. A live adapter must use an approved account flow and
/// a verified server contract. None is assumed by this protocol.
protocol MovieBoxCatalogService: Sendable {
    func search(_ query: String, page: Int) async throws -> [MovieBoxCatalogTitle]
    func title(id: String) async throws -> MovieBoxCatalogTitle
    func episodes(seriesID: String) async throws -> [MovieBoxEpisode]
    func permittedPlaybackLinks(titleID: String, episodeID: String?) async throws -> [MovieBoxPlaybackLink]
}
