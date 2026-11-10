import SwiftUI
import UIKit
import Combine

struct SportFrameHome: View {
    let onTune: (UnifiedChannel) -> Void
    @StateObject private var fixtures = FixtureStore()
    @StateObject private var catalog = SportFrameCatalog()
    @StateObject private var liveTV = LiveTVDataStore.shared
    @StateObject private var teamPalettes = SportFrameTeamPaletteStore()
    @State private var tab = 0
    @AppStorage("sportFrameFollowedSportsV2") private var followedSportsValue = "Soccer|Basketball|American Football"
    @AppStorage("sportFrameSportOrderV2") private var sportOrderValue = "Soccer|Basketball|American Football|Tennis|Motorsport|Ice Hockey|Cricket"
    @AppStorage("sportFrameLeagueSelectionsV2") private var leagueSelectionsValue = "{}"
    @AppStorage("sportFrameLiveTVSourceID") private var liveTVSourceID = "all"
    @State private var expandedSport: String?
    @State private var expandedSettingsSection: String?
    @State private var dayOffset = 0
    @State private var refreshRevision = 0
    @State private var matchSportFilter = "All Sports"
    @State private var matchLeagueFilter = "All Leagues"
    @State private var selectedEvent: SportEvent?
    @State private var selectedDetailEvent: SportEvent?
    @State private var selectedSport: SportFrameSportSelection?
    @StateObject private var sportHighlights = SportFrameHighlightsStore()
    @State private var highlightMessage: String?
    @State private var pendingPlayerChannel: UnifiedChannel?
    @StateObject private var channelResolver = SportFrameBroadcastResolver()
    @FocusState private var focusedCard: String?
    @FocusState private var detailFocusedCard: String?
    @Namespace private var sportDetailFocusScope
    @State private var premiumKeyInput = ""
    @State private var premiumKeySaved = SportsDBAccess.hasPremiumKey
    @State private var credentialRevision = 0
    @State private var credentialMessage: String?

    private let fallbackSports = ["Soccer", "Basketball", "American Football", "Tennis", "Motorsport", "Ice Hockey", "Cricket", "Baseball", "Rugby", "Golf"]
    private let accent = Color(red: 0.0, green: 0.8, blue: 0.94)
    private let allSports = "All Sports"
    private let allLeagueFilter = "All Leagues"

    private var selectedLiveTVSourceID: String? {
        liveTVSourceID != "all" && liveTV.sources.contains(where: { $0.id == liveTVSourceID })
            ? liveTVSourceID : nil
    }

    private var sportFrameChannels: [UnifiedChannel] {
        guard let sourceID = selectedLiveTVSourceID else { return liveTV.channels }
        return liveTV.channels.filter { $0.sourceId == sourceID }
    }

