// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  GuideCategoryTabsTests.swift
//  DreamCASTTests
//
//  The Guide's category tabs: Favorites, sources in order, then groups (#377).
//

import XCTest
@testable import DreamCAST

final class GuideCategoryTabsTests: XCTestCase {
    func test_tabTitles() {
        XCTAssertEqual(
            GuideLayoutView.tabTitles(groups: ["HD", "News", "", "HD"], sourceNames: ["Locals", "News", "Locals"],
                                      hasFavorites: true),
            ["Favorites", "Locals", "News", "HD"])
        XCTAssertEqual(GuideLayoutView.tabTitles(groups: ["HD"], sourceNames: [], hasFavorites: false), ["HD"])
        // An M3U group called Favorites keeps its pinned tab.
        XCTAssertEqual(GuideLayoutView.tabTitles(groups: ["Favorites", "A"], sourceNames: [], hasFavorites: false),
                       ["Favorites", "A"])
    }

    func test_savedPlaylistGroupOrderKeepsFavoritesAndSourcesPinned() {
        XCTAssertEqual(
            GuideLayoutView.tabTitles(groups: ["Sports", "News", "Movies"],
                                      sourceNames: ["IPTV"], hasFavorites: true,
                                      savedOrder: ["Sports", "Movies", "News"]),
            ["Favorites", "IPTV", "Sports", "Movies", "News"])
    }

    func test_newAndRemovedGroupsDoNotBreakSavedOrder() {
        XCTAssertEqual(
            LiveTVGroupOrder.ordered(["News", "Kids", "Sports", "Kids"],
                                     saved: ["Sports", "Removed", "Sports", "News"]),
            ["Sports", "News", "Kids"])
    }

    func test_playlistGroupOrderIsKeptWithoutCustomSort() {
        let groups = ["Sports", "Movies", "Kids", "Sports", "News"]
        XCTAssertEqual(LiveTVGroupOrder.ordered(groups, saved: []),
                       ["Sports", "Movies", "Kids", "News"])
        XCTAssertEqual(GuideLayoutView.tabTitles(groups: groups, sourceNames: [], hasFavorites: false),
                       ["Sports", "Movies", "Kids", "News"])
    }

    func test_sourceChannelOrderSurvivesOutOfOrderFetchCompletion() {
        let first = [
            UnifiedChannel(id: "sports", sourceType: .genericM3U, sourceId: "a", channelNumber: 300, name: "Sports"),
            UnifiedChannel(id: "news", sourceType: .genericM3U, sourceId: "a", channelNumber: 10, name: "News")
        ]
        let second = [
            UnifiedChannel(id: "movies", sourceType: .genericM3U, sourceId: "b", name: "Movies")
        ]
        let channels = LiveTVDataStore.channelsInSourceOrder(["b": second, "a": first], sourceIDs: ["a", "b"])
        XCTAssertEqual(channels.map(\.id), ["sports", "news", "movies"])
    }
}
