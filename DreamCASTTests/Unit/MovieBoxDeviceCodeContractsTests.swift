// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import XCTest
@testable import DreamCAST

final class MovieBoxDeviceCodeContractsTests: XCTestCase {
    func testChallengeRequiresCodeAndFutureExpiry() {
        let now = Date(timeIntervalSince1970: 1_000)
        let future = now.addingTimeInterval(180)

        XCTAssertNil(MovieBoxDeviceCodeChallenge(code: " ", expiresAt: future, pollInterval: 3, now: now))
        XCTAssertNil(MovieBoxDeviceCodeChallenge(code: "sample", expiresAt: now, pollInterval: 3, now: now))
        XCTAssertNil(MovieBoxDeviceCodeChallenge(code: "sample", expiresAt: future, pollInterval: 0, now: now))
        XCTAssertNil(MovieBoxDeviceCodeChallenge(code: "sample", expiresAt: future, pollInterval: .infinity, now: now))
        XCTAssertNotNil(MovieBoxDeviceCodeChallenge(code: "sample", expiresAt: future, pollInterval: 3, now: now))
    }

    func testExpiryUsesProviderDeadline() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let challenge = try XCTUnwrap(MovieBoxDeviceCodeChallenge(
            code: " sample ", expiresAt: now.addingTimeInterval(180), pollInterval: 3, now: now))

        XCTAssertEqual(challenge.code, "sample")
        XCTAssertFalse(challenge.isExpired(at: now.addingTimeInterval(179)))
        XCTAssertTrue(challenge.isExpired(at: now.addingTimeInterval(180)))
    }
}
