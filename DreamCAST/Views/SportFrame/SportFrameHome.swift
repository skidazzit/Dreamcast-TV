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
    @State private var topMenuReturnRevision = 0
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

    private func returnToTopMenu() {
        guard selectedSport == nil, selectedEvent == nil else { return }
        // Back from the top tabs belongs to DreamCAST's main sidebar.
        guard focusedCard?.hasPrefix("nav-") != true else { return }
        topMenuReturnRevision += 1
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
            ScrollViewReader { mainScroll in
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
                    .id("sportsframe-top-menu")
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
            .onExitCommand {
                returnToTopMenu()
            }
            .onChange(of: topMenuReturnRevision) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    mainScroll.scrollTo("sportsframe-top-menu", anchor: .top)
                }
                // Wait until the top row is back on-screen before tvOS picks its focus.
                DispatchQueue.main.async {
                    focusedCard = "nav-\(tab)"
                }
            }
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
            SportFrameDetailFocusHost { detailFocus, scope, leagueFilter in
                sportDetailPage(selection.name, detailFocus: detailFocus,
                                focusScope: scope, leagueFilter: leagueFilter)
            }
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
                if direction == .up, let current = focusedCard,
                   toolbarFocusIDs.contains(current) {
                    focusedCard = "nav-0"
                } else {
                    moveFocusDown(direction, within: toolbarFocusIDs, to: firstMatchFocusID)
                }
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
        .onExitCommand { returnToTopMenu() }
        .background {
            SportFrameMenuBackBridge(isActive: tab == 0 && selectedSport == nil && selectedEvent == nil &&
                                    focusedCard != nil && focusedCard?.hasPrefix("nav-") != true) {
                returnToTopMenu()
            }
            .frame(width: 0, height: 0)
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
                    .foregroundStyle(focusedCard == "sport-header-\(sport)" ? Color.black : Color.white.opacity(0.88))
                    .padding(.horizontal, 21)
                    .padding(.vertical, 13)
                    .background {
                        if focusedCard == "sport-header-\(sport)" {
                            Capsule()
                                .fill(LinearGradient(colors: [Color(red: 0.85, green: 0.96, blue: 1.0),
                                                              Color(red: 0.68, green: 0.84, blue: 0.91)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                }
                .buttonStyle(SportFrameArtworkButtonStyle())
                .focused($focusedCard, equals: "sport-header-\(sport)")
                .focusEffectDisabled()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20, alignment: .top), count: 3),
                      alignment: .leading, spacing: 20) {
                ForEach(leagues, id: \.self) { league in
                    mainLeagueTable(league, sport: sport, events: events.filter { $0.league == league })
                }
            }
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

    private func mainLeagueTable(_ league: String, sport: String, events: [SportEvent]) -> some View {
        let ordered = events.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        let leagueID = events.compactMap(\.idLeague).first
        let badge = events.compactMap(\.leagueBadge).first ??
            catalog.badgeURL(for: league, sport: sport, idLeague: leagueID)
        return VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                if let badge {
                    AsyncImage(url: badge) { image in image.resizable().scaledToFit() }
                        placeholder: { Image(systemName: sportSymbol(sport)) }
                        .frame(width: 34, height: 34)
                } else {
                    Image(systemName: sportSymbol(sport))
                        .frame(width: 34, height: 34)
                }
                Text(league)
                    .font(.system(size: 23, weight: .semibold))
                    .lineLimit(2)
            }
            if ordered.count > 5 {
                ScrollView(.vertical) {
                    mainLeagueRows(ordered, sport: sport, league: league)
                }
                .frame(height: 400)
                .scrollIndicators(.visible)
                Text("\(ordered.count) matches · Scroll for more")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                mainLeagueRows(ordered, sport: sport, league: league)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .sportFrameGlassPanel(radius: 22)
        .task(id: "main-league-badge-\(sport)-\(leagueID ?? league)") {
            if badge == nil { await catalog.loadBadge(for: league, sport: sport, idLeague: leagueID) }
        }
        .focusSection()
    }

    private func mainLeagueRows(_ events: [SportEvent], sport: String, league: String) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.idEvent) { index, event in
                mainFixtureTableRow(event, sport: sport, league: league,
                                    isFirst: index == 0, isLast: index == events.count - 1)
                if index < events.count - 1 { Divider().opacity(0.25) }
            }
        }
    }

    private func mainFixtureTableRow(_ event: SportEvent, sport: String, league: String,
                                     isFirst: Bool, isLast: Bool) -> some View {
        let focusID = "main-fixture-\(sport)-\(league)-\(event.idEvent)"
        let score = fixtures.score(for: event)
        return Button { selectedEvent = event } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        sportBadge(event.homeBadge)
                        Text(event.strHomeTeam ?? "Home")
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    HStack(spacing: 10) {
                        sportBadge(event.awayBadge)
                        Text(event.strAwayTeam ?? "Away")
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(score.home.flatMap { home in score.away.map { "\(home) : \($0)" } } ?? event.timeLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize()
            }
            .font(.system(size: 16, weight: .medium))
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 79)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(SportFrameArtworkButtonStyle())
        .accessibilityLabel("\(event.strHomeTeam ?? "Home") versus \(event.strAwayTeam ?? "Away"), \(event.timeLabel)")
        .focused($focusedCard, equals: focusID)
        .sportFrameFocusOutline(focusedCard == focusID, radius: 10)
        .onMoveCommand { direction in
            guard focusedCard == focusID else { return }
            if (direction == .up && isFirst) || (direction == .down && isLast) {
                focusedCard = "sport-header-\(sport)"
            }
        }
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

    private func sportDetailPage(_ sport: String,
                                 detailFocus: FocusState<String?>.Binding,
                                 focusScope: Namespace.ID,
                                 leagueFilter: Binding<String>) -> some View {
        let allEvents = filteredMatches.filter { fixtures.eventSports[$0.idEvent] == sport }
        let allLeagues = Array(Set(allEvents.map(\.league))).sorted {
            let left = leagueRank($0, sport: sport)
            let right = leagueRank($1, sport: sport)
            return left == right ? $0.localizedStandardCompare($1) == .orderedAscending : left < right
        }
        let events = leagueFilter.wrappedValue == "All Leagues" ? allEvents
            : allEvents.filter { $0.league == leagueFilter.wrappedValue }
        let leagues = allLeagues.filter { leagueFilter.wrappedValue == "All Leagues" || $0 == leagueFilter.wrappedValue }
        let videos = sportHighlights.videos.filter {
            leagueFilter.wrappedValue == "All Leagues" ||
                $0.strLeague?.localizedCaseInsensitiveCompare(leagueFilter.wrappedValue) == .orderedSame
        }
        let featured = events.filter { isLive($0) || $0.isUpcoming }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        let firstFixtureID = leagues.compactMap { league in
            events.filter { $0.league == league }
                .min(by: { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) })?.idEvent
        }.first

        return ZStack {
            SportFrameCinematicBackdrop().ignoresSafeArea()
            ScrollViewReader { detailScroll in
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
                            .font(.system(size: 21, weight: .semibold))
                            .padding(.horizontal, 22).padding(.vertical, 14)
                            .background(.white.opacity(0.09), in: Capsule())
                            .buttonStyle(SportFrameArtworkButtonStyle())
                            .focused(detailFocus, equals: "sport-detail-back")
                            .sportFrameFocusOutline(detailFocus.wrappedValue == "sport-detail-back", radius: 26)
                            .prefersDefaultFocus(in: focusScope)
                    }

                    HStack(spacing: 16) {
                        Text("Filter by league")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(.secondary)
                        Menu {
                            Button("All Leagues") { leagueFilter.wrappedValue = "All Leagues" }
                            ForEach(allLeagues, id: \.self) { league in
                                Button(league) { leagueFilter.wrappedValue = league }
                            }
                        } label: {
                            Label(leagueFilter.wrappedValue, systemImage: "line.3.horizontal.decrease")
                                .font(.system(size: 21, weight: .semibold))
                                .padding(.horizontal, 20).padding(.vertical, 13)
                                .background(.white.opacity(0.09), in: Capsule())
                        }
                        .buttonStyle(SportFrameArtworkButtonStyle())
                        .focused(detailFocus, equals: "sport-detail-league-filter")
                        .sportFrameFocusOutline(detailFocus.wrappedValue == "sport-detail-league-filter", radius: 25)
                        .onMoveCommand { direction in
                            if direction == .up && detailFocus.wrappedValue == "sport-detail-league-filter" {
                                detailFocus.wrappedValue = "sport-detail-back"
                            }
                        }
                        Spacer()
                    }
                    .focusSection()

                    if !featured.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Featured matches").font(.system(size: 30, weight: .semibold))
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 18) {
                                    ForEach(featured) { event in
                                        matchCard(event, focusScope: "detail-\(sport)", inSportDetail: true,
                                                  detailFocus: detailFocus)
                                    }
                                }
                                .padding(.vertical, 12)
                            }
                            .focusSection()
                            .onMoveCommand { direction in
                                if direction == .down, detailFocus.wrappedValue?.hasPrefix("match-detail-") == true {
                                    if let firstHighlight = videos.first {
                                        detailFocus.wrappedValue = "highlight-\(firstHighlight.id)"
                                    } else if firstFixtureID != nil {
                                        moveToDetailFixtureEntry(focus: detailFocus, scroll: detailScroll)
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Yesterday's video highlights")
                            .font(.system(size: 30, weight: .semibold))
                        if sportHighlights.loading {
                            ProgressView("Finding highlights…")
                        } else if videos.isEmpty {
                            Text("No video highlights were found for this league yesterday.")
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 18) {
                                    ForEach(videos) { video in
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
                                        .focused(detailFocus, equals: "highlight-\(video.id)")
                                        .onMoveCommand { direction in
                                            if direction == .down && detailFocus.wrappedValue == "highlight-\(video.id)" {
                                                moveToDetailFixtureEntry(focus: detailFocus, scroll: detailScroll)
                                            }
                                        }
                                        .sportFrameFocusOutline(detailFocus.wrappedValue == "highlight-\(video.id)", radius: 14, outset: 3)
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

                    Button {
                        if let firstFixtureID {
                            moveToDetailFixture(firstFixtureID, focus: detailFocus, scroll: detailScroll)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text(leagueFilter.wrappedValue == "All Leagues" ? "All leagues and fixtures" : "Browse fixtures")
                            Image(systemName: "chevron.down").font(.system(size: 22, weight: .semibold))
                        }
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(SportFrameArtworkButtonStyle())
                    .focused(detailFocus, equals: "sport-detail-fixtures-entry")
                    .sportFrameFocusOutline(detailFocus.wrappedValue == "sport-detail-fixtures-entry", radius: 12)
                    .onMoveCommand { direction in
                        if direction == .down, let firstFixtureID,
                           detailFocus.wrappedValue == "sport-detail-fixtures-entry" {
                            moveToDetailFixture(firstFixtureID, focus: detailFocus, scroll: detailScroll)
                        }
                    }
                    .id("sport-detail-fixtures-entry")
                    .focusSection()

                    if leagueFilter.wrappedValue == "All Leagues" {
                        VStack(alignment: .leading, spacing: 38) {
                            ForEach(leagues, id: \.self) { league in
                                leagueLandscapeSection(league, sport: sport,
                                    events: events.filter { $0.league == league }, focus: detailFocus)
                            }
                        }
                    } else {
                        leagueLandscapeSection(leagueFilter.wrappedValue, sport: sport,
                                               events: events, focus: detailFocus)
                    }
                    if events.isEmpty { emptyPanel("No matches available for this sport on the selected day.") }
                }
                .padding(50)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onMoveCommand { direction in
                guard direction == .down, firstFixtureID != nil else { return }
                let current = detailFocus.wrappedValue ?? ""
                if current == "sport-detail-league-filter" && featured.isEmpty && videos.isEmpty {
                    moveToDetailFixtureEntry(focus: detailFocus, scroll: detailScroll)
                } else if current.hasPrefix("highlight-") {
                    moveToDetailFixtureEntry(focus: detailFocus, scroll: detailScroll)
                }
            }
            }
        }
        .task(id: sport) {
            highlightMessage = nil
            await sportHighlights.fetchYesterday(sport: sport)
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

    private func moveToDetailFixture(_ eventID: String,
                                     focus: FocusState<String?>.Binding,
                                     scroll: ScrollViewProxy) {
        let focusID = "landscape-fixture-\(eventID)"
        withAnimation(.easeOut(duration: 0.2)) {
            scroll.scrollTo(focusID, anchor: .center)
        }
        Task { @MainActor in
            await Task.yield()
            focus.wrappedValue = focusID
        }
    }

    private func moveToDetailFixtureEntry(focus: FocusState<String?>.Binding,
                                          scroll: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            scroll.scrollTo("sport-detail-fixtures-entry", anchor: .center)
        }
        Task { @MainActor in
            await Task.yield()
            focus.wrappedValue = "sport-detail-fixtures-entry"
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

    private func leagueLandscapeSection(_ league: String, sport: String,
                                        events: [SportEvent],
                                        focus: FocusState<String?>.Binding) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                let leagueID = events.compactMap(\.idLeague).first
                let badge = events.compactMap(\.leagueBadge).first ??
                    catalog.badgeURL(for: league, sport: sport, idLeague: leagueID)
                if let badge {
                    AsyncImage(url: badge) { image in image.resizable().scaledToFit() }
                        placeholder: { Image(systemName: sportSymbol(sport)) }
                        .frame(width: 36, height: 36)
                }
                Text("\(league) · Fixtures")
                    .font(.system(size: 30, weight: .semibold))
                Spacer()
                Text("\(events.count) games")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(.white.opacity(0.08), in: Capsule())
            }
            let orderedEvents = events.sorted(by: {
                    ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture)
                })
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4),
                      alignment: .leading, spacing: 16) {
                ForEach(Array(orderedEvents.enumerated()), id: \.element.idEvent) { index, event in
                    landscapeFixtureCard(event, focus: focus,
                                         isFirst: index < 4,
                                         isLast: index >= ((orderedEvents.count - 1) / 4) * 4)
                }
            }
        }
        .focusSection()
    }

    private func landscapeFixtureCard(_ event: SportEvent,
                                      focus: FocusState<String?>.Binding,
                                      isFirst: Bool, isLast: Bool) -> some View {
        let focusID = "landscape-fixture-\(event.idEvent)"
        let score = fixtures.score(for: event)
        return Button { selectedDetailEvent = event } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 9) {
                            sportBadge(event.homeBadge)
                            Text(event.strHomeTeam ?? "Home").lineLimit(2)
                        }
                        HStack(spacing: 9) {
                            sportBadge(event.awayBadge)
                            Text(event.strAwayTeam ?? "Away").lineLimit(2)
                        }
                    }
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 4) {
                        if let home = score.home, let away = score.away {
                            Text("\(home) – \(away)")
                        }
                        Text(event.timeLabel)
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize()
                }
                Divider().overlay(.white.opacity(0.15))
                SportFrameFixtureBroadcasters(eventID: event.idEvent)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(SportFrameArtworkButtonStyle())
        .focused(focus, equals: focusID)
        .id(focusID)
        .sportFrameFocusOutline(focus.wrappedValue == focusID, radius: 15, outset: 3)
        .onMoveCommand { direction in
            guard focus.wrappedValue == focusID else { return }
            if (direction == .up && isFirst) || (direction == .down && isLast) {
                focus.wrappedValue = "sport-detail-fixtures-entry"
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func sportLeagueCard(title: String, sport: String, events: [SportEvent],
                                 showAll: Bool = false, focusScope: String = "",
                                 inSportDetail: Bool = false,
                                 detailFocus: FocusState<String?>.Binding? = nil) -> some View {
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
                .focused(detailFocus ?? $focusedCard,
                         equals: "\(focusScope)league-\(sport)-\(title)-\(event.idEvent)")
                .sportFrameFocusOutline((detailFocus?.wrappedValue ?? focusedCard) == "\(focusScope)league-\(sport)-\(title)-\(event.idEvent)", radius: 9)
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

    private func matchCard(_ event: SportEvent, focusScope: String, inSportDetail: Bool = false,
                           detailFocus: FocusState<String?>.Binding? = nil) -> some View {
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
            .focused(detailFocus ?? $focusedCard, equals: focusID)
            .sportFrameFocusOutline((detailFocus?.wrappedValue ?? focusedCard) == focusID,
                                    radius: 14, outset: inSportDetail ? 3 : 0)
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
        let epgIDs = Set(channelResolver.epgChannelIDs[event.idEvent] ?? [])
        let epgMatches = sportFrameChannels.filter { epgIDs.contains($0.id) }
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
                        SportFrameBroadcasterChannelPicker(eventID: event.idEvent,
                            channels: sportFrameChannels, epgMatches: epgMatches,
                            accent: accent, onPlay: playSportFrameChannel)
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
    @Published private(set) var epgChannelIDs: [String: [String]] = [:]

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
            epgChannelIDs = [:]
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
        let resolved = await Task.detached(priority: .background) { () -> ([String: [String]], [String: [String]], [String: [String]]) in
            let namedChannels = channels.map { (id: $0.id, name: ChannelMatcher.normalize($0.name)) }
            let validIDs = Set(channels.map(\.id))
            var results: [String: [String]] = [:]
            var epgResults: [String: [String]] = [:]
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

                // Secondary: add EPG matches even when broadcaster names matched.
                var epgIDs = Set<String>()
                do {
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
                                epgIDs.insert(channelID)
                            }
                        }
                    }
                }
                ids.formUnion(epgIDs)
                epgResults[event.id] = channels.map(\.id).filter { epgIDs.contains($0) }

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
            return (results, aliases, epgResults)
        }.value
        guard !Task.isCancelled else { return }
        channelIDs = resolved.0
        epgChannelIDs = resolved.2
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

/// Owns focus for the presented sport screen, separate from the main Sports page.
private struct SportFrameDetailFocusHost<Content: View>: View {
    @FocusState private var focusedItem: String?
    @State private var selectedLeague = "All Leagues"
    @Namespace private var scope
    let content: (FocusState<String?>.Binding, Namespace.ID, Binding<String>) -> Content

    var body: some View {
        content($focusedItem, scope, $selectedLeague)
            .focusScope(scope)
            .task {
                await Task.yield()
                focusedItem = "sport-detail-back"
            }
    }
}

private struct SportFrameTVListing: Decodable, Identifiable {
    let id: String
    let strChannel: String?
    let strLogo: String?
    var name: String { strChannel ?? "TV Channel" }
    var logoURL: URL? { strLogo.flatMap(URL.init(string:)) }
}

private struct SportFrameTVListingResponse: Decodable {
    let tvevent: [SportFrameTVListing]?
}

/// Pick a provider broadcaster first, then show matching playlist channels.
/// EPG matches stay separate and are always added below the provider results.
private struct SportFrameBroadcasterChannelPicker: View {
    let eventID: String
    let channels: [UnifiedChannel]
    let epgMatches: [UnifiedChannel]
    let accent: Color
    let onPlay: (UnifiedChannel) -> Void

    @State private var listings: [SportFrameTVListing] = []
    @State private var selectedName: String?
    @State private var loading = true

    private var broadcasterMatches: [UnifiedChannel] {
        guard let selectedName else { return [] }
        let name = ChannelMatcher.normalize(selectedName)
        guard name.count >= 3 else { return [] }
        return channels.filter { channel in
            let candidate = ChannelMatcher.normalize(channel.name)
            return (" " + candidate + " ").contains(" " + name + " ")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TheSportsDB broadcasters").font(.title3.bold())
            if loading {
                ProgressView("Loading broadcaster list…")
            } else if listings.isEmpty {
                Text("No broadcasters listed for this match.").foregroundStyle(.secondary)
            } else {
                Text("Select a broadcaster to find its channels in your Live TV playlist.")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(listings) { listing in
                    Button { selectedName = listing.name } label: {
                        HStack(spacing: 14) {
                            AsyncImage(url: listing.logoURL) { image in image.resizable().scaledToFit() }
                                placeholder: { Image(systemName: "tv") }
                                .frame(width: 62, height: 40)
                            Text(listing.name).font(.headline)
                            Spacer()
                            if selectedName == listing.name { Image(systemName: "checkmark.circle.fill") }
                        }
                        .padding(13)
                        .sportFrameGlassPanel(radius: 12)
                    }
                    .buttonStyle(SportFrameArtworkButtonStyle())
                }
            }

            if let selectedName {
                Text("Playlist channels matching \(selectedName)").font(.headline)
                if broadcasterMatches.isEmpty {
                    Text("No playlist channels match this broadcaster name.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(broadcasterMatches) { channel in
                        SportFrameMatchChannelRow(channel: channel, accent: accent) { onPlay(channel) }
                    }
                }
            }

            Text("More matches from your IPTV guide").font(.title3.bold())
            if epgMatches.isEmpty {
                Text("No extra channels found by match name in the guide.")
                    .foregroundStyle(.secondary)
            } else {
                let seen = Set(broadcasterMatches.map(\.id))
                ForEach(epgMatches.filter { !seen.contains($0.id) }) { channel in
                    SportFrameMatchChannelRow(channel: channel, accent: accent) { onPlay(channel) }
                }
            }
        }
        .task(id: eventID) {
            listings = []
            selectedName = nil
            loading = true
            defer { loading = false }
            guard let url = URL(string: "https://www.thesportsdb.com/api/v1/json/\(SportsDBAccess.apiKey)/lookuptv.php?id=\(eventID)") else { return }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 8
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                let rows = try JSONDecoder().decode(SportFrameTVListingResponse.self, from: data).tvevent ?? []
                var names = Set<String>()
                listings = rows.filter { names.insert(ChannelMatcher.normalize($0.name)).inserted }
            } catch { /* Empty state explains missing provider listings. */ }
        }
    }
}

