// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import XCTest
@testable import DreamCAST

final class MovieBoxLegacyTitleMapperTests: XCTestCase {
    func testNumericMovieIDAndArtwork() throws {
        let data = Data(#"{"mid":321,"title":"Example Film","synopsis":"Test plot","released":"2026-10-14","thumbs_min":"https://example.org/film.jpg"}"#.utf8)
        let title = try MovieBoxLegacyTitleMapper.decode(data, kind: .movie)
        XCTAssertEqual(title.id, "321")
        XCTAssertEqual(title.title, "Example Film")
        XCTAssertEqual(title.releaseYear, 2026)
        XCTAssertEqual(title.posterURL?.absoluteString, "https://example.org/film.jpg")
    }

    func testStringSeriesIDAndInsecurePosterRejection() throws {
        let data = Data(#"{"tid":"series-42","title":" Example Show ","released":2025,"poster":"http://example.org/show.jpg"}"#.utf8)
        let title = try MovieBoxLegacyTitleMapper.decode(data, kind: .series)
        XCTAssertEqual(title.id, "series-42")
        XCTAssertEqual(title.title, "Example Show")
        XCTAssertEqual(title.releaseYear, 2025)
        XCTAssertNil(title.posterURL)
    }

    func testMissingIdentifierIsNotInvented() {
        let data = Data(#"{"title":"Unknown"}"#.utf8)
        XCTAssertThrowsError(try MovieBoxLegacyTitleMapper.decode(data, kind: .movie)) { error in
            XCTAssertEqual(
                error as? MovieBoxLegacyTitleMappingError,
                MovieBoxLegacyTitleMappingError.missingIdentifier
            )
        }
    }
}
