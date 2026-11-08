// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import Combine
import SwiftUI

@MainActor
final class MovieBoxWebShowDetailModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var detail: MovieBoxWebShowDetail?
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedSeason: Int = 1

    private let service = MovieBoxWebCodeService()
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    func load(showID: String) {
        cancel()
        let currentGeneration = generation
        phase = .loading
        detail = nil
        errorMessage = nil

        loadTask = Task {
            do {
                let result = try await service.fetchShowDetail(id: showID)
                try Task.checkCancellation()
                guard currentGeneration == generation else { return }
                detail = result
                selectedSeason = result.seasons.first ?? 1
                phase = .loaded
            } catch is CancellationError {
                // The user returned to the show grid.
            } catch {
                guard currentGeneration == generation else { return }
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Could not load the show's details. Please try again."
                phase = .failed
            }
        }
    }

    func selectSeason(_ number: Int) {
        guard detail?.seasons.contains(number) == true else { return }
        selectedSeason = number
    }

    func cancel() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        if phase == .loading { phase = .idle }
    }
}