/// TheSportsDB listings are kept only in each visible card's short-lived view state.
/// There is no saved event-to-broadcaster map.
private struct SportFrameFixtureBroadcasters: View {
    let eventID: String
    @State private var listings: [SportFrameTVListing] = []
    @State private var loading = true
    @State private var loaded = false

    var body: some View {
        HStack(spacing: 18) {
            if loading {
                ProgressView().controlSize(.small)
                Text("Checking TV listings…").foregroundStyle(.secondary)
            } else if listings.isEmpty {
                Image(systemName: "tv")
                Text("No broadcasters listed yet").foregroundStyle(.secondary)
            } else {
                ForEach(Array(listings.prefix(3))) { listing in
                    HStack(spacing: 8) {
                        if let logo = listing.logoURL {
                            AsyncImage(url: logo) { image in image.resizable().scaledToFit() }
                                placeholder: { Image(systemName: "tv") }
                                .frame(width: 48, height: 27)
                        }
                        Text(listing.name).font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                    }
                }
                if listings.count > 3 {
                    Text("+\(listings.count - 3)").foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 15))
        .frame(height: 31, alignment: .leading)
        .task(id: eventID) {
            guard !loaded else { return }
            guard let url = URL(string: "https://www.thesportsdb.com/api/v1/json/\(SportsDBAccess.apiKey)/lookuptv.php?id=\(eventID)") else {
                loading = false
                loaded = true
                return
            }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 8
                let (data, response) = try await URLSession.shared.data(for: request)
                if !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200 {
                    let rows = try JSONDecoder().decode(SportFrameTVListingResponse.self, from: data).tvevent ?? []
                    var names = Set<String>()
                    listings = rows.filter {
                        names.insert(ChannelMatcher.normalize($0.name)).inserted
                    }
                }
            } catch {
                // Show a clear empty state when the provider has no usable listing.
            }
            guard !Task.isCancelled else { return }
            loading = false
            loaded = true
        }
    }
}

