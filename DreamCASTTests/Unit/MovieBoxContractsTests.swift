// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import XCTest
@testable import DreamCAST

final class MovieBoxContractsTests: XCTestCase {
    func testCatalogTitleRoundTripsWithoutServiceSpecificFields() throws {
        let title = MovieBoxCatalogTitle(
            id: "example-1", kind: .movie, title: "Example",
            synopsis: "Sample metadata", releaseYear: 2026,
            posterURL: URL(string: "https://example.org/poster.jpg")
        )
        let data = try JSONEncoder().encode(title)
        let restored = try JSONDecoder().decode(MovieBoxCatalogTitle.self, from: data)
        XCTAssertEqual(restored, title)
    }

    func testPlaybackLinksRequireHTTPS() {
        XCTAssertNil(MovieBoxPlaybackLink(url: URL(string: "http://example.org/movie.mp4")!, format: .progressiveMP4))
        XCTAssertNil(MovieBoxPlaybackLink(url: URL(fileURLWithPath: "/tmp/movie.mp4"), format: .progressiveMP4))
        XCTAssertNotNil(MovieBoxPlaybackLink(url: URL(string: "https://example.org/movie.m3u8")!, format: .hls))
    }
}
