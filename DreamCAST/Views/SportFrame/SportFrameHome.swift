import SwiftUI

struct SportFrameHome: View {
    let onTune: (UnifiedChannel) -> Void
    @StateObject private var fixtures = FixtureStore()
    @StateObject private var catalog = SportFrameCatalog()
    @StateObject private var liveTV = LiveTVDataStore.shared
    @State private var tab = 0
    @AppStorage("sportFrameFollowedSportsV2") private var followedSportsValue = "Soccer|Basketball|American Football"
    @AppStorage("sportFrameSportOrderV2") private var sportOrderValue = "Soccer|Basketball|American Football|Tennis|Motorsport|Ice Hockey|Cricket"
    @AppStorage("sportFrameLeagueSelectionsV2") private var leagueSelectionsValue = "{}"
    @State private var expandedSport: String?
    @State private var expandedSettingsSection: String?
    @State private var dayOffset = 0
    @State private var selectedEvent: SportEvent?
    @State private var premiumKeyInput = ""
    @State private var premiumKeySaved = SportsDBAccess.hasPremiumKey
    @State private var credentialRevision = 0
    @State private var credentialMessage: String?

    private let fallbackSports = ["Soccer", "Basketball", "American Football", "Tennis", "Motorsport", "Ice Hockey", "Cricket", "Baseball", "Rugby", "Golf"]
    private let accent = Color(red: 0.0, green: 0.8, blue: 0.94)
    private let panel = Color(red: 0.095, green: 0.11, blue: 0.15)

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
            Color(red: 0.025, green: 0.03, blue: 0.05).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    HStack {
                        Image(systemName: "sportscourt.fill").foregroundStyle(accent)
                        Text("SPORTFRAME TV").font(.system(size: 34, weight: .black, design: .rounded))
                        Spacer()
                        Text("DreamCAST sports").foregroundStyle(.secondary)
                    }
                    HStack(spacing: 16) {
                        navigation("Matches", index: 0, symbol: "calendar")
                        navigation("Channels", index: 1, symbol: "tv")
                        navigation("Setup", index: 2, symbol: "gearshape")
                    }
                    switch tab {
                    case 0: matchesPage
                    case 1: channelsPage
                    default: setupPage
                    }
                }
                .padding(65)
                .frame(maxWidth: 1900, alignment: .leading)
            }
        }
        .task(id: "\(followedSportsValue)-\(sportOrderValue)-\(dayOffset)-\(credentialRevision)") {
            await fixtures.fetch(sports: followedSports, date: Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date())
        }
        .task(id: credentialRevision) {
            await catalog.refresh()
        }
        .sheet(item: $selectedEvent) { event in
            eventChannels(event)
        }
    }

    private func navigation(_ label: String, index: Int, symbol: String) -> some View {
        Button { tab = index } label: {
            Label(label, systemImage: symbol)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .tint(tab == index ? accent : .gray)
    }

    private var matchesPage: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("Sports schedule").font(.largeTitle.bold())
            Text("\(followedSports.count) sports followed · arranged in your chosen order")
                .font(.title3).foregroundStyle(.secondary)
            Button("Choose sports and leagues in Setup") { tab = 2 }
                .buttonStyle(.bordered)
            HStack(spacing: 18) {
                ForEach(-1...3, id: \.self) { offset in
                    Button(offset == 0 ? "Today" : offset == -1 ? "Yesterday" : "Day +\(offset)") {
                        dayOffset = offset
                    }
                    .buttonStyle(.bordered)
                    .tint(dayOffset == offset ? accent : .gray)
                }
            }
            if followedSports.isEmpty {
                emptyPanel("Choose at least one sport in Setup to see games.")
            } else if fixtures.loading {
                ProgressView("Loading matches…")
            } else if let error = fixtures.error {
                Text(error).foregroundStyle(.orange)
            } else if fixtures.events.isEmpty {
                emptyPanel("No events returned for the selected sports and day.")
            } else {
                ForEach(followedSports, id: \.self) { sport in
                    let sportMatches = matches(in: sport)
                    VStack(alignment: .leading, spacing: 16) {
                        Text(sport).font(.title.bold())
                        Text("\(sportMatches.count) matches")
                            .font(.caption).foregroundStyle(.secondary)
                        if sportMatches.isEmpty {
                            emptyPanel("No games found for the chosen leagues on this day.")
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3), spacing: 18) {
                                ForEach(sportMatches) { event in matchCard(event) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func matchCard(_ event: SportEvent) -> some View {
        Button { selectedEvent = event } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(event.league).font(.caption).foregroundStyle(accent)
                    Spacer()
                    Text(event.kickoff).font(.caption).foregroundStyle(.secondary)
                }
                teamRow(name: event.strHomeTeam ?? "Home", badge: event.homeBadge, score: event.intHomeScore)
                teamRow(name: event.strAwayTeam ?? "Away", badge: event.awayBadge, score: event.intAwayScore)
                Text("Find my channels").font(.caption.bold()).foregroundStyle(accent)
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .leading)
            .background(panel, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var sportLeagueSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Choose your sports and leagues. Use the arrows to set the order shown on Matches.")
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button("Select all") { followedSportsValue = sportOrder.joined(separator: "|") }
                Button("Unselect all") { followedSportsValue = "" }
            }
            .buttonStyle(.bordered)
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
                        .buttonStyle(.plain)
                        Button { expandedSport = expandedSport == sport ? nil : sport } label: {
                            Image(systemName: expandedSport == sport ? "chevron.down" : "chevron.right")
                        }
                        .buttonStyle(.bordered)
                        Button { moveSport(sport, by: -1) } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .disabled(sportOrder.first == sport)
                        Button { moveSport(sport, by: 1) } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.bordered)
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
                                Button("Unselect all") {
                                    var choices = leagueSelections
                                    choices[sport] = []
                                    saveLeagueSelections(choices)
                                }
                            }
                            .buttonStyle(.bordered)
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
                                }
                                .buttonStyle(.plain)
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
            Text(name).font(.headline).lineLimit(1)
            Spacer()
            if let score { Text(score).font(.title2.bold()) }
        }
    }

    private var channelsPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("My channels").font(.largeTitle.bold())
            Text("\(liveTV.channels.count) streams loaded from your playlist")
                .foregroundStyle(.secondary)
            if liveTV.channels.isEmpty { emptyPanel("Add a playlist in DreamCAST Live TV.") }
            channelGrid(liveTV.channels)
        }
    }

    private func channelGrid(_ channels: [UnifiedChannel]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 4), spacing: 18) {
            ForEach(channels.prefix(80)) { channel in
                Button { onTune(channel) } label: {
                    HStack(spacing: 16) {
                        AsyncImage(url: channel.logoURL) { image in image.resizable().scaledToFit() } placeholder: {
                            Image(systemName: "tv").foregroundStyle(.secondary)
                        }
                        .frame(width: 68, height: 62)
                        VStack(alignment: .leading) {
                            Text(channel.name).font(.headline).lineLimit(2)
                            Text(channel.groupTitle ?? "Live TV").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(20)
                    .background(panel, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var setupPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("SportFrame Settings").font(.system(size: 42, weight: .bold, design: .rounded))
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
            .buttonStyle(.plain)
            if expandedSettingsSection == key {
                Divider().padding(.horizontal, 24)
                content()
                    .padding(28)
            }
        }
        .background(panel, in: RoundedRectangle(cornerRadius: 20))
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
                .buttonStyle(.borderedProminent)
                Button("Use Free Access") {
                    SportsDBAccess.remove()
                    premiumKeyInput = ""
                    premiumKeySaved = false
                    credentialRevision += 1
                    credentialMessage = "Premium key removed. Free access is active."
                }
                .buttonStyle(.bordered)
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
        VStack(alignment: .leading, spacing: 20) {
            Text("SportFrame uses your existing DreamCAST Live TV playlists.")
                .foregroundStyle(.secondary)
            Text("\(liveTV.channels.count) available channels")
                .font(.title2.bold()).foregroundStyle(accent)
            Text("Add or refresh M3U and Xtream sources in DreamCAST Live TV settings.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Channel playback uses DreamCAST Live TV. Your playlists remain unchanged.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func eventChannels(_ event: SportEvent) -> some View {
        let matches = ChannelMatcher.matching(event, in: liveTV.channels)
        return ZStack {
            Color(red: 0.025, green: 0.03, blue: 0.05).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    HStack {
                        Text(event.name).font(.largeTitle.bold())
                        Spacer()
                        Button("Close") { selectedEvent = nil }
                    }
                    Text("Channels found by matching both team names. The stream is not verified by the EPG.")
                        .foregroundStyle(.secondary)
                    if matches.isEmpty {
                        emptyPanel("No channel names match this fixture. Check Live TV channels or browse them manually.")
                        Button("View all channels") { selectedEvent = nil; tab = 1 }
                    } else {
                        channelGrid(matches)
                    }
                }
                .padding(60)
            }
        }
    }

    private func emptyPanel(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            .padding(25)
            .background(panel, in: RoundedRectangle(cornerRadius: 16))
    }
}
