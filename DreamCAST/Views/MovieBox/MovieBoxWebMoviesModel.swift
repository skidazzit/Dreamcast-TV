// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import Combine
import SwiftUI

/// Read-only movie cards from the account's MovieBox web session.
@MainActor
final class MovieBoxWebMoviesModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var movies: [MovieBoxWebMovieCard] = []
    @Published private(set) var errorMessage: String?

    private let service = MovieBoxWebCodeService()
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    func load() {
        cancel()
        generation += 1
        let currentGeneration = generation
        phase = .loading
        movies = []
        errorMessage = nil

        loadTask = Task {
            do {
                let items = try await service.fetchMovies()
                try Task.checkCancellation()
                guard currentGeneration == generation else { return }
                movies = items
                phase = .loaded
            } catch is CancellationError {
                // Moving away from Movies cancels this request.
            } catch {
                guard currentGeneration == generation else { return }
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Could not load MovieBox movies. Please try again."
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