    private var sportOrder: [String] {
        let saved = sportOrderValue.split(separator: "|").map(String.init)
        let names = saved + catalog.sports + fallbackSports
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    private var followedSports: [String] {
        let followed = Set(followedSportsValue.split(separator: "|").map(String.init))
        return sportOrder.filter { followed.contains($0) }
    }

    private var leagueSelections: [String: [String]] {
        guard let data = leagueSelectionsValue.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }

    private func matches(in sport: String) -> [SportEvent] {
        let chosen = leagueSelections[sport]
        return fixtures.events.filter { event in
            guard fixtures.eventSports[event.idEvent] == sport else { return false }
            return chosen.map { $0.contains(event.league) } ?? true
        }
    }

    private var filteredSports: [String] {
        matchSportFilter == allSports ? followedSports : followedSports.filter { $0 == matchSportFilter }
    }

    private var filteredMatches: [SportEvent] {
        filteredSports.flatMap { sport in
            matches(in: sport).filter { matchLeagueFilter == allLeagueFilter || $0.league == matchLeagueFilter }
        }
    }

    private var followingDayMatches: [SportEvent] {
        guard dayOffset == 0 else { return [] }
        return filteredSports.flatMap { sport in
            let chosen = leagueSelections[sport]
            return fixtures.nextDayEvents.filter { event in
                fixtures.nextDaySports[event.idEvent] == sport &&
                (chosen.map { $0.contains(event.league) } ?? true) &&
                (matchLeagueFilter == allLeagueFilter || event.league == matchLeagueFilter)
            }
        }
    }

    private func isLive(_ event: SportEvent) -> Bool {
        dayOffset == 0 ? fixtures.isLive(event) : event.isLive
    }

    private var filterLeagues: [String] {
        let names = filteredSports.flatMap { allLeagues(for: $0) }
        return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func sortedByStartTime(_ events: [SportEvent]) -> [SportEvent] {
        events.sorted { lhs, rhs in
            switch (lhs.startDate, rhs.startDate) {
            case let (left?, right?):
                return left == right ? lhs.name < rhs.name : left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.name < rhs.name
            }
        }
    }

    private var firstMatchFocusID: String? {
        if let event = filteredMatches.first(where: { isLive($0) }) {
            return "match-shelf-Happening now-\(event.idEvent)"
        }
        let upcoming = sortedByStartTime(filteredMatches.filter { !isLive($0) && ($0.isUpcoming || $0.startDate == nil) })
        if let event = upcoming.first {
            return "match-shelf-Coming up-\(event.idEvent)"
        }
        if let event = sortedByStartTime(followingDayMatches).first {
            return "match-shelf-Coming up · Tomorrow-\(event.idEvent)"
        }
        if let event = filteredMatches.first(where: { $0.intHomeScore != nil || $0.intAwayScore != nil }),
           !filteredMatches.contains(where: { isLive($0) || $0.isUpcoming || $0.startDate == nil }) {
            return "match-shelf-Recent results-\(event.idEvent)"
        }
        if let sport = filteredSports.first(where: { candidate in
            filteredMatches.contains { fixtures.eventSports[$0.idEvent] == candidate }
        }), let event = filteredMatches.first(where: { fixtures.eventSports[$0.idEvent] == sport }) {
            return "match-sport-\(sport)-\(event.idEvent)"
        }
        return nil
    }

    private var toolbarFocusIDs: [String] {
        ["filter-sport", "filter-league"] + (-1...3).map { "filter-day-\($0)" }
            + ["filter-refresh", "filter-settings"]
    }

    private func moveFocusDown(_ direction: MoveCommandDirection, within order: [String], to target: String?) {
        guard direction == .down, let current = focusedCard,
              order.contains(current), let target else { return }
        // Give tvOS its own focus move first. Only bridge an otherwise empty row.
        DispatchQueue.main.async {
            guard focusedCard == current else { return }
            focusedCard = target
        }
    }

    private var firstContentFocusID: String? {
        switch tab {
        case 0: return "filter-sport"
        case 1: return sportFrameChannels.first.map { "channel-\($0.id)" }
        default: return "settings-sports"
        }
    }

    private func toggleSport(_ name: String) {
        var selected = Set(followedSports)
        if selected.contains(name) { selected.remove(name) } else { selected.insert(name) }
        followedSportsValue = sportOrder.filter { selected.contains($0) }.joined(separator: "|")
    }

    private func moveSport(_ name: String, by step: Int) {
        var ordered = sportOrder
        guard let index = ordered.firstIndex(of: name), ordered.indices.contains(index + step) else { return }
        ordered.swapAt(index, index + step)
        sportOrderValue = ordered.joined(separator: "|")
    }

    private func toggleLeague(_ league: String, sport: String) {
        var choices = leagueSelections
        var selected = Set(choices[sport] ?? allLeagues(for: sport))
        if selected.contains(league) { selected.remove(league) } else { selected.insert(league) }
        choices[sport] = selected.sorted()
        saveLeagueSelections(choices)
    }

    private func saveLeagueSelections(_ choices: [String: [String]]) {
        if let data = try? JSONEncoder().encode(choices), let value = String(data: data, encoding: .utf8) {
            leagueSelectionsValue = value
        }
    }

    private func allLeagues(for sport: String) -> [String] {
        let fromCatalog = catalog.leagues(for: sport).map(\.strLeague)
        let fromMatches = fixtures.events.filter { fixtures.eventSports[$0.idEvent] == sport }.map(\.league)
        return Array(Set(fromCatalog + fromMatches)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        ZStack {
            SportFrameCinematicBackdrop().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 52) {
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            navigation("Sports", index: 0, symbol: "sportscourt")
                            navigation("Channels", index: 1, symbol: "tv")
                            navigation("Settings", index: 2, symbol: "gearshape")
                        }
                        .focusSection()
                        .onMoveCommand { direction in
                            moveFocusDown(direction, within: ["nav-0", "nav-1", "nav-2"],
                                          to: firstContentFocusID)
                        }
                        .padding(6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.17), lineWidth: 1))
                        Spacer()
                    }
                    switch tab {
                    case 0: matchesPage
                    case 1: channelsPage
                    default: setupPage
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 30)
                .padding(.bottom, 90)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: "\(followedSportsValue)-\(sportOrderValue)-\(dayOffset)-\(credentialRevision)-\(refreshRevision)") {
            await fixtures.fetch(sports: followedSports,
                                 date: Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date(),
                                 quietly: !fixtures.events.isEmpty)
        }
        .task(id: "live-\(credentialRevision)-\(dayOffset)-\(refreshRevision)") {
            guard dayOffset == 0, SportsDBAccess.hasPremiumKey else { return }
            await fixtures.refreshLiveScores()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(120)) } catch { break }
                if Task.isCancelled { break }
                await fixtures.refreshLiveScores()
            }
        }
        .task(id: "scores-\(followedSportsValue)-\(dayOffset)-\(credentialRevision)-\(refreshRevision)") {
            guard dayOffset == 0, !followedSports.isEmpty else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(300)) } catch { break }
                if Task.isCancelled { break }
                await fixtures.refreshScores(sports: followedSports, date: Date())
            }
        }
        .task(id: "schedule-\(followedSportsValue)-\(dayOffset)-\(credentialRevision)-\(refreshRevision)") {
            guard dayOffset == 0, !followedSports.isEmpty else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(900)) } catch { break }
                if Task.isCancelled { break }
                await fixtures.fetch(sports: followedSports, date: Date(), quietly: true)
            }
        }
        .task(id: credentialRevision) {
            await catalog.refresh()
        }
        .task(id: "broadcasts-\(liveTVSourceID)-\(liveTV.channels.count)-\(liveTV.epg.count)-\(fixtures.events.map(\.idEvent).joined(separator: "|"))-\(fixtures.nextDayEvents.map(\.idEvent).joined(separator: "|"))") {
            await channelResolver.refresh(events: fixtures.events + fixtures.nextDayEvents,
                                          channels: sportFrameChannels,
                                          programs: liveTV.epg,
                                          sourceID: liveTVSourceID)
        }
        .sheet(item: $selectedEvent, onDismiss: {
            if let channel = pendingPlayerChannel {
                pendingPlayerChannel = nil
                DispatchQueue.main.async {
                    presentSportFrameChannel(channel)
                }
            }
        }) { event in
            eventChannels(event, onClose: { selectedEvent = nil })
        }
        .sheet(item: $selectedSport) { selection in
            sportDetailPage(selection.name)
        }
    }

    private func navigation(_ label: String, index: Int, symbol: String) -> some View {
        return Button { tab = index } label: {
            HStack(spacing: 9) {
                if index == 2 { Image(systemName: symbol) }
                Text(label)
            }
            .font(.system(size: 23, weight: tab == index ? .bold : .medium))
        }
        .buttonStyle(.bordered)
        .tint(Color.white.opacity(0.8))
        .focused($focusedCard, equals: "nav-\(index)")
    }

    private var matchesPage: some View {
        VStack(alignment: .leading, spacing: 58) {
            HStack(spacing: 16) {
                Menu {
                    Button(allSports) { matchSportFilter = allSports; matchLeagueFilter = allLeagueFilter }
                    ForEach(followedSports, id: \.self) { sport in
                        Button(sport) { matchSportFilter = sport; matchLeagueFilter = allLeagueFilter }
                    }
                } label: { Label(matchSportFilter, systemImage: "sportscourt") }
                .buttonStyle(.bordered)
                .focused($focusedCard, equals: "filter-sport")
                Menu {
                    Button(allLeagueFilter) { matchLeagueFilter = allLeagueFilter }
                    ForEach(filterLeagues, id: \.self) { league in
                        Button(league) { matchLeagueFilter = league }
                    }
                } label: { Label(matchLeagueFilter, systemImage: "list.bullet") }
                .buttonStyle(.bordered)
                .focused($focusedCard, equals: "filter-league")
                HStack(spacing: 8) {
                    ForEach(-1...3, id: \.self) { offset in
                        Button(offset == 0 ? "Today" : offset == -1 ? "Yesterday" : "+\(offset)d") { dayOffset = offset }
                            .buttonStyle(.bordered)
                            .tint(Color.white.opacity(dayOffset == offset ? 0.8 : 0.52))
                            .focused($focusedCard, equals: "filter-day-\(offset)")
                    }
                }
                Spacer()
                Button { refreshRevision += 1 } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.bordered)
                    .focused($focusedCard, equals: "filter-refresh")
                Button { tab = 2 } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.bordered)
                    .focused($focusedCard, equals: "filter-settings")
            }
            .focusSection()
            .onMoveCommand { direction in
                moveFocusDown(direction, within: toolbarFocusIDs, to: firstMatchFocusID)
            }
            if followedSports.isEmpty {
                emptyPanel("Select sports in Setup to see matches.")
            } else if fixtures.loading {
                ProgressView("Loading sports…")
            } else if let error = fixtures.error {
                Text(error).foregroundStyle(.orange)
            } else if filteredMatches.isEmpty && followingDayMatches.isEmpty {
                emptyPanel("No matches for these filters and date. Try All Sports or All Leagues.")
            } else {
                matchShelf("Happening now", events: filteredMatches.filter { isLive($0) })
                let todayUpcoming = sortedByStartTime(filteredMatches.filter { !isLive($0) && ($0.isUpcoming || $0.startDate == nil) })
                matchShelf(todayUpcoming.isEmpty && !followingDayMatches.isEmpty ? "Coming up · Tomorrow" : "Coming up",
                           events: todayUpcoming.isEmpty ? sortedByStartTime(followingDayMatches) : todayUpcoming)
                if !filteredMatches.contains(where: { isLive($0) || $0.isUpcoming || $0.startDate == nil }) && followingDayMatches.isEmpty {
                    matchShelf("Recent results", events: filteredMatches.filter { $0.intHomeScore != nil || $0.intAwayScore != nil })
                }
                leagueSummarySection
            }
        }
    }

    private func matchShelf(_ title: String, events: [SportEvent]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 29, weight: .semibold)).foregroundStyle(Color.white.opacity(0.88))
            if events.isEmpty {
                Text(title == "Happening now" ? "No matches marked live by the provider. Use Refresh to check again." :
                     title == "Coming up" ? "No upcoming matches on this date. Choose +1d to see tomorrow's schedule." :
                     "No \(title.lowercased()) matches found.")
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(22)
                    .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
                    .sportFrameGlassPanel(radius: 18)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(events) { event in matchCard(event, focusScope: "shelf-\(title)") }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .focusSection()
    }

    private var leagueSummarySection: some View {
        VStack(alignment: .leading, spacing: 60) {
            ForEach(filteredSports.filter { sport in
                filteredMatches.contains { fixtures.eventSports[$0.idEvent] == sport }
            }, id: \.self) { sport in
                leagueShelf(for: sport)
            }
        }
    }

    private func leagueShelf(for sport: String) -> some View {
        let sportMatches = filteredMatches.filter { fixtures.eventSports[$0.idEvent] == sport }
        return sportShelf(sport: sport, events: sportMatches)
    }

    private func sportShelf(sport: String, events: [SportEvent]) -> some View {
        let leagues = Array(Set(events.map(\.league))).sorted { lhs, rhs in
            let left = leagueRank(lhs, sport: sport)
            let right = leagueRank(rhs, sport: sport)
            return left == right ? lhs.localizedStandardCompare(rhs) == .orderedAscending : left < right
        }
        return VStack(alignment: .leading, spacing: 20) {
            if !events.isEmpty {
                Button { selectedSport = SportFrameSportSelection(name: sport) } label: {
                    HStack(spacing: 9) {
                        Text(sport)
                        Image(systemName: "chevron.right").font(.system(size: 20, weight: .semibold))
                    }
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
                }
                .buttonStyle(SportFrameArtworkButtonStyle())
                .focused($focusedCard, equals: "sport-header-\(sport)")
                .sportFrameFocusOutline(focusedCard == "sport-header-\(sport)")
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(leagues, id: \.self) { league in
                        sportLeagueCard(title: league, sport: sport, events: events.filter { $0.league == league })
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 12)
            }
            .scrollClipDisabled()
            if !events.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(events) { event in matchCard(event, focusScope: "sport-\(sport)") }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .focusSection()
    }

    private func leagueRank(_ name: String, sport: String) -> Int {
        guard sport.caseInsensitiveCompare("Basketball") == .orderedSame else { return 0 }
        let text = name.lowercased()
        if text == "nba" { return 0 }
        if text.contains("eastern conference") { return 1 }
        if text.contains("western conference") { return 2 }
        if text.contains("college") || text.contains("ncaa") { return 3 }
        return 4
    }

    private func sportDetailPage(_ sport: String) -> some View {
        let events = filteredMatches.filter { fixtures.eventSports[$0.idEvent] == sport }
        let leagues = Array(Set(events.map(\.league))).sorted {
            let left = leagueRank($0, sport: sport)
            let right = leagueRank($1, sport: sport)
            return left == right ? $0.localizedStandardCompare($1) == .orderedAscending : left < right
        }
        let featured = events.filter { isLive($0) || $0.isUpcoming }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }

        return ZStack {
            SportFrameCinematicBackdrop().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 38) {
                    HStack(spacing: 20) {
                        Image(systemName: sportSymbol(sport))
                            .font(.system(size: 38)).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(sport).font(.system(size: 42, weight: .bold))
                            Text("\(events.count) matches · \(leagues.count) leagues")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Back to Sports") { selectedSport = nil }
                            .buttonStyle(.bordered)
                            .focused($detailFocusedCard, equals: "sport-detail-back")
                            .prefersDefaultFocus(in: sportDetailFocusScope)
                            .overlay {
                                Capsule().stroke(detailFocusedCard == "sport-detail-back" ? .white : .clear, lineWidth: 2)
                                    .allowsHitTesting(false)
                            }
                    }

                    if !featured.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Featured matches").font(.system(size: 30, weight: .semibold))
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 18) {
                                    ForEach(featured) { event in
                                        matchCard(event, focusScope: "detail-\(sport)", inSportDetail: true)
                                    }
                                }
                                .padding(.vertical, 12)
                            }
                            .focusSection()
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Yesterday's video highlights")
                            .font(.system(size: 30, weight: .semibold))
                        if sportHighlights.loading {
                            ProgressView("Finding highlights…")
                        } else if sportHighlights.videos.isEmpty {
                            Text("No video highlights were found for yesterday.")
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 18) {
                                    ForEach(sportHighlights.videos) { video in
                                        Button { openSportHighlight(video) } label: {
                                            VStack(alignment: .leading, spacing: 10) {
                                                AsyncImage(url: video.thumbnailURL) { image in
                                                    image.resizable().scaledToFill()
                                                } placeholder: {
                                                    ZStack {
                                                        Color.white.opacity(0.08)
                                                        Image(systemName: "play.rectangle.fill")
                                                            .foregroundStyle(accent).font(.largeTitle)
                                                    }
                                                }
                                                .frame(width: 330, height: 185)
                                                .clipped()
                                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                                Text(video.title)
                                                    .font(.system(size: 18, weight: .semibold))
                                                    .lineLimit(2)
                                            }
                                            .frame(width: 330, alignment: .leading)
                                        }
                                        .buttonStyle(SportFrameArtworkButtonStyle())
                                        .focused($detailFocusedCard, equals: "highlight-\(video.id)")
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(detailFocusedCard == "highlight-\(video.id)" ? .white : .clear, lineWidth: 2)
                                                .allowsHitTesting(false)
                                        }
                                    }
                                }
                                .padding(.vertical, 12)
                            }
                            .focusSection()
                        }
                        if let highlightMessage {
                            Text(highlightMessage).foregroundStyle(.orange)
                        }
                    }

                    Text("All leagues and fixtures")
                        .font(.system(size: 30, weight: .semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 430), spacing: 22, alignment: .top)],
                              alignment: .leading, spacing: 22) {
                        ForEach(leagues, id: \.self) { league in
                            sportLeagueCard(title: league, sport: sport,
                                            events: events.filter { $0.league == league },
                                            showAll: true, focusScope: "detail-", inSportDetail: true)
                        }
                    }
                    .focusSection()
                    if events.isEmpty { emptyPanel("No matches available for this sport on the selected day.") }
                }
                .padding(50)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focusScope(sportDetailFocusScope)
        }
        .task(id: sport) {
            highlightMessage = nil
            await sportHighlights.fetchYesterday(sport: sport)
        }
        .onAppear {
            DispatchQueue.main.async { detailFocusedCard = "sport-detail-back" }
        }
        .sheet(item: $selectedDetailEvent, onDismiss: {
            if let channel = pendingPlayerChannel {
                pendingPlayerChannel = nil
                DispatchQueue.main.async { presentSportFrameChannel(channel) }
            }
        }) { event in
            eventChannels(event, onClose: { selectedDetailEvent = nil })
        }
    }

    private func openSportHighlight(_ video: SportFrameVideoHighlight) {
        guard let url = video.youtubeAppURL else {
            highlightMessage = "This highlight has no valid YouTube link."
            return
        }
        UIApplication.shared.open(url) { opened in
            if !opened {
                Task { @MainActor in
                    highlightMessage = "Install YouTube on Apple TV to watch this highlight."
                }
            }
        }
    }

    private func sportLeagueCard(title: String, sport: String, events: [SportEvent],
                                 showAll: Bool = false, focusScope: String = "",
                                 inSportDetail: Bool = false) -> some View {
        let leagueID = events.compactMap(\.idLeague).first
        let badge = events.compactMap(\.leagueBadge).first ?? catalog.badgeURL(for: title, sport: sport, idLeague: leagueID)
        return VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 9) {
                if let badge {
                    AsyncImage(url: badge) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: sportSymbol(sport)).foregroundStyle(.secondary)
                    }
                    .frame(width: 32, height: 32)
                } else {
                    Image(systemName: sportSymbol(sport))
                        .font(.headline).foregroundStyle(.white.opacity(0.85))
                        .frame(width: 32, height: 32)
                }
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(events.prefix(showAll ? events.count : 5)) { event in
                Button { if inSportDetail { selectedDetailEvent = event } else { selectedEvent = event } } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 10) {
                            sportBadge(event.homeBadge)
                            Text(event.strHomeTeam ?? "Home")
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                            Spacer(minLength: 5)
                            Text(fixtures.score(for: event).home ?? event.timeLabel)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(white: 0.66))
                        }
                        HStack(alignment: .top, spacing: 10) {
                            sportBadge(event.awayBadge)
                            Text(event.strAwayTeam ?? "Away")
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                            Spacer(minLength: 5)
                            if let awayScore = fixtures.score(for: event).away {
                                Text(awayScore)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color(white: 0.66))
                            }
                        }
                    }
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(SportFrameArtworkButtonStyle())
                .focusEffectDisabled(!inSportDetail)
                .focused(inSportDetail ? $detailFocusedCard : $focusedCard,
                         equals: "\(focusScope)league-\(sport)-\(title)-\(event.idEvent)")
                .background((inSportDetail ? detailFocusedCard : focusedCard) == "\(focusScope)league-\(sport)-\(title)-\(event.idEvent)" ? Color.white.opacity(0.09) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke((inSportDetail ? detailFocusedCard : focusedCard) == "\(focusScope)league-\(sport)-\(title)-\(event.idEvent)" ? Color.white.opacity(0.86) : .clear,
                                lineWidth: 2)
                        .allowsHitTesting(false)
                }
                Divider().opacity(0.35)
            }
        }
        .padding(20)
        .frame(width: 430, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .sportFrameGlassPanel(radius: 19)
        .task(id: "badge-\(sport)-\(leagueID ?? title)") {
            if badge == nil { await catalog.loadBadge(for: title, sport: sport, idLeague: leagueID) }
        }
    }

    private func sportSymbol(_ sport: String) -> String {
        switch sport.lowercased() {
        case "soccer": return "soccerball"
        case "basketball": return "basketball.fill"
        case "american football": return "american.football.fill"
        case "ice hockey": return "hockey.puck.fill"
        case "baseball": return "baseball.fill"
        case "tennis": return "tennis.racket"
        default: return "sportscourt.fill"
        }
    }

    private func sportBadge(_ url: URL?) -> some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: {
            Image(systemName: "shield.fill").foregroundStyle(.secondary)
        }
        .frame(width: 27, height: 27)
    }

    private func matchCard(_ event: SportEvent, focusScope: String, inSportDetail: Bool = false) -> some View {
        let live = isLive(event)
        let focusID = "match-\(focusScope)-\(event.idEvent)"
        return VStack(alignment: .leading, spacing: 9) {
            Button { if inSportDetail { selectedDetailEvent = event } else { selectedEvent = event } } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(event.league)
                            .font(.system(size: 15, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                        Spacer(minLength: 0)
                        Text(live ? "● LIVE" : event.isUpcoming ? "SOON" : event.startDate == nil ? "SCHEDULED" : "RESULT")
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(live ? Color.red : Color.blue, in: Capsule())
                            .fixedSize()
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 12) {
                        matchBadge(event.homeBadge)
                        Spacer(minLength: 0)
                        Text(fixtures.score(for: event).home.map { "\($0) – \(fixtures.score(for: event).away ?? "–")" } ?? event.timeLabel)
                            .font(.system(size: 25, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                        Spacer(minLength: 0)
                        matchBadge(event.awayBadge)
                    }
                    Spacer(minLength: 0)
                    HStack {
                        Spacer()
                        Text(live ? "LIVE" : event.timeLabel)
                            .font(.caption.bold())
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
                .padding(13)
                .frame(width: 330)
                .frame(minHeight: 184)
                .background { matchCardBackdrop(home: event.homeBadge, away: event.awayBadge) }
            }
            .buttonStyle(SportFrameArtworkButtonStyle())
            .focusEffectDisabled(!inSportDetail)
            .focused(inSportDetail ? $detailFocusedCard : $focusedCard, equals: focusID)
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke((inSportDetail ? detailFocusedCard : focusedCard) == focusID ? Color.white.opacity(0.86) : Color.clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .task(id: "palette-\(event.idEvent)") {
                await teamPalettes.prepare(home: event.homeBadge, away: event.awayBadge)
            }
            Text(event.name)
                .font(.system(size: 18, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            let count = channelResolver.channelIDs[event.idEvent]?.count ?? 0
            Text(count == 0 ? "Find channels" : "\(count) matching channels")
                .font(.system(size: 15)).foregroundStyle(Color(white: 0.48))
        }
        .frame(width: 330, alignment: .topLeading)
    }

    private func matchBadge(_ url: URL?) -> some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: {
            Image(systemName: "shield.fill").foregroundStyle(.white.opacity(0.7))
        }
        .padding(5)
        .frame(width: 65, height: 65)
        .background(.white.opacity(0.11), in: Circle())
    }

    private func matchCardBackdrop(home: URL?, away: URL?) -> some View {
        GeometryReader { geometry in
            let left = teamPalettes.color(for: home, fallback: Color(red: 0.08, green: 0.19, blue: 0.42))
            let right = teamPalettes.color(for: away, fallback: Color(red: 0.47, green: 0.08, blue: 0.17))
            ZStack {
                right
                Color.black.opacity(0.12)
                Path { path in
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: geometry.size.width * 0.57, y: 0))
                    path.addLine(to: CGPoint(x: geometry.size.width * 0.34, y: geometry.size.height))
                    path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(left)
                LinearGradient(colors: [.white.opacity(0.07), .clear, .black.opacity(0.18)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var sportLeagueSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Choose your sports and leagues. Use the arrows to set the order shown on Matches.")
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button("Select all") { followedSportsValue = sportOrder.joined(separator: "|") }
                    .focused($focusedCard, equals: "sports-all")
                    .sportFrameFocusOutline(focusedCard == "sports-all")
                Button("Unselect all") { followedSportsValue = "" }
                    .focused($focusedCard, equals: "sports-none")
                    .sportFrameFocusOutline(focusedCard == "sports-none")
            }
            .buttonStyle(SportFrameGlassControlStyle())
            if let message = catalog.message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sportOrder, id: \.self) { sport in
                    HStack(spacing: 15) {
                        Button { toggleSport(sport) } label: {
                            Image(systemName: followedSports.contains(sport) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(followedSports.contains(sport) ? .white : .gray)
                            Text(sport).foregroundStyle(followedSports.contains(sport) ? .white : .gray)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .buttonStyle(SportFrameArtworkButtonStyle())
                        .focused($focusedCard, equals: "sport-toggle-\(sport)")
                        .sportFrameFocusOutline(focusedCard == "sport-toggle-\(sport)")
                        Button { expandedSport = expandedSport == sport ? nil : sport } label: {
                            Image(systemName: expandedSport == sport ? "chevron.down" : "chevron.right")
                        }
                        .buttonStyle(SportFrameGlassControlStyle())
                        .focused($focusedCard, equals: "sport-expand-\(sport)")
                        .sportFrameFocusOutline(focusedCard == "sport-expand-\(sport)")
                        Button { moveSport(sport, by: -1) } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(SportFrameGlassControlStyle())
                        .focused($focusedCard, equals: "sport-up-\(sport)")
                        .sportFrameFocusOutline(focusedCard == "sport-up-\(sport)")
                        .disabled(sportOrder.first == sport)
                        Button { moveSport(sport, by: 1) } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(SportFrameGlassControlStyle())
                        .focused($focusedCard, equals: "sport-down-\(sport)")
                        .sportFrameFocusOutline(focusedCard == "sport-down-\(sport)")
                        .disabled(sportOrder.last == sport)
                    }
                    .padding(.vertical, 15)
                    if expandedSport == sport {
                        let leagueNames = allLeagues(for: sport)
                        LazyVStack(alignment: .leading, spacing: 10) {
                            Text("Leagues in \(sport)")
                                .font(.headline).foregroundStyle(accent)
                            HStack(spacing: 16) {
                                Button("Select all") {
                                    var choices = leagueSelections
                                    choices.removeValue(forKey: sport)
                                    saveLeagueSelections(choices)
                                }
                                .focused($focusedCard, equals: "league-all-\(sport)")
                                .sportFrameFocusOutline(focusedCard == "league-all-\(sport)")
                                Button("Unselect all") {
                                    var choices = leagueSelections
                                    choices[sport] = []
                                    saveLeagueSelections(choices)
                                }
                                .focused($focusedCard, equals: "league-none-\(sport)")
                                .sportFrameFocusOutline(focusedCard == "league-none-\(sport)")
                            }
                            .buttonStyle(SportFrameGlassControlStyle())
                            if leagueNames.isEmpty {
                                Text("No leagues returned. Premium access provides more league data.")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(leagueNames, id: \.self) { league in
                                Button { toggleLeague(league, sport: sport) } label: {
                                    HStack {
                                        Image(systemName: (leagueSelections[sport]?.contains(league) ?? true) ? "checkmark.circle.fill" : "circle")
                                        Text(league)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(SportFrameArtworkButtonStyle())
                                .focused($focusedCard, equals: "league-toggle-\(sport)-\(league)")
                                .sportFrameFocusOutline(focusedCard == "league-toggle-\(sport)-\(league)")
                            }
                        }
                        .padding(.leading, 55)
                        .padding(.bottom, 20)
                    }
                    Divider()
                }
            }
            .padding(.horizontal, 12)
            Text("Sports and leagues come from TheSportsDB. Free access returns fewer choices.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func teamRow(name: String, badge: URL?, score: String?) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: badge) { image in image.resizable().scaledToFit() } placeholder: {
                Image(systemName: "shield").foregroundStyle(.secondary)
            }
            .frame(width: 48, height: 48)
            Text(name).font(.headline).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let score { Text(score).font(.title2.bold()) }
        }
    }

    private var channelsPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("My channels").font(.largeTitle.bold())
            Text("\(sportFrameChannels.count) channels from the selected playlist")
                .foregroundStyle(.secondary)
            if sportFrameChannels.isEmpty { emptyPanel("No channels in this playlist. Select another source in SportFrame Settings.") }
            channelGrid(sportFrameChannels)
        }
    }

    private func playSportFrameChannel(_ channel: UnifiedChannel) {
        if selectedDetailEvent != nil {
            pendingPlayerChannel = channel
            selectedDetailEvent = nil
        } else if selectedEvent != nil {
            pendingPlayerChannel = channel
            selectedEvent = nil
        } else {
            presentSportFrameChannel(channel)
        }
    }

    private func presentSportFrameChannel(_ channel: UnifiedChannel) {
        // Match the working Live TV path: present from the active controller,
        // never from an off-screen SwiftUI representable host.
        guard let top = LiveProgramMenu.topViewController() else { return }
        let player = LiveTVAetherPlayerViewController(channel: channel)
        player.modalPresentationStyle = .fullScreen
        // No onMinimize: Back closes the stream and exposes SportFrame again.
        top.present(player, animated: true)
    }

    private func channelGrid(_ channels: [UnifiedChannel], columns: Int = 4) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: columns), spacing: 18) {
            ForEach(channels.prefix(80)) { channel in
                Button { playSportFrameChannel(channel) } label: {
                    HStack(spacing: 16) {
                        AsyncImage(url: channel.logoURL) { image in image.resizable().scaledToFit() } placeholder: {
                            Image(systemName: "tv").foregroundStyle(.secondary)
                        }
                        .frame(width: 68, height: 62)
                        VStack(alignment: .leading) {
                            Text(channel.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                            Text(channel.groupTitle ?? "Live TV").font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(20)
                    .sportFrameGlassPanel(radius: 16)
                }
                .buttonStyle(SportFrameArtworkButtonStyle())
                .focused($focusedCard, equals: "channel-\(channel.id)")
                .sportFrameFocusOutline(focusedCard == "channel-\(channel.id)", radius: 16)
            }
        }
        .focusSection()
    }

    private func matchChannelList(_ channels: [UnifiedChannel]) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(channels) { channel in
                SportFrameMatchChannelRow(channel: channel, accent: accent) {
                    playSportFrameChannel(channel)
                }
            }
        }
        .focusSection()
    }

    private var setupPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("SportFrame Settings").font(.system(size: 42, weight: .bold))
            Text("Manage your sports, data access, and TV channels.")
                .font(.title3).foregroundStyle(.secondary)
            settingsSection("Which sports do you follow?", subtitle: "\(followedSports.count) sports selected · choose leagues and order", icon: "sportscourt", key: "sports") {
                sportLeagueSettings
            }
            settingsSection("TheSportsDB Premium", subtitle: premiumKeySaved ? "Premium key saved" : "Free access", icon: "key.horizontal", key: "premium") {
                premiumSettings
            }
            settingsSection("Live TV connection", subtitle: "\(liveTV.channels.count) channels available", icon: "tv", key: "livetv") {
                liveTVSettings
            }
        }
    }

    private func settingsSection<Content: View>(_ title: String, subtitle: String, icon: String,
                                                 key: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                expandedSettingsSection = expandedSettingsSection == key ? nil : key
            } label: {
                HStack(spacing: 24) {
                    Image(systemName: icon)
                        .font(.title2).foregroundStyle(accent)
                        .frame(width: 54, height: 54)
                        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(title).font(.title2.bold())
                        Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: expandedSettingsSection == key ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .contentShape(Rectangle())
            }
            .buttonStyle(SportFrameArtworkButtonStyle())
            .focused($focusedCard, equals: "settings-\(key)")
            .sportFrameFocusOutline(focusedCard == "settings-\(key)", radius: 18)
            if expandedSettingsSection == key {
                Divider().padding(.horizontal, 24)
                content()
                    .padding(28)
            }
        }
        .sportFrameGlassPanel(radius: 20)
        .focusSection()
    }

    private var premiumSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(premiumKeySaved ? "Premium key saved on this Apple TV" : "Using free sports data")
                .foregroundStyle(premiumKeySaved ? accent : .secondary)
            SecureField("Enter Premium API key", text: $premiumKeyInput)
                .textContentType(.password)
            HStack(spacing: 18) {
                Button("Save Premium Key") {
                    if SportsDBAccess.save(premiumKeyInput) {
                        premiumKeyInput = ""
                        premiumKeySaved = true
                        credentialRevision += 1
                        credentialMessage = "Key saved. Match data will reload with Premium access."
                    } else {
                        credentialMessage = "Could not save key. Use the API key from your TheSportsDB profile."
                    }
                }
                .buttonStyle(SportFrameGlassControlStyle(selected: true))
                .focused($focusedCard, equals: "premium-save")
                .sportFrameFocusOutline(focusedCard == "premium-save")
                Button("Use Free Access") {
                    SportsDBAccess.remove()
                    premiumKeyInput = ""
                    premiumKeySaved = false
                    credentialRevision += 1
                    credentialMessage = "Premium key removed. Free access is active."
                }
                .buttonStyle(SportFrameGlassControlStyle())
                .focused($focusedCard, equals: "premium-free")
                .sportFrameFocusOutline(focusedCard == "premium-free")
                .disabled(!premiumKeySaved)
            }
            if let credentialMessage {
                Text(credentialMessage).font(.footnote).foregroundStyle(.secondary)
            }
            Text("Your key stays in the Apple TV Keychain. TheSportsDB v1 sends it in the request URL.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var liveTVSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose which DreamCAST Live TV playlist SportFrame can use.")
                .foregroundStyle(.secondary)
            Text("\(sportFrameChannels.count.formatted()) channels available")
                .font(.title2.bold()).foregroundStyle(accent)

            Button {
                liveTVSourceID = "all"
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: selectedLiveTVSourceID == nil ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(accent)
                    Text("All Playlists").font(.headline)
                    Spacer()
                    Text(liveTV.channels.count.formatted()).foregroundStyle(.secondary)
                }
                .padding(16)
                .sportFrameGlassPanel(radius: 14)
            }
            .buttonStyle(SportFrameArtworkButtonStyle())
            .focused($focusedCard, equals: "source-all")
            .sportFrameFocusOutline(focusedCard == "source-all", radius: 14)

            ForEach(liveTV.sources) { source in
                Button {
                    liveTVSourceID = source.id
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: selectedLiveTVSourceID == source.id ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.displayName).font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(source.isConnected ? "Connected" : "Not connected")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(source.channelCount.formatted()).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .sportFrameGlassPanel(radius: 14)
                }
                .buttonStyle(SportFrameArtworkButtonStyle())
                .focused($focusedCard, equals: "source-\(source.id)")
                .sportFrameFocusOutline(focusedCard == "source-\(source.id)", radius: 14)
            }

            Text("Manage or refresh your sources in DreamCAST Live TV settings.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Your choice only filters SportFrame. Live TV playlists stay unchanged.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func eventChannels(_ event: SportEvent, onClose: @escaping () -> Void) -> some View {
        let matchIDs = Set(channelResolver.channelIDs[event.idEvent] ?? [])
        let matches = matchIDs.isEmpty
            ? ChannelMatcher.matching(event, in: sportFrameChannels)
            : sportFrameChannels.filter { matchIDs.contains($0.id) }
        return ZStack {
            SportFrameCinematicBackdrop().ignoresSafeArea()
            VStack {
                Spacer(minLength: 30)
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("WATCH MATCH").font(.subheadline.bold()).foregroundStyle(accent)
                                Text(event.name).font(.largeTitle.bold())
                            }
                            Spacer()
                            Button("Close", action: onClose)
                                .focused($focusedCard, equals: "event-close")
                                .sportFrameFocusOutline(focusedCard == "event-close")
                        }
                        Text("Choose a channel to watch full screen. Press Back to return to SportFrame.")
                            .foregroundStyle(.secondary)
                        if matches.isEmpty {
                            emptyPanel("No matching channels found. Check your Live TV playlist or browse all channels.")
                            Button("View all channels") {
                                onClose()
                                selectedSport = nil
                                tab = 1
                            }
                                .focused($focusedCard, equals: "event-all-channels")
                                .sportFrameFocusOutline(focusedCard == "event-all-channels")
                        } else {
                            matchChannelList(matches)
                        }
                    }
                    .padding(34)
                }
                .frame(maxWidth: 1050, maxHeight: 650)
                .sportFrameGlassPanel(radius: 28)
                Spacer(minLength: 30)
            }
            .padding(.horizontal, 30)
        }
    }

    private func emptyPanel(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            .padding(25)
            .sportFrameGlassPanel(radius: 16)
    }
}

