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
            case .movies: "Movie listings will appear after a supported account connection is ready."
            case .series: "TV shows and episodes will appear after a supported account connection is ready."
            case .search: "Search will be available after we verify the provider's request format."
            case .account: "Connect your MovieBox Pro account using a TV code."
            }
        }
    }

    @State private var page: Page = .overview
    @StateObject private var codeLogin = MovieBoxWebCodeLoginModel()
    @FocusState private var codeButtonFocused: Bool

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

                    if page != .account {
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
                                       (codeLogin.phase == .expired || codeLogin.phase == .approved)
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
                            }

                            Label(codeLogin.phase == .approved
                                  ? "Account status: Code approved (beta)"
                                  : "Account status: Not connected",
                                  systemImage: codeLogin.phase == .approved
                                    ? "checkmark.circle.fill" : "person.crop.circle.badge.exclamationmark")
                                .font(.headline)
                                .foregroundStyle(codeLogin.phase == .approved ? Color.green : Color.yellow)

                            Text("Get a TV code, then approve it through MovieBox Pro on your phone.")
                                .font(.body)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Your Apple TV code")
                                    .font(.headline)

                                HStack(spacing: 16) {
                                    Image(systemName: codeLogin.phase == .approved
                                          ? "checkmark.shield.fill" : "lock.shield")
                                        .foregroundStyle(codeLogin.phase == .approved ? Color.green : Color.cyan)
                                    if let code = codeLogin.code {
                                        Text(code)
                                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                                    } else {
                                        Text(codeLogin.phase == .approved ? "Approved" :
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
                                    Label("Code approved. Account browsing is not connected yet.", systemImage: "checkmark.circle.fill")
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

                            Text("Beta: Approval does not yet enable the MovieBox catalog or playback.")
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
        }
        .onDisappear { codeLogin.cancel() }
    }
}
