// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import XCTest
@testable import DreamCAST

final class MovieBoxWebShowDetailParserTests: XCTestCase {
    func testReadsSeasonsEpisodesAndSafeDisplayFields() throws {
        let html = """
        <div class="info">
          <img src="https://images.example.test/show-cover.jpg" class="cover" />
          <p class="movie_title"><span class="name">Sample &amp; Show</span></p>
          <span class="year">2026</span>
          <p style="font-size:18px;margin-top:30px;">A short &amp; safe summary.</p>
        </div>
        <a play="mbpplay://example?private=NEVER_STORE_THIS"></a>
        <script>
        var tv_season_list = [
          {"season":1,"episode_list":[
            {"season":1,"episode":1,"title":"Pilot","runtime":42,
             "thumbs":"https://images.example.test/ep1.jpg","over":1,"seconds":200},
            {"season":1,"episode":2,"title":"","runtime":0,"thumbs":"http://not-secure.test/ep2.jpg"}
          ]},
          {"season":2,"episode_list":[
            {"season":2,"episode":1,"title":"New Start","runtime":47,
             "thumbs":"https://images.example.test/season2.jpg"}
          ]}
        ];
        </script>
        """

        let detail = try MovieBoxWebShowDetailParser.detail(from: html, id: "12345")

        XCTAssertEqual(detail.id, "12345")
        XCTAssertEqual(detail.title, "Sample & Show")
        XCTAssertEqual(detail.year, "2026")
        XCTAssertEqual(detail.posterURL?.absoluteString, "https://images.example.test/show-cover.jpg")
        XCTAssertEqual(detail.synopsis, "A short & safe summary.")
        XCTAssertEqual(detail.seasons, [1, 2])
        XCTAssertEqual(detail.episodes(in: 1).count, 2)
        XCTAssertEqual(detail.episodes(in: 2).count, 1)
        XCTAssertEqual(detail.episodes(in: 1)[0].title, "Pilot")
        XCTAssertEqual(detail.episodes(in: 1)[0].runtimeMinutes, 42)
        XCTAssertEqual(detail.episodes(in: 1)[1].title, "Episode 2")
        XCTAssertNil(detail.episodes(in: 1)[1].thumbnailURL)
        XCTAssertFalse(String(describing: detail).contains("NEVER_STORE_THIS"))
    }

    func testFailsClosedWhenSeasonDataIsMissing() throws {
        let html = "<p class=\"movie_title\"><span class=\"name\">Show</span></p>"
        XCTAssertThrowsError(try MovieBoxWebShowDetailParser.detail(from: html, id: "12345"))
    }

    func testReadsRenderedEpisodesWhenEmbeddedSeasonJSONIsMissing() throws {
        let html = """
        <title>Sample Show - MovieBoxPro</title>
        <div class="tv_episode">
          <a href="javascript:;" season="1" episode="1" play="private-value" class="start_app_episode watch_tab">
            <p class="chapter_img" style='background-image:url("https://images.example.test/ep1.jpg")'></p>
          </a>
          <a href="javascript:;" season="1" episode="1" class="start_app_episode">
            <p>Opening Episode</p>
          </a>
          <p>October 2026 | 43 minutes</p>
        </div>
        <a href="/tvshow/12345?season=1">Season 1</a>
        <a href="/tvshow/12345?season=2">Season 2</a>
        """
        let detail = try MovieBoxWebShowDetailParser.detail(from: html, id: "12345")

        XCTAssertEqual(detail.title, "Sample Show")
        XCTAssertEqual(detail.seasons, [1, 2])
        XCTAssertEqual(detail.episodes.count, 1)
        XCTAssertEqual(detail.episodes[0].title, "Opening Episode")
        XCTAssertEqual(detail.episodes[0].runtimeMinutes, 43)
        XCTAssertEqual(detail.episodes[0].thumbnailURL?.absoluteString, "https://images.example.test/ep1.jpg")
        XCTAssertFalse(String(describing: detail).contains("private-value"))
    }

    func testDetectsLoginPage() throws {
        let html = "<title>Login</title><p id=\"qrcode\">00000000</p>"
        XCTAssertThrowsError(try MovieBoxWebShowDetailParser.detail(from: html, id: "12345")) { error in
            XCTAssertEqual(error as? MovieBoxWebShowDetailError, .signInRequired)
        }
    }

    func testRejectsInvalidShowID() throws {
        XCTAssertThrowsError(try MovieBoxWebShowDetailParser.detail(from: "", id: "../../other"))
    }
}
