import Foundation

struct SportEvent: Decodable, Identifiable {
    let idEvent: String
    let strEvent: String?
    let strHomeTeam: String?
    let strAwayTeam: String?
    let strLeague: String?
    let strHomeTeamBadge: String?
    let strAwayTeamBadge: String?
    let dateEvent: String?
    let strTime: String?
    let intHomeScore: String?
    let intAwayScore: String?

    var id: String { idEvent }
    var name: String { strEvent ?? "Upcoming event" }
    var league: String { strLeague ?? "Other league" }
    var homeBadge: URL? { strHomeTeamBadge.flatMap(URL.init(string:)) }
    var awayBadge: URL? { strAwayTeamBadge.flatMap(URL.init(string:)) }
    var kickoff: String { [dateEvent, strTime].compactMap { $0 }.joined(separator: "  ") }
}

struct DayResponse: Decodable { let events: [SportEvent]? }

enum ChannelMatcher {
    static func normalize(_ text: String) -> String {
        let normalized = text.lowercased().unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? String($0) : " "
        }
        return String(normalized).split(separator: " ").joined(separator: " ")
    }

    static func matching(_ event: SportEvent, in channels: [UnifiedChannel]) -> [UnifiedChannel] {
        guard let home = event.strHomeTeam, let away = event.strAwayTeam else { return [] }
        let first = normalize(home), second = normalize(away)
        guard first.count >= 4 && second.count >= 4 else { return [] }
        return channels.filter {
            let title = normalize($0.name)
            return title.contains(first) && title.contains(second)
        }
    }
}
