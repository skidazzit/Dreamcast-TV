import Foundation
import Combine

enum SportsDBAccess {
    private static let keychainAccount = "sportFrameSportsDBPremiumKey"

    static var hasPremiumKey: Bool { KeychainHelper.get(keychainAccount) != nil }
    static var apiKey: String { KeychainHelper.get(keychainAccount) ?? "123" }

    static func save(_ key: String) -> Bool {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.unicodeScalars.allSatisfy({
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").contains($0)
        }) else { return false }
        return KeychainHelper.set(cleaned, forKey: keychainAccount)
    }

    static func remove() { KeychainHelper.delete(keychainAccount) }
}

@MainActor
final class FixtureStore: ObservableObject {
    @Published private(set) var events: [SportEvent] = []
    @Published private(set) var eventSports: [String: String] = [:]
    @Published private(set) var nextDayEvents: [SportEvent] = []
    @Published private(set) var nextDaySports: [String: String] = [:]
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    func fetch(sports: [String], date: Date) async {
        loading = true
        error = nil
        defer { loading = false }
        guard !sports.isEmpty else { events = []; eventSports = [:]; nextDayEvents = []; nextDaySports = [:]; return }
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = .current
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        var results: [SportEvent] = []
        var sportMap: [String: String] = [:]
        var upcoming: [SportEvent] = []
        var upcomingSports: [String: String] = [:]
        var failures = 0
        for sport in sports {
            if Task.isCancelled { return }
            // UTC kickoff times can land on the following calendar day.
            // Fetch both API dates and sort them into the viewer's local day.
            for requestDate in [date, tomorrow] {
                if Task.isCancelled { return }
                var parts = URLComponents(string: "https://www.thesportsdb.com/api/v1/json/\(SportsDBAccess.apiKey)/eventsday.php")!
                parts.queryItems = [URLQueryItem(name: "d", value: day.string(from: requestDate)),
                                    URLQueryItem(name: "s", value: sport)]
                guard let url = parts.url else { failures += 1; continue }
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    let dayEvents = try JSONDecoder().decode(DayResponse.self, from: data).events ?? []
                    for event in dayEvents {
                        if isOnLocalDay(event, date: date, calendar: calendar) {
                            sportMap[event.idEvent] = sport
                            results.append(event)
                        } else if calendar.isDateInToday(date) && isOnLocalDay(event, date: tomorrow, calendar: calendar) {
                            upcomingSports[event.idEvent] = sport
                            upcoming.append(event)
                        }
                    }
                } catch {
                    failures += 1
                }
            }
        }
        if Task.isCancelled { return }
        // One event may appear under multiple sport labels. Keep its first copy.
        var ids = Set<String>()
        events = results.filter { ids.insert($0.idEvent).inserted }
        eventSports = sportMap
        if failures > 0 { error = failures == sports.count * 2 ? "Could not load sports schedules." : nil }
        var upcomingIDs = Set<String>()
        nextDayEvents = calendar.isDateInToday(date) ? upcoming.filter { upcomingIDs.insert($0.idEvent).inserted } : []
        nextDaySports = calendar.isDateInToday(date) ? upcomingSports : [:]
    }

    private func isOnLocalDay(_ event: SportEvent, date: Date, calendar: Calendar) -> Bool {
        if let kickoff = event.startDate { return calendar.isDate(kickoff, inSameDayAs: date) }
        // Older fixtures have no timestamp. Use their supplied date as a fallback.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        guard let rawDate = event.dateEvent, let fallback = formatter.date(from: rawDate) else { return false }
        return calendar.isDate(fallback, inSameDayAs: date)
    }
}
