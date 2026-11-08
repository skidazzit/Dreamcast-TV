// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import SwiftUI

/// Owns one short-lived login attempt. The code never goes to disk or logs.
@MainActor
final class MovieBoxWebCodeLoginModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case requesting
        case awaitingApproval
        case approved
        case expired
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var code: String?
    @Published private(set) var failureMessage: String?

    private let service = MovieBoxWebCodeService()
    private var attempt: Task<Void, Never>?
    private var generation = 0

    var isBusy: Bool { phase == .requesting || phase == .awaitingApproval }

    func requestCode() {
        cancel()
        generation += 1
        let currentGeneration = generation
        phase = .requesting
        failureMessage = nil

        attempt = Task {
            do {
                let challenge = try await service.requestCode()
                try Task.checkCancellation()
                guard currentGeneration == generation else { return }
                code = challenge.code
                phase = .awaitingApproval

                while !challenge.isExpired() {
                    try await Task.sleep(for: .seconds(challenge.pollInterval))
                    try Task.checkCancellation()
                    let result = try await service.checkStatus(for: challenge)
                    try Task.checkCancellation()
                    guard currentGeneration == generation else { return }

                    if result == .approved {
                        code = nil
                        phase = .approved
                        return
                    }
                    if result == .expired { break }
                }

                if currentGeneration == generation {
                    code = nil
                    phase = .expired
                }
            } catch is CancellationError {
                // The user left the page or started a new attempt.
            } catch {
                guard currentGeneration == generation else { return }
                code = nil
                failureMessage = (error as? MovieBoxWebCodeError)?.localizedDescription
                    ?? "Could not contact MovieBox Pro. Check your network and try again."
                phase = .failed
            }
        }
    }

    func cancel() {
        generation += 1
        attempt?.cancel()
        attempt = nil
        if isBusy {
            code = nil
            phase = .idle
        }
    }
}