// Stores broadcaster names by event and reusable provider-to-playlist links.
// Heavy EPG scans run off the main actor and never run during remote focus moves.
@MainActor
private final class SportFrameBroadcastResolver: ObservableObject {
    @Published private(set) var channelIDs: [String: [String]] = [:]

    private struct SavedIndex: Codable {
        var aliases: [String: [String]] = [:]
    }

    private static let cacheKey = "sportFrameBroadcastLinksV2"
    private var index: SavedIndex = {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "sportFrameBroadcastLinksV2"),
           let decoded = try? JSONDecoder().decode(SavedIndex.self, from: data) {
            defaults.removeObject(forKey: "sportFrameBroadcastIndexV1")
            return decoded
        }
        // Keep existing broadcaster-to-playlist links, but erase every old
        // event-specific broadcaster record from persistent storage.
        let migrated = defaults.data(forKey: "sportFrameBroadcastIndexV1")
            .flatMap { try? JSONDecoder().decode(SavedIndex.self, from: $0) } ?? SavedIndex()
        if let data = try? JSONEncoder().encode(migrated) {
            defaults.set(data, forKey: "sportFrameBroadcastLinksV2")
        }
        defaults.removeObject(forKey: "sportFrameBroadcastIndexV1")
        return migrated
    }()

    private func save() {
        if let data = try? JSONEncoder().encode(index) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    func refresh(events: [SportEvent], channels: [UnifiedChannel],
                 programs: [String: [UnifiedProgram]], sourceID: String) async {
        guard !events.isEmpty, !channels.isEmpty else {
            channelIDs = [:]
            return
        }

        // TheSportsDB broadcaster names are used for this lookup only.
        // Do not persist a list of broadcasters by event ID.
        var broadcasts: [String: [String]] = [:]
        for event in events.prefix(12) {
            if Task.isCancelled { return }
            broadcasts[event.idEvent] = await fetchBroadcasters(eventID: event.idEvent)
        }
        let savedAliases = index.aliases
        let eventTerms = events.map { event in
            (id: event.idEvent, home: event.strHomeTeam ?? "",
             away: event.strAwayTeam ?? "", start: event.startDate)
        }
        // UnifiedChannel and UnifiedProgram are Sendable. Keep all string scans
        // away from the tvOS focus and rendering thread.
        let resolved = await Task.detached(priority: .background) { () -> ([String: [String]], [String: [String]]) in
            let namedChannels = channels.map { (id: $0.id, name: ChannelMatcher.normalize($0.name)) }
            let validIDs = Set(channels.map(\.id))
            var results: [String: [String]] = [:]
            var aliases = savedAliases

            for event in eventTerms {
                if Task.isCancelled { break }
                var ids = Set<String>()

                // Primary: official broadcast channel names from TheSportsDB.
                for broadcaster in broadcasts[event.id] ?? [] {
                    let broadcast = ChannelMatcher.normalize(broadcaster)
                    guard broadcast.count >= 3 else { continue }
                    let aliasKey = sourceID + "|" + broadcast
                    ids.formUnion((aliases[aliasKey] ?? []).filter { validIDs.contains($0) })
                    let direct = namedChannels.filter { channel in
                        let padded = " " + channel.name + " "
                        return padded.contains(" " + broadcast + " ")
                    }.map(\.id)
                    ids.formUnion(direct)
                    if !direct.isEmpty { aliases[aliasKey] = direct }
                }

                // Secondary: use current guide titles near the match start.
                if ids.isEmpty {
                    let home = ChannelMatcher.normalize(event.home)
                    let away = ChannelMatcher.normalize(event.away)
                    if home.count >= 4 && away.count >= 4 {
                        for (channelID, guide) in programs where validIDs.contains(channelID) {
                            if guide.contains(where: { program in
                                if let start = event.start {
                                    guard program.startTime < start.addingTimeInterval(3 * 3600),
                                          program.endTime > start.addingTimeInterval(-2 * 3600) else { return false }
                                }
                                let title = ChannelMatcher.normalize(program.title)
                                return title.contains(home) && title.contains(away)
                            }) {
                                ids.insert(channelID)
                            }
                        }
                    }
                }

                // Last resort for event-specific PPV channels with no EPG.
                if ids.isEmpty {
                    let home = ChannelMatcher.normalize(event.home)
                    let away = ChannelMatcher.normalize(event.away)
                    if home.count >= 4 && away.count >= 4 {
                        ids.formUnion(namedChannels.filter {
                            $0.name.contains(home) && $0.name.contains(away)
                        }.map(\.id))
                    }
                }
                results[event.id] = channels.map(\.id).filter { ids.contains($0) }
            }
            return (results, aliases)
        }.value
        guard !Task.isCancelled else { return }
        channelIDs = resolved.0
        if index.aliases != resolved.1 {
            index.aliases = resolved.1
            save()
        }
    }

    private func fetchBroadcasters(eventID: String) async -> [String] {
        guard let url = URL(string: "https://www.thesportsdb.com/api/v1/json/\(SportsDBAccess.apiKey)/lookuptv.php?id=\(eventID)") else {
            return []
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = payload["tvevent"] as? [[String: Any]] else { return [] }
            return Array(Set(rows.compactMap { $0["strChannel"] as? String }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
        } catch {
            return []
        }
    }
}

private struct SportFrameMatchChannelRow: View {
    let channel: UnifiedChannel
    let accent: Color
    let onSelect: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 20) {
                AsyncImage(url: channel.logoURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "tv").foregroundStyle(.secondary)
                }
                .frame(width: 76, height: 58)
                VStack(alignment: .leading, spacing: 6) {
                    Text(channel.name)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Text(channel.groupTitle ?? "Live TV")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Image(systemName: "play.fill")
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sportFrameGlassPanel(radius: 16)
        }
        .buttonStyle(SportFrameArtworkButtonStyle())
        .focused($isFocused)
        .background(isFocused ? Color.white.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 16))
        .sportFrameFocusOutline(isFocused, radius: 16)
    }
}

