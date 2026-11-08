// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import XCTest
@testable import DreamCAST

final class MovieBoxWebShowsParserTests: XCTestCase {
    func testParsesTVShowLinksTitlesAndHTTPSPosters() throws {
        let html = """
        <div class="movies">
          <a href="/tvshow/201" title="First &amp; Second">
            <div><p style="background-image:url(https://images.example.test/show.jpg),url('/default.png');"></p></div>
            <span class="update">S01 E05</span>
          </a>
          <a href="/tvshow/202" title="Another Show">
            <div><p style="background-image:url('/default.png');"></p></div>
          </a>
        </div>
        """
        let shows = try MovieBoxWebCatalogParser.shows(from: html)

        XCTAssertEqual(shows.count, 2)
        XCTAssertEqual(shows[0].id, "201")
        XCTAssertEqual(shows[0].title, "First & Second")
        XCTAssertEqual(shows[0].posterURL?.absoluteString, "https://images.example.test/show.jpg")
        XCTAssertEqual(shows[1].title, "Another Show")
        XCTAssertNil(shows[1].posterURL)
    }

    func testIgnoresDuplicatesMoviesAndInvalidShowLinks() throws {
        let html = """
        <a href="/tvshow/301" title="One Show"><div></div></a>
        <a href="/tvshow/301" title="Duplicate Show"><div></div></a>
        <a href="/movie/401" title="Not A Show"><div></div></a>
        <a href="/tvshow/not-an-id" title="Invalid"><div></div></a>
        """
        let shows = try MovieBoxWebCatalogParser.shows(from: html)

        XCTAssertEqual(shows.count, 1)
        XCTAssertEqual(shows.first?.title, "One Show")
    }

    func testRejectsMissingShows() throws {
        XCTAssertTrue(try MovieBoxWebCatalogParser.shows(from: "<p>Sign in</p>").isEmpty)
    }
}
