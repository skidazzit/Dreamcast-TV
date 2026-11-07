// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  LiveTVContainerView.swift
//  DreamCAST
//
//  Container view that switches between the Guide and What's On layouts
//  based on user settings
//

import SwiftUI
import Combine

// MARK: - Live TV Layout Option

/// Raw values are what `liveTVLayout` stores, so they never change; a saved
/// "Channels" (a retired layout) falls back to the default.
enum LiveTVLayout: String, CaseIterable, CustomStringConvertible {
    case guide = "Guide"
    /// Shelves of live cards, after the Apple TV app (UIKit).
    case browse = "Browse"

    var description: String {
        switch self {
        case .guide: return String(localized: "Guide")
        case .browse: return String(localized: "What's On")
        }
    }

    /// With nothing saved, or a saved layout that no longer exists.
    static let fallback: LiveTVLayout = .browse
}

// MARK: - Live TV Container View

struct LiveTVContainerView: View {
    /// Optional source ID to filter channels. nil = show all sources.
    var sourceIdFilter: String?

    @AppStorage("liveTVLayout") private var liveTVLayoutRaw = LiveTVLayout.fallback.rawValue
    @AppStorage("liveTVAutoPlayLastWatched") private var autoPlayLastWatched = false
    @StateObject private var launchMini = LiveTVLaunchMiniRequest.shared

    private var layout: LiveTVLayout {
        LiveTVLayout(rawValue: liveTVLayoutRaw) ?? .fallback
    }

    var body: some View {
        Group {
            // Keep the same UIKit guide mounted throughout startup. Otherwise
            // Browse mounts first, then a late playlist callback swaps it for
            // Guide and resets the tvOS focus chain on the first Down press.
            switch autoPlayLastWatched || launchMini.channelID != nil ? .guide : layout {
            case .guide:
                GuideLayoutView(sourceIdFilter: sourceIdFilter, startupMiniChannelID: launchMini.channelID)
            case .browse:
                LiveBrowseBridge(sourceIdFilter: sourceIdFilter)
                    .ignoresSafeArea()
                    .id(sourceIdFilter ?? "all")
            }
        }
    }
}

/// A one-shot request from app launch. It stays set while Live TV is visible,
/// so a SwiftUI refresh never tears down the playing guide mini-player.
@MainActor
final class LiveTVLaunchMiniRequest: ObservableObject {
    static let shared = LiveTVLaunchMiniRequest()
    @Published var channelID: String?
}

/// Hosts the UIKit Browse layout. `.id` on the source rebuilds it when the
/// sidebar switches Live TV sources.
private struct LiveBrowseBridge: UIViewControllerRepresentable {
    let sourceIdFilter: String?

    func makeUIViewController(context: Context) -> LiveBrowseViewController {
        LiveBrowseViewController(sourceIdFilter: sourceIdFilter)
    }

    func updateUIViewController(_ uiViewController: LiveBrowseViewController, context: Context) {}
}

#Preview {
    LiveTVContainerView()
}