private struct SportFrameSportSelection: Identifiable {
    let name: String
    var id: String { name }
}

private struct SportFrameVideoHighlight: Decodable, Identifiable {
    let idEvent: String?
    let strEvent: String?
    let strVideo: String?
    let strThumb: String?
    let strPoster: String?

    var id: String { "\(idEvent ?? "")-\(strVideo ?? "")" }
    var title: String { strEvent ?? "Match highlight" }
    var thumbnailURL: URL? { (strThumb ?? strPoster).flatMap(URL.init(string:)) }
    var youtubeAppURL: URL? {
        guard let strVideo, let url = URL(string: strVideo),
              let host = url.host?.lowercased(),
              host == "youtube.com" || host == "www.youtube.com" || host == "m.youtube.com" || host == "youtu.be" else { return nil }
        let videoID = host == "youtu.be" ? String(url.path.dropFirst())
            : URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value
        guard let videoID else { return nil }
        return YouTubeTrailer.appURL(videoID: videoID)
    }
}

private struct SportFrameVideoResponse: Decodable {
    let tvhighlights: [SportFrameVideoHighlight]?
}

@MainActor
private final class SportFrameHighlightsStore: ObservableObject {
    @Published private(set) var videos: [SportFrameVideoHighlight] = []
    @Published private(set) var loading = false
    private var cached: [String: [SportFrameVideoHighlight]] = [:]

