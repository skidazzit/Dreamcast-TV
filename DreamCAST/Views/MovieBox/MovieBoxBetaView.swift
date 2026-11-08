// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import SwiftUI

/// Beta entry point. Code Login is isolated from Plex and the media catalog.
struct MovieBoxBetaView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case movies = "Movies"
        case series = "TV Shows"
        case search = "Search"
        case account = "Account"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .overview: "house"
            case .movies: "film"
            case .series: "tv"
            case .search: "magnifyingglass"
            case .account: "person.crop.circle"
            }
        }

        var detail: String {
            switch self {
            case .overview: "MovieBox Pro is not connected to DreamCAST yet."
            case .movies: "Read-only listings from your saved MovieBox web session."
            case .series: "Read-only shows from your saved MovieBox web session."
            case .search: "Search will be available after we verify the provider's request format."
            case .account: "Connect your MovieBox Pro account using a TV code."
            }
        }
    }

    @State private var page: Page = .overview
    @StateObject private var codeLogin = MovieBoxWebCodeLoginModel()
    @StateObject private var webMovies = MovieBoxWebMoviesModel()
    @StateObject private var webShows = MovieBoxWebShowsModel()
    @StateObject private var webShowDetail = MovieBoxWebShowDetailModel()
    @FocusState private var codeButtonFocused: Bool
    @State private var selectedCatalogItem: CatalogSelection?
    @State private var activeShow: MovieBoxWebShowCard?

    private struct CatalogSelection: Identifiable {
        let id: String
        let title: String
        let message: String
    }

    /// Use the same six-column poster geometry as the Plex shelves.
    private var catalogColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(MediaRowMetrics.poster.art.width), spacing: MediaRowMetrics.tileGap),
            count: MediaRowMetrics.posterFullCount
        )
    }

    private var episodeColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(MediaRowMetrics.gridWidth(columns: 4)), spacing: MediaRowMetrics.tileGap),
            count: 4
        )
    }

    var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.06, blue: 0.09)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 18) {
                        Image(systemName: "play.tv.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.cyan)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("MovieBox Pro")
                                .font(.largeTitle.bold())
                            Text("DreamCAST beta")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 14) {
                        ForEach(Page.allCases) { item in
                            Button {
                                page = item
                            } label: {
                                Label(item.rawValue, systemImage: item.symbol)
                                    .font(.headline)
                                    .frame(minWidth: 130, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .tint(page == item ? .cyan : .gray)
                        }
                    }

                    if page == .movies {
                        movieCatalog
                    } else if page == .series {
                        if let activeShow {
                            showDetailView(for: activeShow)
                        } else {
                            showCatalog
                        }
                    } else if page != .account {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(page.rawValue)
                                .font(.title.bold())
                            Text(page.detail)
                                .font(.title3)
                                .foregroundStyle(.secondary)

                            Label("Account status: Not connected", systemImage: "person.crop.circle.badge.exclamationmark")
                                .font(.headline)
                                .foregroundStyle(.yellow)
                                .padding(.top, 6)
                        }
                        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
                        .padding(24)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
                    }

                    if page == .account {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 20) {
                                Label("Code Login", systemImage: "number.square")
                                    .font(.title2.bold())
                                    .foregroundStyle(.cyan)

                                Spacer(minLength: 20)

                                Button(codeLogin.isBusy ? "Cancel" :
                                       (codeLogin.phase == .expired || codeLogin.phase == .approved || codeLogin.hasSavedSession)
                                        ? "Get new code" : "Get TV code") {
                                    if codeLogin.isBusy {
                                        codeLogin.cancel()
                                    } else {
                                        codeLogin.requestCode()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.cyan)
                                .focused($codeButtonFocused)
                                .disabled(codeLogin.isClearingSession)

                                if codeLogin.hasSavedSession {
                                    Button("Forget session") {
                                        codeLogin.forgetSavedSession()
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(codeLogin.isClearingSession)
                                }
                            }

                            Label(codeLogin.hasSavedSession
                                  ? "Account status: Web session saved (not verified)"
                                  : codeLogin.phase == .approved
                                    ? "Account status: Code approved (no session saved)"
                                    : "Account status: Not connected",
                                  systemImage: codeLogin.hasSavedSession || codeLogin.phase == .approved
                                    ? "checkmark.circle.fill" : "person.crop.circle.badge.exclamationmark")
                                .font(.headline)
                                .foregroundStyle(codeLogin.hasSavedSession ? Color.green : Color.yellow)

                            Text("Get a TV code, then approve it through MovieBox Pro on your phone.")
                                .font(.body)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Your Apple TV code")
                                    .font(.headline)

                                HStack(spacing: 16) {
                                    Image(systemName: codeLogin.phase == .approved || codeLogin.hasSavedSession
                                          ? "checkmark.shield.fill" : "lock.shield")
                                        .foregroundStyle(codeLogin.hasSavedSession ? Color.green : Color.cyan)
                                    if let code = codeLogin.code {
                                        Text(code)
                                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                                    } else {
                                        Text(codeLogin.hasSavedSession ? "Session saved" :
                                             codeLogin.phase == .approved ? "Approved" :
                                             codeLogin.phase == .expired ? "Expired" : "Not issued")
                                            .font(.title2.bold())
                                    }
                                }

                                switch codeLogin.phase {
                                case .requesting:
                                    ProgressView("Requesting TV code…")
                                case .awaitingApproval:
                                    ProgressView("Waiting for approval (up to 2 minutes)…")
                                case .approved:
                                    Text("Code approved, but the website did not return a usable session.")
                                        .foregroundStyle(.orange)
                                case .sessionSaved:
                                    Label("Session saved on this Apple TV. Account access is not verified yet.", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                case .expired:
                                    Text("This code expired. Request a new one to try again.")
                                        .foregroundStyle(.orange)
                                case .failed:
                                    Text(codeLogin.failureMessage ?? "Code login failed. Please try again.")
                                        .foregroundStyle(.orange)
                                case .idle:
                                    EmptyView()
                                }
                            }
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))

                            Text("On your phone: MovieBox Pro → Code Login → Enter this code → Confirm.")
                                .font(.body)

                            Text("Beta: Movies and TV shows are read-only. Playback is not enabled.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
                        .focusSection()
                    }

                    Text("MovieBox web pairing is experimental. No MovieBox streaming is active.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: page == .movies || page == .series ? 1920 : 1460, alignment: .leading)
                .padding(.horizontal, page == .movies || page == .series ? MediaRowMetrics.rowLeading : 90)
                .padding(.vertical, 28)
            }
            .id("\(page.rawValue)-\(activeShow?.id ?? "grid")")
        }
        .onChange(of: page) { newPage in
            if newPage != .account { codeLogin.cancel() }
            else { codeButtonFocused = true }
            if newPage == .movies { webMovies.load() }
            else { webMovies.cancel() }
            if newPage == .series { webShows.load() }
            else {
                webShows.cancel()
                webShowDetail.cancel()
                activeShow = nil
            }
        }
        .onDisappear {
            codeLogin.cancel()
            webMovies.cancel()
            webShows.cancel()
            webShowDetail.cancel()
        }
        .alert(item: $selectedCatalogItem) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var movieCatalog: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 24) {
                Text("Movies")
                    .font(.title.bold())
                Spacer()
                Button("Refresh") { webMovies.load() }
                    .buttonStyle(.bordered)
            }

            Text("Read-only movie listings from your MovieBox Pro web session.")
                .font(.body)
                .foregroundStyle(.secondary)

            if webMovies.phase == .loading {
                ProgressView("Loading movies…")
            } else if webMovies.phase == .failed {
                Text(webMovies.errorMessage ?? "Could not load movies.")
                    .foregroundStyle(.orange)
            } else if webMovies.phase == .loaded {
                Text("\(webMovies.movies.count) movies found")
                    .font(.headline)
                    .foregroundStyle(.cyan)
            }

            if !webMovies.movies.isEmpty {
                LazyVGrid(
                    columns: catalogColumns,
                    alignment: .leading,
                    spacing: 32
                ) {
                    ForEach(webMovies.movies) { movie in
                        Button {
                            selectedCatalogItem = CatalogSelection(
                                id: "movie-\(movie.id)",
                                title: movie.title,
                                message: "Movie details and playback are not connected yet."
                            )
                        } label: {
                            catalogPoster(title: movie.title, posterURL: movie.posterURL, symbol: "film")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Beta: Listings only. Playback and account rights are not verified yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
        .focusSection()
    }

    private var showCatalog: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 24) {
                Text("TV Shows")
                    .font(.title.bold())
                Spacer()
                Button("Refresh") { webShows.load() }
                    .buttonStyle(.bordered)
            }

            Text("Read-only TV show listings from your MovieBox Pro web session.")
                .font(.body)
                .foregroundStyle(.secondary)

            if webShows.phase == .loading {
                ProgressView("Loading TV shows…")
            } else if webShows.phase == .failed {
                Text(webShows.errorMessage ?? "Could not load TV shows.")
                    .foregroundStyle(.orange)
            } else if webShows.phase == .loaded {
                Text("\(webShows.shows.count) TV shows found")
                    .font(.headline)
                    .foregroundStyle(.cyan)
            }

            if !webShows.shows.isEmpty {
                LazyVGrid(
                    columns: catalogColumns,
                    alignment: .leading,
                    spacing: 32
                ) {
                    ForEach(webShows.shows) { show in
                        Button {
                            activeShow = show
                            webShowDetail.load(showID: show.id)
                        } label: {
                            catalogPoster(title: show.title, posterURL: show.posterURL, symbol: "tv")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Select a show to browse its seasons and episodes. Playback is not enabled.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
        .focusSection()
    }

    private func showDetailView(for show: MovieBoxWebShowCard) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 20) {
                Button {
                    webShowDetail.cancel()
                    activeShow = nil
                } label: {
                    Label("Back to TV Shows", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Refresh") { webShowDetail.load(showID: show.id) }
                    .buttonStyle(.bordered)
            }

            if webShowDetail.phase == .loading {
                ProgressView("Loading show details…")
            } else if webShowDetail.phase == .failed {
                Text(webShowDetail.errorMessage ?? "Could not load this show.")
                    .foregroundStyle(.orange)
            }

            if let detail = webShowDetail.detail {
                HStack(alignment: .top, spacing: 36) {
                    AsyncImage(url: detail.posterURL ?? show.posterURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.gray.opacity(0.18)
                                .overlay(Image(systemName: "tv").font(.system(size: 52)))
                        }
                    }
                    .frame(width: MediaRowMetrics.poster.art.width, height: MediaRowMetrics.poster.art.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 18) {
                        Text(detail.title)
                            .font(.largeTitle.bold())
                        if let year = detail.year {
                            Text(year)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        if let synopsis = detail.synopsis {
                            Text(synopsis)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Read-only show details. No playback is available in this beta.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 20) {
                    Text("Seasons")
                        .font(.title2.bold())

                    HStack(spacing: 16) {
                        ForEach(detail.seasons, id: \.self) { season in
                            Button("Season \(season)") {
                                webShowDetail.selectSeason(season)
                            }
                            .buttonStyle(.bordered)
                            .tint(webShowDetail.selectedSeason == season ? .cyan : .gray)
                        }
                    }

                    let episodes = detail.episodes(in: webShowDetail.selectedSeason)
                    Text("\(episodes.count) episodes")
                        .font(.headline)
                        .foregroundStyle(.cyan)

                    LazyVGrid(columns: episodeColumns, alignment: .leading, spacing: 32) {
                        ForEach(episodes) { episode in
                            Button {
                                let runtime = episode.runtimeMinutes.map { " · \($0) minutes" } ?? ""
                                selectedCatalogItem = CatalogSelection(
                                    id: "episode-\(detail.id)-\(episode.id)",
                                    title: episode.title,
                                    message: "Season \(episode.season), Episode \(episode.number)\(runtime). Playback is not enabled yet."
                                )
                            } label: {
                                episodeCard(episode)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
        .focusSection()
    }

    private func episodeCard(_ episode: MovieBoxWebEpisode) -> some View {
        let width = MediaRowMetrics.gridWidth(columns: 4)
        return VStack(alignment: .leading, spacing: 10) {
            AsyncImage(url: episode.thumbnailURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.18)
                        .overlay(Image(systemName: "tv").font(.system(size: 46)))
                }
            }
            .frame(width: width, height: width * 9 / 16)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("S\(episode.season)E\(episode.number) · \(episode.title)")
                .font(.headline)
                .lineLimit(2)
                .frame(width: width, alignment: .leading)
            if let runtime = episode.runtimeMinutes {
                Text("\(runtime) minutes")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func catalogPoster(title: String, posterURL: URL?, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AsyncImage(url: posterURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.18)
                        .overlay(Image(systemName: symbol).font(.system(size: 52)))
                }
            }
            .frame(width: MediaRowMetrics.poster.art.width, height: MediaRowMetrics.poster.art.height)
            .clipped()
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(title)
                .font(.headline)
                .lineLimit(2)
                .frame(width: MediaRowMetrics.poster.art.width, alignment: .leading)
        }
    }
}
