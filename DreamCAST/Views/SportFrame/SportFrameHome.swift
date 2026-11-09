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
        dayOffset == 0 ? fixtures.isLive(event) : event.isLive
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
        .sheet(item: $selectedEvent) { event in
            eventChannels(event)
        }
    }

    private func navigation(_ label: String, index: Int, symbol: String) -> some View {
        let focused = focusedCard == "nav-\(index)"
        return Button { tab = index } label: {
            HStack(spacing: 9) {
                if index == 2 { Image(systemName: symbol) }
                Text(label)
            }
            .font(.system(size: 23, weight: tab == index ? .bold : .medium))
            .foregroundStyle(focused ? Color.black : Color.white)
            .padding(.horizontal, 27)
            .padding(.vertical, 12)
            .background(focused ? Color.white : tab == index ? Color.white.opacity(0.17) : Color.clear, in: Capsule())
        }
        .buttonStyle(SportFrameArtworkButtonStyle())
        .focusEffectDisabled()
        .focused($focusedCard, equals: "nav-\(index)")
        .overlay {
            Capsule()
                .stroke(focused ? Color.white : Color.clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .scaleEffect(focused ? 1.045 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: focused)
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
                .buttonStyle(SportFrameGlassControlStyle())
                Menu {
                    Button(allLeagueFilter) { matchLeagueFilter = allLeagueFilter }
                    ForEach(filterLeagues, id: \.self) { league in
                        Button(league) { matchLeagueFilter = league }
                    }
                } label: { Label(matchLeagueFilter, systemImage: "list.bullet") }
                .buttonStyle(SportFrameGlassControlStyle())
                HStack(spacing: 8) {
                    ForEach(-1...3, id: \.self) { offset in
                        Button(offset == 0 ? "Today" : offset == -1 ? "Yesterday" : "+\(offset)d") { dayOffset = offset }
                            .buttonStyle(SportFrameGlassControlStyle(selected: dayOffset == offset))
                    }
                }
                Spacer()
                Button { refreshRevision += 1 } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(SportFrameGlassControlStyle())
                Button { tab = 2 } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(SportFrameGlassControlStyle())
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
                        ForEach(events) { event in matchCard(event) }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
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
                Text("\(sport) ›")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
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
        .sportFrameGlassPanel(radius: 19)
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
            .focusEffectDisabled()
            .focused($focusedCard, equals: "match-\(event.idEvent)")
            .scaleEffect(focusedCard == "match-\(event.idEvent)" ? 1.035 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.82), value: focusedCard == "match-\(event.idEvent)")
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(focusedCard == "match-\(event.idEvent)" ? Color.white : Color.clear, lineWidth: 3)
                    .allowsHitTesting(false)
            }
            .task(id: "palette-\(event.idEvent)") {
                await teamPalettes.prepare(home: event.homeBadge, away: event.awayBadge)
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
                Button("Unselect all") { followedSportsValue = "" }
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
                        .buttonStyle(.plain)
                        Button { expandedSport = expandedSport == sport ? nil : sport } label: {
                            Image(systemName: expandedSport == sport ? "chevron.down" : "chevron.right")
                        }
                        .buttonStyle(SportFrameGlassControlStyle())
                        Button { moveSport(sport, by: -1) } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(SportFrameGlassControlStyle())
                        .disabled(sportOrder.first == sport)
                        Button { moveSport(sport, by: 1) } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(SportFrameGlassControlStyle())
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
            Text(name).font(.headline).fixedSize(horizontal: false, vertical: true)
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
                            Text(channel.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                            Text(channel.groupTitle ?? "Live TV").font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(20)
                    .sportFrameGlassPanel(radius: 16)
                }
                .buttonStyle(.plain)
            }
        }
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
            .buttonStyle(.plain)
            if expandedSettingsSection == key {
                Divider().padding(.horizontal, 24)
                content()
                    .padding(28)
            }
        }
        .sportFrameGlassPanel(radius: 20)
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
                Button("Use Free Access") {
                    SportsDBAccess.remove()
                    premiumKeyInput = ""
                    premiumKeySaved = false
                    credentialRevision += 1
                    credentialMessage = "Premium key removed. Free access is active."
                }
                .buttonStyle(SportFrameGlassControlStyle())
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
            SportFrameCinematicBackdrop().ignoresSafeArea()
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
            .sportFrameGlassPanel(radius: 16)
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
    @FocusState private var isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 19, weight: selected ? .semibold : .medium))
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .padding(.horizontal, 19)
            .padding(.vertical, 12)
            .background(isFocused ? Color.white : Color.white.opacity(selected ? 0.22 : 0.09),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 0 : 0.16), lineWidth: 1)
            }
            .focused($isFocused)
            .focusEffectDisabled()
            .scaleEffect(configuration.isPressed ? 0.96 : isFocused ? 1.06 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isFocused)
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