    func fetchYesterday(sport: String) async {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date().addingTimeInterval(-86_400)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let date = formatter.string(from: yesterday)
        let cacheKey = "\(date)|\(sport)"
        if let saved = cached[cacheKey] { videos = saved; loading = false; return }

        videos = []
        loading = true
        defer { loading = false }
        var parts = URLComponents(string: "https://www.thesportsdb.com/api/v1/json/\(SportsDBAccess.apiKey)/eventshighlights.php")!
        parts.queryItems = [URLQueryItem(name: "d", value: date), URLQueryItem(name: "s", value: sport)]
        guard let url = parts.url else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let fetched = try JSONDecoder().decode(SportFrameVideoResponse.self, from: data).tvhighlights ?? []
            cached[cacheKey] = fetched
            videos = fetched
        } catch {
            // An empty state is preferable to holding up remote navigation.
        }
    }
}

private struct SportFrameCinematicBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.025, green: 0.045, blue: 0.085),
                             Color(red: 0.01, green: 0.013, blue: 0.027),
                             Color(red: 0.065, green: 0.024, blue: 0.045)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(Color.cyan.opacity(0.12))
                    .frame(width: geometry.size.width * 0.55)
                    .blur(radius: 150)
                    .offset(x: -geometry.size.width * 0.42, y: -geometry.size.height * 0.28)
                Circle()
                    .fill(Color(red: 1, green: 0.30, blue: 0.24).opacity(0.08))
                    .frame(width: geometry.size.width * 0.5)
                    .blur(radius: 155)
                    .offset(x: geometry.size.width * 0.44, y: geometry.size.height * 0.34)
            }
        }
    }
}

