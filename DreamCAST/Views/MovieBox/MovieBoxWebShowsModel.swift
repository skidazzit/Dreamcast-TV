// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import Combine
import SwiftUI

/// Read-only show cards from the account's MovieBox web session.
@MainActor
final class MovieBoxWebShowsModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var shows: [MovieBoxWebShowCard] = []
    @Published private(set) var errorMessage: String?

    private let service = MovieBoxWebCodeService()
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    func load() {
        cancel()
        generation += 1
        let currentGeneration = generation
        phase = .loading
        shows = []
        errorMessage = nil

        loadTask = Task {
            do {
                let items = try await service.fetchShows()
                try Task.checkCancellation()
                guard currentGeneration == generation else { return }
                shows = items
                phase = .loaded
            } catch is CancellationError {
                // Moving away from TV Shows cancels this request.
            } catch {
                guard currentGeneration == generation else { return }
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Could not load MovieBox TV shows. Please try again."
                phase = .failed
            }
        }
    }

    func cancel() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        if phase == .loading { phase = .idle }
    }
}
