import Foundation

struct SportEvent: Decodable, Identifiable {
    let idEvent: String
    let strEvent: String?
    let strHomeTeam: String?
    let strAwayTeam: String?
    let strLeague: String?
    let strSport: String?
    let strHomeTeamBadge: String?
    let strAwayTeamBadge: String?
    let dateEvent: String?
    let strTime: String?
    let strTimestamp: String?
    let strStatus: String?
    let strProgress: String?
    let intHomeScore: String?
    let intAwayScore: String?

    var id: String { idEvent }
    var name: String { strEvent ?? "Upcoming event" }
    var league: String { strLeague ?? "Other league" }
    var homeBadge: URL? { strHomeTeamBadge.flatMap(URL.init(string:)) }
    var awayBadge: URL? { strAwayTeamBadge.flatMap(URL.init(string:)) }
    var kickoff: String { [dateEvent, strTime].compactMap { $0 }.joined(separator: "  ") }

    var startDate: Date? {
        if let strTimestamp, let date = ISO8601DateFormatter().date(from: strTimestamp) { return date }
        guard let dateEvent, let strTime else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: "\(dateEvent) \(strTime)")
    }

    var isLive: Bool {
        let status = (strStatus ?? "").lowercased()
        let progress = (strProgress ?? "").lowercased()
        if ["finished", "final", "full time", "ft", "postponed", "cancelled"].contains(where: { status.contains($0) }) { return false }
        return ["live", "in play", "half time", "1st half", "2nd half", "in progress"].contains(where: { status.contains($0) })
            || (!progress.isEmpty && progress != "ft" && progress != "finished")
    }

    var isUpcoming: Bool { !isLive && (startDate.map { $0 > Date() } ?? false) }
    var timeLabel: String {
        guard let startDate else { return strTime ?? "Time TBA" }
        return startDate.formatted(date: .omitted, time: .shortened)
    }
}

struct DayResponse: Decodable { let events: [SportEvent]? }

enum ChannelMatcher {
    static func normalize(_ text: String) -> String {
        let normalized = text.lowercased().unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? String($0) : " "
        }
        return normalized.joined().split(separator: " ").joined(separator: " ")
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
