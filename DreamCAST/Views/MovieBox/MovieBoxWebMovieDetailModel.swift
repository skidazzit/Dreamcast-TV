// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import Combine
import SwiftUI

@MainActor
final class MovieBoxWebMovieDetailModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var detail: MovieBoxWebMovieDetail?
    @Published private(set) var errorMessage: String?

    private let service = MovieBoxWebCodeService()
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    func load(movieID: String) {
        cancel()
        let currentGeneration = generation
        detail = nil
        errorMessage = nil
        phase = .loading

        loadTask = Task {
            do {
                let result = try await service.fetchMovieDetail(id: movieID)
                try Task.checkCancellation()
                guard currentGeneration == generation else { return }
                detail = result
                phase = .loaded
            } catch is CancellationError {
                // The user returned to the movie grid.
            } catch {
                guard currentGeneration == generation else { return }
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Could not load movie details. Please try again."
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