private struct SportFrameVideoHighlight: Decodable, Identifiable {
    let idEvent: String?
    let strEvent: String?
    let strLeague: String?
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

    func sportFrameFocusOutline(_ focused: Bool, radius: CGFloat = 10, outset: CGFloat = 0) -> some View {
        self
            .focusEffectDisabled()
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(focused ? Color.white.opacity(0.13) : .clear)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(focused ? Color.white.opacity(0.58) : .clear, lineWidth: 1)
                }
                .padding(-outset)
                .allowsHitTesting(false)
            }
    }
}

/// Receives Menu before RootShell can open the app sidebar.
/// The SwiftUI exit handler alone runs too late for this shell's input policy.
private struct SportFrameMenuBackBridge: UIViewRepresentable {
    let isActive: Bool
    let onBack: () -> Void

    @MainActor final class Coordinator: NSObject, MenuBackHandling {
        var isActive = false
        var onBack: (() -> Void)?
        weak var view: UIView?

        func handleMenuBack() -> Bool {
            guard isActive, view?.window?.isKeyWindow == true else { return false }
            onBack?()
            return true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        context.coordinator.view = view
        MenuPressInterceptor.register(context.coordinator)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isActive = isActive
        context.coordinator.onBack = onBack
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        MenuPressInterceptor.resign(coordinator)
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
