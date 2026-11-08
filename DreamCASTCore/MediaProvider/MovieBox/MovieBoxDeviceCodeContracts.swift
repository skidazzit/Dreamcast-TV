// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import Foundation

/// A short-lived code returned by a verified provider, never made up locally.
/// The code must not be logged or stored on disk.
nonisolated struct MovieBoxDeviceCodeChallenge: Sendable, Equatable {
    let code: String
    let expiresAt: Date
    let pollInterval: TimeInterval

    init?(code: String, expiresAt: Date, pollInterval: TimeInterval, now: Date = Date()) {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCode.isEmpty, expiresAt > now,
              pollInterval.isFinite, pollInterval >= 1 else { return nil }
        self.code = cleanCode
        self.expiresAt = expiresAt
        self.pollInterval = pollInterval
    }

    func isExpired(at date: Date = Date()) -> Bool {
        date >= expiresAt
    }
}

nonisolated enum MovieBoxDeviceCodeStatus: Sendable, Equatable {
    case awaitingPhone
    case approved
    case expired
}

/// An adapter must use a verified account flow and secure session handling.
/// No MovieBox server endpoint or credentials are assumed here.
protocol MovieBoxDeviceCodeService: Sendable {
    func requestCode() async throws -> MovieBoxDeviceCodeChallenge
    func checkStatus(for challenge: MovieBoxDeviceCodeChallenge) async throws -> MovieBoxDeviceCodeStatus
}
