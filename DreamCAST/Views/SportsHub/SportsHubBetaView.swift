// Sports Hub beta: original tvOS interface built from the user-provided layout reference.
// No third-party artwork, stream links, or unverified match data are bundled.
import SwiftUI

struct SportsHubBetaView: View {
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
    @State private var scoreSubscription: ScoreboardPoller.Subscription?
    @State private var section: Section = .home
    @State private var sport: Sport = .football
    @State private var sportTab: SportTab = .watch
    @State private var selectedDay = 1
    @State private var selectedLeague = "All leagues"

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
        }
        .onDisappear { scoreSubscription = nil }
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
                                Text(game.network ?? "Network not listed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                emptyShelf("Live and upcoming \(sport.rawValue.lowercased()) events will appear here.", symbol: "play.rectangle")
            } else if sportTab == .scores {
                datePicker
                scoreCards
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
            emptyShelf("Sports scores and standings need a verified data provider.", symbol: "network")
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
