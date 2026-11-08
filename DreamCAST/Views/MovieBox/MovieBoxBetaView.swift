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
            case .series: "TV shows and episodes will appear after a supported account connection is ready."
            case .search: "Search will be available after we verify the provider's request format."
            case .account: "Connect your MovieBox Pro account using a TV code."
            }
        }
    }

    @State private var page: Page = .overview
    @StateObject private var codeLogin = MovieBoxWebCodeLoginModel()
    @StateObject private var webMovies = MovieBoxWebMoviesModel()
    @FocusState private var codeButtonFocused: Bool
    @State private var selectedMovie: MovieBoxWebMovieCard?

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

                            Text("Beta: Movie listings are read-only. Playback is not enabled.")
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
                .frame(maxWidth: 1460, alignment: .leading)
                .padding(.horizontal, 90)
                .padding(.vertical, 28)
            }
        }
        .onChange(of: page) { newPage in
            if newPage != .account { codeLogin.cancel() }
            else { codeButtonFocused = true }
            if newPage == .movies { webMovies.load() }
            else { webMovies.cancel() }
        }
        .onDisappear {
            codeLogin.cancel()
            webMovies.cancel()
        }
        .alert(item: $selectedMovie) { movie in
            Alert(
                title: Text(movie.title),
                message: Text("Movie details and playback are not connected yet."),
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
                    columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: 4),
                    spacing: 28
                ) {
                    ForEach(webMovies.movies) { movie in
                        Button { selectedMovie = movie } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                AsyncImage(url: movie.posterURL) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Color.gray.opacity(0.18)
                                            .overlay(Image(systemName: "film").font(.system(size: 52)))
                                    }
                                }
                                .frame(height: 275)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .background(.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                                Text(movie.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
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
        .padding(24)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
        .focusSection()
    }
}
