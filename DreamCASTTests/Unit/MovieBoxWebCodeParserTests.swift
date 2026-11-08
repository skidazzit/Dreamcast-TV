// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import XCTest
@testable import DreamCAST

final class MovieBoxWebCodeParserTests: XCTestCase {
    func testServerRenderedCodeGetsTwoMinuteExpiry() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let html = #"<p class="code" id="qrcode">24681357</p>"#
        let challenge = try MovieBoxWebCodeParser.challenge(from: html, now: now)

        XCTAssertEqual(challenge.code, "24681357")
        XCTAssertEqual(challenge.expiresAt, now.addingTimeInterval(120))
        XCTAssertEqual(challenge.pollInterval, 1.5)
    }

    func testRejectsMissingOrInvalidCode() {
        XCTAssertThrowsError(try MovieBoxWebCodeParser.challenge(from: "<p>Sign in</p>"))
        XCTAssertThrowsError(try MovieBoxWebCodeParser.challenge(from: #"<p id="qrcode">not-a-code</p>"#))
    }

    func testPollResponseWaitsForApproval() throws {
        let pending = try MovieBoxWebCodeParser.status(from: Data(#"{"code":0}"#.utf8))
        let approved = try MovieBoxWebCodeParser.status(from: Data(#"{"code":1,"ui":"private"}"#.utf8))
        let stringApproved = try MovieBoxWebCodeParser.status(from: Data(#"{"code":"1"}"#.utf8))

        XCTAssertEqual(pending, .awaitingPhone)
        XCTAssertEqual(approved, .approved)
        XCTAssertEqual(stringApproved, .approved)
        XCTAssertThrowsError(try MovieBoxWebCodeParser.status(from: Data(#"{"unknown":1}"#.utf8)))
    }
}