// A plain tvOS button can draw a large white focus plate over nearby titles.
// This style leaves focus drawing to the artwork outline above.
private struct SportFrameGlassControlStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 19, weight: selected ? .semibold : .medium))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 19)
            .padding(.vertical, 12)
            .background(Color.white.opacity(selected ? 0.22 : 0.09),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private struct SportFrameGlassPanelModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
    }
}

private extension View {
    func sportFrameGlassPanel(radius: CGFloat) -> some View {
        modifier(SportFrameGlassPanelModifier(radius: radius))
    }

    func sportFrameFocusOutline(_ focused: Bool, radius: CGFloat = 10) -> some View {
        self
            .focusEffectDisabled()
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(focused ? Color.white.opacity(0.85) : Color.clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }
    }
}

private struct SportFrameArtworkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

@MainActor
private final class SportFrameTeamPaletteStore: ObservableObject {
    @Published private var badgeColors: [URL: Color] = [:]
    private var requested = Set<URL>()

    func color(for badge: URL?, fallback: Color) -> Color {
        guard let badge else { return fallback }
        return badgeColors[badge] ?? fallback
    }

    func prepare(home: URL?, away: URL?) async {
        if let home { await loadColor(from: home) }
        if Task.isCancelled { return }
        if let away { await loadColor(from: away) }
    }

