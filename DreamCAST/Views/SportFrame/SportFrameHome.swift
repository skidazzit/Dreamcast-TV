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
    @State private var refreshRevision = 0
    @State private var matchSportFilter = "All Sports"
    @State private var matchLeagueFilter = "All Leagues"
    @State private var selectedEvent: SportEvent?
    @FocusState private var focusedCard: String?
    @State private var premiumKeyInput = ""
    @State private var premiumKeySaved = SportsDBAccess.hasPremiumKey
    @State private var credentialRevision = 0
    @State private var credentialMessage: String?

    private let fallbackSports = ["Soccer", "Basketball", "American Football", "Tennis", "Motorsport", "Ice Hockey", "Cricket", "Baseball", "Rugby", "Golf"]
    private let accent = Color(red: 0.0, green: 0.8, blue: 0.94)
    private let panel = Color(white: 0.105)
    private let allSports = "All Sports"
    private let allLeagueFilter = "All Leagues"

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
        event.isLive
    }

    private var filterLeagues: [String] {
        let names = filteredSports.flatMap { allLeagues(for: $0) }
        return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
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
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 52) {
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            navigation("Sports", index: 0, symbol: "sportscourt")
                            navigation("Channels", index: 1, symbol: "tv")
                            navigation("Settings", index: 2, symbol: "gearshape")
                        }
                        .padding(6)
                        .background(Color(white: 0.13), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.13), lineWidth: 1))
                        Spacer()
                    }
                    switch tab {
                    case 0: matchesPage
                    case 1: channelsPage
                    default: setupPage
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 90)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: "\(followedSportsValue)-\(sportOrderValue)-\(dayOffset)-\(credentialRevision)-\(refreshRevision)") {
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
            HStack(spacing: 9) {
                if index == 2 { Image(systemName: symbol) }
                Text(label)
            }
            .font(.system(size: 23, weight: tab == index ? .bold : .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 27)
            .padding(.vertical, 12)
            .background(tab == index ? Color(white: 0.035) : Color.clear, in: Capsule())
        }
        .buttonStyle(SportFrameArtworkButtonStyle())
        .focusEffectDisabled()
        .focused($focusedCard, equals: "nav-\(index)")
        .overlay {
            Capsule()
                .stroke(focusedCard == "nav-\(index)" ? Color.white : Color.clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
    }

    private var matchesPage: some View {
        VStack(alignment: .leading, spacing: 74) {
            HStack(spacing: 16) {
                Menu {
                    Button(allSports) { matchSportFilter = allSports; matchLeagueFilter = allLeagueFilter }
                    ForEach(followedSports, id: \.self) { sport in
                        Button(sport) { matchSportFilter = sport; matchLeagueFilter = allLeagueFilter }
                    }
                } label: { Label(matchSportFilter, systemImage: "sportscourt") }
                .buttonStyle(.bordered)
                Menu {
                    Button(allLeagueFilter) { matchLeagueFilter = allLeagueFilter }
                    ForEach(filterLeagues, id: \.self) { league in
                        Button(league) { matchLeagueFilter = league }
                    }
                } label: { Label(matchLeagueFilter, systemImage: "list.bullet") }
                .buttonStyle(.bordered)
                HStack(spacing: 8) {
                    ForEach(-1...3, id: \.self) { offset in
                        Button(offset == 0 ? "Today" : offset == -1 ? "Yesterday" : "+\(offset)d") { dayOffset = offset }
                            .buttonStyle(.bordered)
                            .tint(dayOffset == offset ? accent : .gray)
                    }
                }
                Spacer()
                Button { refreshRevision += 1 } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.bordered)
                Button { tab = 2 } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.bordered)
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
                let todayUpcoming = filteredMatches.filter { !isLive($0) && ($0.isUpcoming || $0.startDate == nil) }
                matchShelf(todayUpcoming.isEmpty && !followingDayMatches.isEmpty ? "Coming up · Tomorrow" : "Coming up",
                           events: todayUpcoming.isEmpty ? followingDayMatches : todayUpcoming)
                if !filteredMatches.contains(where: { isLive($0) || $0.isUpcoming || $0.startDate == nil }) && followingDayMatches.isEmpty {
                    matchShelf("Recent results", events: filteredMatches.filter { $0.intHomeScore != nil || $0.intAwayScore != nil })
                }
                leagueSummarySection
            }
        }
    }

    private func matchShelf(_ title: String, events: [SportEvent]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 29, weight: .semibold)).foregroundStyle(Color(white: 0.7))
            if events.isEmpty {
                Text(title == "Happening now" ? "No matches marked live by the provider. Use Refresh to check again." :
                     title == "Coming up" ? "No upcoming matches on this date. Choose +1d to see tomorrow's schedule." :
                     "No \(title.lowercased()) matches found.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(events) { event in matchCard(event) }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var leagueSummarySection: some View {
        VStack(alignment: .leading, spacing: 72) {
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
                Text("\(sport) ›")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(Color(white: 0.7))
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(leagues, id: \.self) { league in
                        sportLeagueCard(title: league, sport: sport, events: events.filter { $0.league == league })
                    }
                }
                .padding(.vertical, 8)
            }
            if !events.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(events) { event in matchCard(event) }
                    }
                    .padding(.vertical, 8)
                }
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

    private func sportLeagueCard(title: String, sport: String, events: [SportEvent]) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 9) {
                if let badge = catalog.badgeURL(for: title, sport: sport) {
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
            ForEach(events.prefix(5)) { event in
                Button { selectedEvent = event } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 10) {
                            sportBadge(event.homeBadge)
                            Text(event.strHomeTeam ?? "Home")
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                            Spacer(minLength: 5)
                            Text(event.intHomeScore ?? event.timeLabel)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(white: 0.66))
                        }
                        HStack(alignment: .top, spacing: 10) {
                            sportBadge(event.awayBadge)
                            Text(event.strAwayTeam ?? "Away")
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                            Spacer(minLength: 5)
                            if let awayScore = event.intAwayScore {
                                Text(awayScore)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color(white: 0.66))
                            }
                        }
                    }
                    .font(.system(size: 15))
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .focused($focusedCard, equals: "league-\(title)-\(event.idEvent)")
                .background(focusedCard == "league-\(title)-\(event.idEvent)" ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                Divider().opacity(0.35)
            }
        }
        .padding(20)
        .frame(width: 430, alignment: .topLeading)
        .background(panel, in: RoundedRectangle(cornerRadius: 19))
        .task(id: "badge-\(sport)-\(title)") {
            await catalog.loadBadge(for: title, sport: sport)
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

    private func matchCard(_ event: SportEvent) -> some View {
        let live = isLive(event)
        return VStack(alignment: .leading, spacing: 9) {
            Button { selectedEvent = event } label: {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Text(event.league).font(.caption.bold()).lineLimit(1)
                        Spacer()
                        Text(live ? "● LIVE" : event.isUpcoming ? "SOON" : event.startDate == nil ? "SCHEDULED" : "RESULT")
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(live ? Color.red : Color.blue, in: Capsule())
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 12) {
                        matchBadge(event.homeBadge)
                        Spacer(minLength: 0)
                        Text(event.intHomeScore.map { "\($0) – \(event.intAwayScore ?? "–")" } ?? event.timeLabel)
                            .font(.system(size: 27, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
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
                .frame(width: 330, height: 184)
                .background(LinearGradient(colors: [Color(red: 0.08, green: 0.19, blue: 0.42), Color(red: 0.47, green: 0.08, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(SportFrameArtworkButtonStyle())
            .focusEffectDisabled()
            .focused($focusedCard, equals: "match-\(event.idEvent)")
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(focusedCard == "match-\(event.idEvent)" ? Color.white : Color.clear, lineWidth: 3)
                    .allowsHitTesting(false)
            }
            Text(event.name)
                .font(.system(size: 18, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            let count = ChannelMatcher.matching(event, in: liveTV.channels).count
            Text(count == 0 ? "Find channels" : "\(count) matching channels")
                .font(.system(size: 15)).foregroundStyle(Color(white: 0.48))
        }
        .frame(width: 330, alignment: .topLeading)
    }

    private func matchBadge(_ url: URL?) -> some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: {
            Image(systemName: "shield.fill").foregroundStyle(.white.opacity(0.7))
        }
        .frame(width: 65, height: 65)
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

// A plain tvOS button can draw a large white focus plate over nearby titles.
// This style leaves focus drawing to the artwork outline above.
private struct SportFrameArtworkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}
