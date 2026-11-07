// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  GuideCategoryTabsTests.swift
//  DreamCASTTests
//
//  The Guide's category tabs: Favorites, sources in order, then groups (#377).
//

import XCTest
import UIKit
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

    func test_hiddenGroupsDisappearButSavedOrderIsKept() {
        XCTAssertEqual(GuideLayoutView.tabTitles(
            groups: ["Sports", "News", "Movies"], sourceNames: ["IPTV"], hasFavorites: true,
            savedOrder: ["Movies", "Sports", "News"], hiddenGroups: ["Sports"]),
            ["Favorites", "IPTV", "Movies", "News"])
    }

    func test_customGuideChannelNameAndPrefixRules() {
        let channel = UnifiedChannel(id: "guide-name-test", sourceType: .genericM3U,
                                     sourceId: "test", name: "US: ESPN HD")
        let defaults = UserDefaults.standard
        let beforePrefix = defaults.string(forKey: LiveTVChannelNames.prefixKey)
        let beforeSuffix = defaults.string(forKey: LiveTVChannelNames.suffixKey)
        defer {
            if let beforePrefix { defaults.set(beforePrefix, forKey: LiveTVChannelNames.prefixKey) }
            else { defaults.removeObject(forKey: LiveTVChannelNames.prefixKey) }
            if let beforeSuffix { defaults.set(beforeSuffix, forKey: LiveTVChannelNames.suffixKey) }
            else { defaults.removeObject(forKey: LiveTVChannelNames.suffixKey) }
            LiveTVChannelNames.setCustomName("", for: channel.id)
        }
        defaults.set("US:", forKey: LiveTVChannelNames.prefixKey)
        defaults.set("HD", forKey: LiveTVChannelNames.suffixKey)
        XCTAssertEqual(LiveTVChannelNames.displayName(for: channel), "ESPN")
        LiveTVChannelNames.setCustomName("ESPN One", for: channel.id)
        XCTAssertEqual(LiveTVChannelNames.displayName(for: channel), "ESPN One")
    }

    @MainActor
    func test_liveGuideLayoutTracksChannelColumnWidthChanges() {
        let key = "liveTVGuideChannelColumnWidth"
        let styleKey = "liveTVTiviMateGuide"
        let defaults = UserDefaults.standard
        let previousWidth = defaults.object(forKey: key)
        let previousStyle = defaults.object(forKey: styleKey)
        defer {
            if let previousWidth { defaults.set(previousWidth, forKey: key) }
            else { defaults.removeObject(forKey: key) }
            if let previousStyle { defaults.set(previousStyle, forKey: styleKey) }
            else { defaults.removeObject(forKey: styleKey) }
        }
        defaults.set(true, forKey: styleKey)
        defaults.set(220, forKey: key)
        let layout = EPGLayout()
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                          collectionViewLayout: layout)
        layout.configure(rows: [[]], channelCount: 1, totalMinutes: 180,
                         timelineStart: Date(), now: Date())
        let index = IndexPath(item: 0, section: 0)
        XCTAssertEqual(layout.layoutAttributesForSupplementaryView(ofKind: EPGLayout.kindChannel,
                                                                    at: index)?.frame.width, 220)
        defaults.set(320, forKey: key)
        XCTAssertEqual(layout.layoutAttributesForSupplementaryView(ofKind: EPGLayout.kindChannel,
                                                                    at: index)?.frame.width, 320)
        _ = collection
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