    private func loadColor(from url: URL) async {
        guard requested.insert(url).inserted else { return }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, _) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { requested.remove(url); return }
            if let color = Self.extractAccent(from: data) { badgeColors[url] = color }
        } catch {
            requested.remove(url)
        }
    }

    private static func extractAccent(from data: Data) -> Color? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        let side = 40
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard rendered else { return nil }

        // Pick the strongest colorful group. Ignore transparent and pale edges.
        var weights = [Double](repeating: 0, count: 24)
        var hues = [Double](repeating: 0, count: 24)
        var saturations = [Double](repeating: 0, count: 24)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255.0
            if alpha < 0.55 { continue }
            let red = CGFloat(pixels[offset]) / 255.0
            let green = CGFloat(pixels[offset + 1]) / 255.0
            let blue = CGFloat(pixels[offset + 2]) / 255.0
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var opacity: CGFloat = 0
            UIColor(red: red, green: green, blue: blue, alpha: 1)
                .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &opacity)
            if saturation < 0.28 || brightness < 0.16 || brightness > 0.94 { continue }
            let bucket = min(23, Int(Double(hue) * 24))
            let weight = alpha * Double(saturation * saturation)
            weights[bucket] += weight
            hues[bucket] += Double(hue) * weight
            saturations[bucket] += Double(saturation) * weight
        }
        guard let strongest = weights.indices.max(by: { weights[$0] < weights[$1] }),
              weights[strongest] > 0.25 else { return nil }
        let hue = hues[strongest] / weights[strongest]
        let saturation = min(0.82, max(0.56, saturations[strongest] / weights[strongest]))
        // Darken logo colors so white labels stay readable on both halves.
        return Color(hue: hue, saturation: saturation, brightness: 0.37)
    }
}
