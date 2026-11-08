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
        let status = (strStatus ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let progress = (strProgress ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let finalCodes: Set<String> = ["FT", "AET", "AOT", "PEN", "AP", "AW", "AWD", "WO", "FINAL", "FINISHED", "NS", "TBD", "PST", "POST", "CANC", "CANCELLED", "ABD", "SUSP"]
        if finalCodes.contains(status) || ["FINAL", "FINISHED", "FULL TIME"].contains(where: { progress.contains($0) }) { return false }
        let inPlay: Set<String> = ["1H", "2H", "HT", "ET", "BT", "P", "PT", "Q1", "Q2", "Q3", "Q4", "OT", "IN1", "IN2", "IN3", "IN4", "IN5", "IN6", "IN7", "IN8", "IN9", "P1", "P2", "P3", "S1", "S2", "S3", "S4", "S5"]
        if inPlay.contains(status) || status.hasPrefix("LIVE") || status.contains("IN PLAY") { return true }
        if !progress.isEmpty && (progress.contains(":") || progress.contains("1ST") || progress.contains("2ND") || progress.contains("3RD") || progress.contains("4TH")) { return true }
        // Some day-schedule feeds omit status. Infer only when scores exist
        // and kickoff falls within a short, plausible in-play window.
        guard status.isEmpty, progress.isEmpty,
              intHomeScore != nil, intAwayScore != nil,
              let startDate else { return false }
        let elapsed = Date().timeIntervalSince(startDate)
        let window: TimeInterval = strSport == "American Football" ? 4 * 3600 : 3 * 3600
        return elapsed >= 0 && elapsed < window
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
