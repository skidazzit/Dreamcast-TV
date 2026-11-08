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
                        emptyContent("Sports networks", description: "Network groups will use your current Live TV sources.", symbol: "dot.radiowaves.left.and.right")
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
    }

    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text("Favourite channels").font(.title2.bold())
            emptyShelf("Your favourite Live TV channels will appear here.", symbol: "star")

            Text("Live events").font(.title2.bold())
            emptyShelf("Match-to-channel links will appear after the sports data source is connected.", symbol: "play.tv")

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
                emptyShelf("Verified scores and match cards will appear here.", symbol: "sportscourt")
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
            emptyShelf("Your existing DreamCAST Live TV guide stays available from the Live TV sidebar.", symbol: "tv")
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
