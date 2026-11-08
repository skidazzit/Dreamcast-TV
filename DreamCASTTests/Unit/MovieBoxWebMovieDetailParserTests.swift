// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import XCTest
@testable import DreamCAST

final class MovieBoxWebMovieDetailParserTests: XCTestCase {
    func testReadsSafeMovieDetails() throws {
        let html = """
        <div class="info">
          <img src="https://images.example.test/movie.jpg" class="cover" />
          <p class="movie_title"><span class="name">First &amp; Second</span></p>
          <span class="year">2026</span>
          <meta itemprop="datePublished" content="2026-10-14" />
          <p style="font-size:18px;margin-top:30px;">A movie &amp; its story.</p>
        </div>
        <a play="mbpplay://example?private=NEVER_STORE_THIS">Play</a>
        """

        let result = try MovieBoxWebMovieDetailParser.detail(from: html, id: "12345")

        XCTAssertEqual(result.id, "12345")
        XCTAssertEqual(result.title, "First & Second")
        XCTAssertEqual(result.year, "2026")
        XCTAssertEqual(result.releaseDate, "October 14, 2026")
        XCTAssertEqual(result.posterURL?.absoluteString, "https://images.example.test/movie.jpg")
        XCTAssertEqual(result.synopsis, "A movie & its story.")
        XCTAssertFalse(String(describing: result).contains("NEVER_STORE_THIS"))
    }

    func testUsesPageTitleWhenVisibleTitleIsMissing() throws {
        let html = "<title>Example Movie - MovieBoxPro</title>"
        let result = try MovieBoxWebMovieDetailParser.detail(from: html, id: "42")
        XCTAssertEqual(result.title, "Example Movie")
        XCTAssertNil(result.synopsis)
    }

    func testDetectsLoginPage() throws {
        let html = "<title>Login</title><p id=\"qrcode\">00000000</p>"
        XCTAssertThrowsError(try MovieBoxWebMovieDetailParser.detail(from: html, id: "42")) { error in
            XCTAssertEqual(error as? MovieBoxWebMovieDetailError, .signInRequired)
        }
    }

    func testRejectsInvalidID() throws {
        XCTAssertThrowsError(try MovieBoxWebMovieDetailParser.detail(from: "", id: "../index"))
    }
}
