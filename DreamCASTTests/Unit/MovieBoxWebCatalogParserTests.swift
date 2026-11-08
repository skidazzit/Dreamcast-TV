// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import XCTest
@testable import DreamCAST

final class MovieBoxWebCatalogParserTests: XCTestCase {
    func testParsesMovieLinksTitlesAndHTTPSPosters() throws {
        let html = """
        <div class="movies">
          <a href="/movie/101" title="First &amp; Second">
            <div><p style="background-image:url(https://images.example.test/poster.jpg),url('/default.png');"></p></div>
          </a>
          <a href="/movie/102" title="Another Film">
            <div><p style="background-image:url('/default.png');"></p></div>
          </a>
        </div>
        """
        let movies = try MovieBoxWebCatalogParser.movies(from: html)

        XCTAssertEqual(movies.count, 2)
        XCTAssertEqual(movies[0].id, "101")
        XCTAssertEqual(movies[0].title, "First & Second")
        XCTAssertEqual(movies[0].posterURL?.absoluteString, "https://images.example.test/poster.jpg")
        XCTAssertEqual(movies[1].title, "Another Film")
        XCTAssertNil(movies[1].posterURL)
    }

    func testIgnoresDuplicateAndNonMovieLinks() throws {
        let html = """
        <a href="/movie/123" title="A Film"><div></div></a>
        <a href="/movie/123" title="Repeated Film"><div></div></a>
        <a href="/tvshow/321" title="Not A Film"><div></div></a>
        <a href="/movie/not-an-id" title="Invalid"><div></div></a>
        """
        let movies = try MovieBoxWebCatalogParser.movies(from: html)

        XCTAssertEqual(movies.count, 1)
        XCTAssertEqual(movies.first?.title, "A Film")
    }

    func testRejectsMissingCards() throws {
        XCTAssertTrue(try MovieBoxWebCatalogParser.movies(from: "<p>Sign in</p>").isEmpty)
    }
}
