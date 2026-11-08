import SwiftUI

struct SportFrameHome: View {
    let onTune: (UnifiedChannel) -> Void
    @StateObject private var fixtures = FixtureStore()
    @StateObject private var liveTV = LiveTVDataStore.shared
    @State private var tab = 0
    @State private var sport = "Soccer"
    @State private var selectedLeague = "All Leagues"
    @State private var dayOffset = 0
    @State private var selectedEvent: SportEvent?

    private let sports = ["Soccer", "Basketball", "Ice Hockey", "American Football", "Tennis", "Motorsport", "Cricket"]
    private let allLeagues = "All Leagues"
    private let accent = Color(red: 0.0, green: 0.8, blue: 0.94)
    private let panel = Color(red: 0.095, green: 0.11, blue: 0.15)

    private var availableLeagues: [String] {
        Array(Set(fixtures.events.map(\.league))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var visibleEvents: [SportEvent] {
        selectedLeague == allLeagues ? fixtures.events : fixtures.events.filter { $0.league == selectedLeague }
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
        .task(id: "\(sport)-\(dayOffset)") {
            await fixtures.fetch(sport: sport, date: Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date())
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
            Text("Choose a sport").font(.title3.bold())
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(sports, id: \.self) { item in
                        Button(item) { sport = item; selectedLeague = allLeagues }
                            .buttonStyle(.bordered)
                            .tint(sport == item ? accent : .gray)
                    }
                }
            }
            if !availableLeagues.isEmpty {
                HStack {
                    Text("League").font(.title3.bold())
                    Menu {
                        Button(allLeagues) { selectedLeague = allLeagues }
                        ForEach(availableLeagues, id: \.self) { league in
                            Button(league) { selectedLeague = league }
                        }
                    } label: {
                        Label(selectedLeague, systemImage: "chevron.down")
                            .padding(.horizontal, 22)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .tint(accent)
                    Spacer()
                    Text("Leagues with matches on this day")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 18) {
                ForEach(-1...3, id: \.self) { offset in
                    Button(offset == 0 ? "Today" : offset == -1 ? "Yesterday" : "Day +\(offset)") {
                        dayOffset = offset
                        selectedLeague = allLeagues
                    }
                    .buttonStyle(.bordered)
                    .tint(dayOffset == offset ? accent : .gray)
                }
            }
            if fixtures.loading {
                ProgressView("Loading matches…")
            } else if let error = fixtures.error {
                Text(error).foregroundStyle(.orange)
            } else if fixtures.events.isEmpty {
                emptyPanel("No events returned for this sport and day.")
            } else {
                Text("\(visibleEvents.count) matches in \(selectedLeague)")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3), spacing: 18) {
                    ForEach(visibleEvents) { event in
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
                }
            }
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
        VStack(alignment: .leading, spacing: 22) {
            Text("Live TV connection").font(.largeTitle.bold())
            Text("SportFrame uses your existing DreamCAST Live TV playlists.")
                .foregroundStyle(.secondary)
            Text("\(liveTV.channels.count) available channels")
                .font(.title2.bold()).foregroundStyle(accent)
            Text("Add or refresh M3U and Xtream sources in DreamCAST Live TV settings.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("TheSportsDB free schedule limits results. Premium access is not yet wired into this pilot.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(28)
        .background(panel, in: RoundedRectangle(cornerRadius: 20))
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
