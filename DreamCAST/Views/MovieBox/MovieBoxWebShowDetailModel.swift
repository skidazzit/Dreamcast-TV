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
        guard let previous = detail, previous.seasons.contains(number) else { return }
        if !previous.episodes(in: number).isEmpty {
            selectedSeason = number
            return
        }

        // Fallback pages show one season at a time, so follow their season link.
        cancel()
        let currentGeneration = generation
        selectedSeason = number
        phase = .loading
        errorMessage = nil
        loadTask = Task {
            do {
                let result = try await service.fetchShowDetail(id: previous.id, season: number)
                try Task.checkCancellation()
                guard currentGeneration == generation else { return }

                let newSeasons = Set(result.episodes.map(\.season))
                let mergedEpisodes = (previous.episodes.filter { !newSeasons.contains($0.season) }
                    + result.episodes).sorted { ($0.season, $0.number) < ($1.season, $1.number) }
                detail = MovieBoxWebShowDetail(
                    id: previous.id,
                    title: result.title,
                    year: result.year ?? previous.year,
                    posterURL: result.posterURL ?? previous.posterURL,
                    synopsis: result.synopsis ?? previous.synopsis,
                    seasons: Array(Set(previous.seasons + result.seasons)).sorted(),
                    episodes: mergedEpisodes
                )
                phase = .loaded
            } catch is CancellationError {
                // The user left the show page.
            } catch {
                guard currentGeneration == generation else { return }
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Could not load this season. Please try again."
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
