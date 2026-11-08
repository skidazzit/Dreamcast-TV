// Sports Hub beta: original tvOS interface built from the user-provided layout reference.
// No third-party artwork, stream links, or unverified match data are bundled.
import SwiftUI

struct SportsHubBetaView: View {
    let onTune: (UnifiedChannel) -> Void
    private enum Section: String, CaseIterable, Identifiable {
        case home = "Home"
        case channels = "Channels"
        case networks = "Networks"
        case multiview = "Multiview"
        case settings = "Settings"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .home: "house"
            case .channels: "tv"
            case .networks: "dot.radiowaves.left.and.right"
            case .multiview: "square.grid.2x2"
            case .settings: "gearshape"
            }
        }
    }

    private enum Sport: String, CaseIterable, Identifiable {
        case football = "Football"
        case basketball = "Basketball"
        case tennis = "Tennis"
        case formulaOne = "Formula 1"
        case hockey = "Hockey"
        case americanFootball = "American football"
        case cricket = "Cricket"
        var id: Self { self }
        var apiName: String {
            switch self {
            case .football: "Soccer"
            case .basketball: "Basketball"
            case .tennis: "Tennis"
            case .formulaOne: "Motorsport"
            case .hockey: "Ice Hockey"
            case .americanFootball: "American Football"
            case .cricket: "Cricket"
            }
        }
        var symbol: String {
            switch self {
            case .football: "soccerball"
            case .basketball: "basketball"
            case .tennis: "tennis.racket"
            case .formulaOne: "flag.checkered"
            case .hockey: "hockey.puck"
            case .americanFootball: "american.football"
            case .cricket: "figure.cricket"
            }
        }
    }

    private enum SportTab: String, CaseIterable, Identifiable {
        case watch = "Watch"
        case scores = "Scores"
        case standings = "Standings"
        var id: Self { self }
    }

    @StateObject private var liveTV = LiveTVDataStore.shared
    @StateObject private var scorePoller = ScoreboardPoller.shared
    @StateObject private var sportsDB = SportsDBScheduleModel()
    @State private var scoreSubscription: ScoreboardPoller.Subscription?
    @State private var section: Section = .home
    @State private var sport: Sport = .football
    @State private var sportTab: SportTab = .watch
    @State private var channelChoices: ChannelChoices?
    @State private var matchingBroadcasts = false

    private struct ChannelChoices: Identifiable {
        var id = UUID()
        let title: String
        let exact: [UnifiedChannel]
        let possible: [UnifiedChannel]
        let other: [UnifiedChannel]
        var nameMatches: [UnifiedChannel] = []
        var broadcastNames: [String] = []
        var lookupMessage: String? = nil
    }

    @State private var selectedDay = 1
    @State private var selectedLeague = "All leagues"
    @State private var premiumKeyDraft = ""
    @State private var premiumConfigured = false
    @State private var premiumMessage: String?

    private let background = Color(red: 0.035, green: 0.038, blue: 0.045)
    private let surface = Color(red: 0.095, green: 0.1, blue: 0.115)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack {
                        Text("SPORTS HUB")
                            .font(.system(size: 25, weight: .black, design: .rounded))
                            .tracking(2)
                        Spacer()
                        Text("DreamCAST beta").foregroundStyle(.secondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Section.allCases) { item in
                                Button { section = item } label: {
                                    Label(item.rawValue, systemImage: item.symbol)
                                        .font(.headline)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(.bordered)
                                .tint(section == item ? .white : .gray)
                            }
                        }
                    }

                    switch section {
                    case .home:
                        homeContent
                    case .channels:
                        channelsContent
                    case .networks:
                        networksContent
                    case .multiview:
                        multiviewContent
                    case .settings:
                        settingsContent
                    }
                }
                .padding(64)
                .frame(maxWidth: 1900, alignment: .leading)
            }
        }
        .onAppear {
            if scoreSubscription == nil { scoreSubscription = scorePoller.subscribe() }
            loadSportsDB()
            premiumConfigured = SportsDBPremiumKeyStore.read() != nil
        }
        .onDisappear { scoreSubscription = nil }
        .onChange(of: selectedDay) { _, _ in
            selectedLeague = "All leagues"
            loadSportsDB()
        }
        .onChange(of: sport) { _, _ in
            selectedLeague = "All leagues"
            loadSportsDB()
        }
        .sheet(item: $channelChoices) { choices in
            channelPicker(choices)
        }
    }



    private var chosenDate: Date {
        Calendar.current.date(byAdding: .day, value: selectedDay - 1, to: Date()) ?? Date()
    }

    private func loadSportsDB() {
        sportsDB.load(date: chosenDate, sport: sport.apiName)
    }

    private func matchesSelectedSport(_ event: SportsDBEvent) -> Bool {
        let name = event.sport.lowercased()
        let league = event.league.lowercased()
        switch sport {
        case .football: return name == "soccer"
        case .basketball: return name == "basketball"
        case .tennis: return name == "tennis"
        case .formulaOne: return name.contains("motor") || league.contains("formula")
        case .hockey: return name == "ice hockey" || name == "hockey"
        case .americanFootball: return name == "american football"
        case .cricket: return name == "cricket"
        }
    }

    private func normalizedChannelName(_ name: String) -> String {
        let cleaned = name.lowercased().unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        }
        return String(cleaned).split(whereSeparator: { $0.isWhitespace })
            .filter { !["hd", "fhd", "uhd", "4k", "50fps", "60fps", "tv", "channel"].contains(String($0)) }
            .joined(separator: " ")
    }

    private func channelMatchesBroadcast(_ channel: UnifiedChannel, names: [String]) -> Bool {
        let local = normalizedChannelName(channel.name)
        guard local.count >= 4 else { return false }
        return names.contains { name in
            let broadcast = normalizedChannelName(name)
            return broadcast.count >= 4 && (local == broadcast ||
                local.contains(broadcast) || broadcast.contains(local))
        }
    }

    private func channelMatchesTeams(_ channel: UnifiedChannel, home: String?, away: String?) -> Bool {
        guard let home, let away else { return false }
        let local = normalizedChannelName(channel.name)
        let ignored = Set(["united", "city", "football", "club", "sporting", "athletic", "real", "inter"])
        func matchesTeam(_ team: String) -> Bool {
            let normalized = normalizedChannelName(team)
            guard !normalized.isEmpty else { return false }
            if local.contains(normalized) { return true }
            let significant = normalized.split(separator: " ").map { String($0) }
                .filter { $0.count >= 5 && !ignored.contains($0) }
            return significant.contains { token in
                local.split(separator: " ").contains(Substring(token))
            }
        }
        return matchesTeam(home) && matchesTeam(away)
    }

    private func presentSportsDBChannels(_ event: SportsDBEvent) {
        let teamNames = [event.strHomeTeam, event.strAwayTeam]
            .compactMap { $0?.lowercased() }
            .filter { $0.count >= 4 }
        let exact = liveTV.channels.filter { channel in
            liveTV.epg[channel.id]?.contains(where: { program in
                let title = [program.title, program.subtitle ?? ""].joined(separator: " ").lowercased()
                guard teamNames.count == 2, teamNames.allSatisfy({ title.contains($0) }) else { return false }
                guard let start = event.startTime else { return true }
                return abs(program.eventStart.timeIntervalSince(start)) < 4 * 3600
            }) == true
        }
        let exactIDs = Set(exact.map(\.id))
        let nameMatches = liveTV.channels.filter { channel in
            !exactIDs.contains(channel.id) && channelMatchesTeams(channel, home: event.strHomeTeam, away: event.strAwayTeam)
        }
        let requestID = UUID()
        channelChoices = ChannelChoices(id: requestID, title: event.title,
                                        exact: exact, possible: [], other: [], nameMatches: nameMatches,
                                        lookupMessage: "Checking TheSportsDB TV broadcasts…")
        matchingBroadcasts = true
        Task {
            let names: [String]
            let note: String
            do {
                names = try await SportsDBScheduleClient.shared.broadcastChannels(eventID: event.idEvent)
                note = names.isEmpty
                    ? "TheSportsDB has no TV broadcasts listed for this match."
                    : "Matched TheSportsDB broadcasts against your Live TV playlist."
            } catch {
                names = []
                note = "TheSportsDB TV lookup failed. Showing EPG and channel-name matches."
            }
            guard channelChoices?.id == requestID else { return }
            let usedIDs = exactIDs.union(nameMatches.map(\.id))
            let possible = liveTV.channels.filter { channel in
                !usedIDs.contains(channel.id) && channelMatchesBroadcast(channel, names: names)
            }
            channelChoices = ChannelChoices(id: requestID, title: event.title,
                                            exact: exact, possible: possible, other: [],
                                            nameMatches: nameMatches, broadcastNames: names, lookupMessage: note)
            matchingBroadcasts = false
        }
    }

    private func presentGameChannels(_ game: ScoreGame) {
        let exact = liveTV.channels.filter { channel in
            liveTV.epg[channel.id]?.contains(where: { GameMatcher.matches($0, game) }) == true
        }
        let networkNames = (game.network ?? "")
            .split(whereSeparator: { $0 == "/" || $0 == "," || $0 == "&" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count >= 3 }
        let exactIDs = Set(exact.map(\.id))
        let nameMatches = liveTV.channels.filter { channel in
            !exactIDs.contains(channel.id) &&
            channelMatchesTeams(channel, home: game.home.name, away: game.away.name)
        }
        let usedIDs = exactIDs.union(nameMatches.map(\.id))
        let possible = liveTV.channels.filter { channel in
            guard !usedIDs.contains(channel.id) else { return false }
            let name = normalizedChannelName(channel.name)
            return networkNames.contains { network in
                let expected = normalizedChannelName(network)
                return expected.count >= 4 && (name == expected ||
                    name.contains(expected) || expected.contains(name))
            }
        }
        channelChoices = ChannelChoices(
            title: "\(game.away.name) vs \(game.home.name)",
            exact: exact, possible: possible, other: [], nameMatches: nameMatches
        )
    }

    private func presentEventChannels(_ event: UnifiedProgram, original: UnifiedChannel) {
        let exact = liveTV.channels.filter { channel in
            liveTV.epg[channel.id]?.contains(where: { program in
                program.displayTitle.localizedCaseInsensitiveCompare(event.displayTitle) == .orderedSame
                    && abs(program.eventStart.timeIntervalSince(event.eventStart)) < 3600
            }) == true
        }
        let confirmed = exact.isEmpty ? [original] : exact
        channelChoices = ChannelChoices(
            title: event.displayTitle,
            exact: confirmed,
            possible: [],
            other: []
        )
    }

    private func channelPicker(_ choices: ChannelChoices) -> some View {
        ZStack {
            background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Choose a channel").font(.largeTitle.bold())
                            Text(choices.title).font(.title3).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Close") { channelChoices = nil }
                            .buttonStyle(.bordered)
                    }
                    if matchingBroadcasts {
                        ProgressView("Looking up broadcast channels…")
                    }
                    if let note = choices.lookupMessage {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                    if !choices.broadcastNames.isEmpty {
                        Text("Networks listed by TheSportsDB: " + choices.broadcastNames.joined(separator: ", "))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !matchingBroadcasts && choices.exact.isEmpty && choices.nameMatches.isEmpty && choices.possible.isEmpty && choices.other.isEmpty {
                        Text("No matching channels were found in your Live TV playlists.")
                            .foregroundStyle(.secondary)
                    }
                    channelPickerGroup("EPG matches", channels: choices.exact,
                                       note: "These channels list the selected game in their guide.")
                    channelPickerGroup("Channel-name matches", channels: choices.nameMatches,
                                       note: "Both teams appear in the channel name. Confirm the stream before watching.")
                    channelPickerGroup("Broadcast network matches", channels: choices.possible,
                                       note: "These channel names match the game's reported networks.")
                    channelPickerGroup("Other sports channels", channels: choices.other,
                                       note: "These are suggestions. Their schedules may differ.")
                }
                .padding(60)
                .frame(maxWidth: 1500, alignment: .leading)
            }
        }
    }

    private func channelPickerGroup(_ name: String, channels: [UnifiedChannel], note: String) -> some View {
        Group {
            if !channels.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(name) (\(channels.count))").font(.title2.bold())
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                        ForEach(channels) { channel in
                            Button {
                                channelChoices = nil
                                onTune(channel)
                            } label: {
                                HStack(spacing: 16) {
                                    AsyncImage(url: channel.logoURL) { image in
                                        image.resizable().scaledToFit()
                                    } placeholder: {
                                        Image(systemName: "tv").foregroundStyle(.secondary)
                                    }
                                    .frame(width: 72, height: 52)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(channel.name).font(.headline).lineLimit(2)
                                        Text(channel.groupTitle ?? "Live TV")
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "play.fill").foregroundStyle(.secondary)
                                }
                                .padding(14)
                                .background(surface, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var favouriteChannels: some View {
        let favorites = liveTV.channels.filter {
            liveTV.favoriteIds.contains($0.id) || $0.isFavourite
        }
        return Group {
            if favorites.isEmpty {
                emptyShelf("Mark channels as favourites in Live TV to see them here.", symbol: "star")
            } else {
                channelGrid(Array(favorites.prefix(12)))
            }
        }
    }

    private var liveEvents: some View {
        let now = Date()
        let upcoming: [(UnifiedChannel, UnifiedProgram)] = liveTV.channels.compactMap { channel in
            guard let programs = liveTV.epg[channel.id] else { return nil }
            guard let program = programs.first(where: {
                $0.endTime > now && $0.startTime < now.addingTimeInterval(24 * 3600)
                    && isSportsProgram($0)
            }) else { return nil }
            return (channel, program)
        }
        return Group {
            if upcoming.isEmpty {
                emptyShelf("No sports events found in the loaded TV guide.", symbol: "play.tv")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                    ForEach(0..<min(upcoming.count, 16), id: \.self) { index in
                        let pair = upcoming[index]
                        Button {
                            presentEventChannels(pair.1, original: pair.0)
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                            Text(pair.1.isLiveAiring ? "LIVE" : pair.1.startTime.formatted(date: .omitted, time: .shortened))
                                .font(.caption.bold())
                                .foregroundColor(pair.1.isLiveAiring ? .red : .gray)
                            Text(pair.1.displayTitle)
                                .font(.headline)
                                .lineLimit(2)
                            Text(pair.0.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
                        .padding(16)
                        .background(surface, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func isSportsProgram(_ program: UnifiedProgram) -> Bool {
        let text = [program.title, program.category ?? "", program.subtitle ?? ""]
            .joined(separator: " ").lowercased()
        return ["sport", "football", "soccer", "basketball", "baseball", "hockey",
                "tennis", "formula", "racing", "cricket", "nfl", "nba", "mlb", "nhl",
                "grand prix", "champions league", "premier league"].contains {
            text.contains($0)
        }
    }

    private var availableLeagues: [String] {
        Array(Set(sportsDB.events.map(\.league)))
            .filter { !$0.isEmpty && $0 != "Sport" }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var leaguePicker: some View {
        HStack(spacing: 18) {
            Text("League").font(.headline)
            Menu {
                Button("All leagues") { selectedLeague = "All leagues" }
                ForEach(availableLeagues, id: \.self) { league in
                    Button(league) { selectedLeague = league }
                }
            } label: {
                Label(selectedLeague, systemImage: "line.3.horizontal.decrease.circle")
                    .font(.headline)
                    .lineLimit(1)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            Spacer()
            Text("\(availableLeagues.count) leagues")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var sportsDBSchedule: some View {
        Group {
            if sportsDB.isLoading {
                ProgressView("Loading match schedule…")
            } else if let error = sportsDB.errorMessage {
                emptyShelf(error, symbol: "wifi.exclamationmark")
            } else {
                let matches = sportsDB.events.filter {
                    matchesSelectedSport($0) && (selectedLeague == "All leagues" || $0.league == selectedLeague)
                }
                leaguePicker
                if matches.isEmpty {
                    emptyShelf("No matches returned for this sport and date by TheSportsDB.", symbol: "calendar")
                } else {
                    Text("\(matches.count) matches in \(selectedLeague == "All leagues" ? sport.rawValue : selectedLeague)")
                        .font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                        ForEach(Array(matches.prefix(24))) { event in
                            Button { presentSportsDBChannels(event) } label: {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack(spacing: 10) {
                                        SportsDBArtworkBadge(kind: .league, recordID: event.idLeague, provided: event.leagueBadge, size: 34)
                                        Text(event.league).font(.caption).lineLimit(1)
                                        Spacer()
                                        if let start = event.startTime {
                                            Text(start, format: .dateTime.hour().minute())
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    HStack(spacing: 12) {
                                        SportsDBArtworkBadge(kind: .team, recordID: event.idHomeTeam, provided: event.homeBadge, size: 48)
                                        Text(event.strHomeTeam ?? "Home").lineLimit(2)
                                        Spacer(minLength: 8)
                                        if let score = event.intHomeScore {
                                            Text(score).font(.title3.bold())
                                        }
                                    }
                                    HStack(spacing: 12) {
                                        SportsDBArtworkBadge(kind: .team, recordID: event.idAwayTeam, provided: event.awayBadge, size: 48)
                                        Text(event.strAwayTeam ?? "Away").lineLimit(2)
                                        Spacer(minLength: 8)
                                        if let score = event.intAwayScore {
                                            Text(score).font(.title3.bold())
                                        }
                                    }
                                    Text(event.strStatus ?? "Match details")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    Label("Choose channel", systemImage: "list.bullet")
                                        .font(.caption.bold()).foregroundStyle(.cyan)
                                }
                                .font(.headline)
                                .padding(20)
                                .frame(maxWidth: .infinity, minHeight: 195, alignment: .leading)
                                .background(surface, in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var scoreLeague: League? {
        switch sport {
        case .basketball: .nba
        case .hockey: .nhl
        case .americanFootball: .nfl
        default: nil
        }
    }

    private var scoreCards: some View {
        Group {
            if selectedDay != 1 {
                emptyShelf("The current score feed covers today's games.", symbol: "calendar")
            } else if let league = scoreLeague, let board = scorePoller.boards[league] {
                if board.games.isEmpty {
                    emptyShelf("No \(league.title) games in today's feed.", symbol: "sportscourt")
                } else {
                    let now = Date()
                    let airing = GameMatcher.channels(
                        airing: board.games,
                        channels: liveTV.channels,
                        current: { channel in
                            liveTV.epg[channel.id]?.first(where: {
                                $0.startTime <= now && $0.endTime > now
                            })
                        }
                    )
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                        ForEach(board.games) { game in
                            VStack(alignment: .leading, spacing: 14) {
                                Text(game.detail).font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Text(game.away.short).lineLimit(1)
                                    Spacer()
                                    Text(game.away.score.map { String($0) } ?? "–")
                                }
                                HStack {
                                    Text(game.home.short).lineLimit(1)
                                    Spacer()
                                    Text(game.home.score.map { String($0) } ?? "–")
                                }
                                if let channel = airing[game.id] {
                                    Text("EPG match: \(channel.name)")
                                        .font(.caption).foregroundStyle(.green)
                                } else {
                                    Text(game.network ?? "No confirmed channel")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Button {
                                    presentGameChannels(game)
                                } label: {
                                    Label("Choose channel", systemImage: "list.bullet")
                                        .font(.caption.bold())
                                }
                                .buttonStyle(.bordered)
                                .tint(.cyan)
                            }
                            .font(.headline)
                            .padding(20)
                            .frame(maxWidth: .infinity, minHeight: 170)
                            .background(surface, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            } else if scoreLeague == nil {
                emptyShelf("This sport needs a match-results provider.", symbol: "sportscourt")
            } else {
                ProgressView("Loading verified scores…")
            }
        }
    }

    private var networksContent: some View {
        let channels = liveTV.channels.filter {
            let value = [ $0.name, $0.groupTitle ?? "" ].joined(separator: " ").lowercased()
            return ["sport", "espn", "tnt", "nba", "nfl", "mlb", "nhl", "formula", "f1"].contains { value.contains($0) }
        }
        return VStack(alignment: .leading, spacing: 24) {
            Text("Sports networks").font(.title.bold())
            if channels.isEmpty {
                emptyShelf("No sports networks found in your Live TV channels.", symbol: "tv")
            } else {
                channelGrid(Array(channels.prefix(60)))
            }
        }
    }

    private func channelGrid(_ channels: [UnifiedChannel]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 5), spacing: 16) {
            ForEach(channels) { channel in
                Button {
                    onTune(channel)
                } label: {
                VStack(alignment: .leading, spacing: 12) {
                    AsyncImage(url: channel.logoURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "tv").font(.largeTitle).foregroundStyle(.secondary)
                    }
                    .frame(height: 75)
                    .frame(maxWidth: .infinity)
                    Text(channel.name).font(.headline).lineLimit(2)
                    Text(channel.groupTitle ?? "Live TV")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 160)
                .background(surface, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text("Favourite channels").font(.title2.bold())
            favouriteChannels

            Text("Live events").font(.title2.bold())
            liveEvents

            Text("Sports").font(.title2.bold())
            sportPicker
            sportContent
        }
    }

    private var sportPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Sport.allCases) { item in
                    Button {
                        sport = item
                        sportTab = .watch
                    } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(item == sport ? .white : .gray)
                }
            }
        }
    }

    private var sportContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 30) {
                Text(sport.rawValue).font(.title.bold())
                Spacer()
                ForEach(SportTab.allCases) { item in
                    Button(item.rawValue) { sportTab = item }
                        .buttonStyle(.bordered)
                        .tint(sportTab == item ? .white : .gray)
                }
            }
            if sportTab == .watch {
                datePicker
                sportsDBSchedule
            } else if sportTab == .scores {
                datePicker
                scoreCards
                Text("More match results from TheSportsDB").font(.title3.bold())
                sportsDBSchedule
            } else {
                emptyShelf("League tables and rankings will appear here.", symbol: "list.number")
            }
        }
    }

    private var datePicker: some View {
        HStack(spacing: 14) {
            ForEach(0..<5, id: \.self) { day in
                Button {
                    selectedDay = day
                } label: {
                    VStack(spacing: 7) {
                        Text(day == 0 ? "Yesterday" : day == 1 ? "Today" : day == 2 ? "Tomorrow" : "Day +\(day - 1)")
                            .font(.caption)
                        Text(Calendar.current.date(byAdding: .day, value: day - 1, to: Date()) ?? Date(),
                             format: .dateTime.day().month(.abbreviated))
                            .font(.headline)
                    }
                    .frame(minWidth: 135, minHeight: 75)
                }
                .buttonStyle(.bordered)
                .tint(selectedDay == day ? .white : .gray)
            }
        }
    }

    private var channelsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Channels").font(.title.bold())
            datePicker
            liveEvents
            Text("Match schedule").font(.title2.bold())
            sportPicker
            sportsDBSchedule
            Text("This view will add the Sportset-style sports filter and timeline.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var multiviewContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Multiview").font(.title.bold())
            Text("Four-view layout").foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(0..<4, id: \.self) { slot in
                    RoundedRectangle(cornerRadius: 18)
                        .fill(surface)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: "plus.circle").font(.largeTitle)
                                Text("Channel \(slot + 1)")
                            }
                            .foregroundStyle(.secondary)
                        }
                }
            }
            Text("Playback slots remain inactive until resource use is tested on Apple TV.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func savePremiumKey() {
        let candidate = premiumKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate != "123", !candidate.isEmpty,
              candidate.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            premiumMessage = "Enter your numeric Premium API key from TheSportsDB profile."
            return
        }
        if SportsDBPremiumKeyStore.save(candidate) {
            premiumConfigured = true
            premiumKeyDraft = ""
            premiumMessage = "Key saved on this device. Refreshing matches…"
            sportsDB.load(date: chosenDate, sport: sport.apiName, forceRefresh: true)
        } else {
            premiumMessage = "Could not save the key on this device."
        }
    }

    private func removePremiumKey() {
        if SportsDBPremiumKeyStore.save(nil) {
            premiumConfigured = false
            premiumKeyDraft = ""
            premiumMessage = "Premium key removed. Using the free feed."
            sportsDB.load(date: chosenDate, sport: sport.apiName, forceRefresh: true)
        } else {
            premiumMessage = "Could not remove the key from this device."
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Sports Hub Settings").font(.title.bold())
            HStack {
                Text("Default league")
                Spacer()
                Text(selectedLeague).foregroundStyle(.secondary)
            }
            .padding(24)
            .background(surface, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 18) {
                Text("TheSportsDB API").font(.title2.bold())
                Text(premiumConfigured ? "Premium key saved on this device" : "Using free API")
                    .foregroundColor(premiumConfigured ? .green : .gray)
                SecureField("Premium API key", text: $premiumKeyDraft)
                    .textContentType(.password)
                HStack(spacing: 16) {
                    Button("Save Premium key") { savePremiumKey() }
                        .buttonStyle(.borderedProminent)
                    if premiumConfigured {
                        Button("Remove key") { removePremiumKey() }
                            .buttonStyle(.bordered)
                    }
                    Button("Refresh matches") {
                        sportsDB.load(date: chosenDate, sport: sport.apiName, forceRefresh: true)
                        premiumMessage = "Refreshing the match feed…"
                    }
                    .buttonStyle(.bordered)
                }
                if let premiumMessage {
                    Text(premiumMessage).font(.footnote).foregroundStyle(.secondary)
                }
                Text("Find your key in your TheSportsDB account profile. It stays in this device's Keychain.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Last match query: \(sportsDB.loadedCount) events. The feed filters by \(sport.apiName).")
                    .font(.footnote).foregroundStyle(.secondary)
                if let error = sportsDB.errorMessage {
                    Text(error).font(.footnote).foregroundColor(.orange)
                }
                Text("Without a saved Premium key, schedules use the free feed.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
            .background(surface, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func emptyShelf(_ message: String, symbol: String) -> some View {
        HStack(spacing: 20) {
            Image(systemName: symbol).font(.system(size: 35)).foregroundStyle(.secondary)
            Text(message).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(minHeight: 130)
        .padding(24)
        .background(surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func emptyContent(_ title: String, description: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title).font(.title.bold())
            emptyShelf(description, symbol: symbol)
        }
    }
}

private struct SportsDBArtworkBadge: View {
    enum Kind { case team, league }
    let kind: Kind
    let recordID: String?
    let provided: URL?
    let size: CGFloat

    @State private var fallback: URL?
    @State private var attempted = false

    var body: some View {
        AsyncImage(url: fallback ?? provided) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .failure:
                placeholder
                    .task { await recoverBadge() }
            case .empty:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .frame(width: size, height: size)
        .task(id: recordID) {
            fallback = nil
            attempted = false
            if provided == nil { await recoverBadge() }
        }
    }

    private var placeholder: some View {
        Image(systemName: kind == .team ? "shield" : "sportscourt")
            .resizable().scaledToFit().foregroundStyle(.secondary)
    }

    @MainActor
    private func recoverBadge() async {
        guard !attempted, let recordID else { return }
        attempted = true
        switch kind {
        case .team:
            fallback = await SportsDBScheduleClient.shared.teamBadge(id: recordID)
        case .league:
            fallback = await SportsDBScheduleClient.shared.leagueBadge(id: recordID)
        }
    }
}
