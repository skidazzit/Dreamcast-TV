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
        var results: [SportEvent] = []
        var sportMap: [String: String] = [:]
        var failures = 0
        for sport in sports {
            if Task.isCancelled { return }
            var parts = URLComponents(string: "https://www.thesportsdb.com/api/v1/json/\(SportsDBAccess.apiKey)/eventsday.php")!
            parts.queryItems = [URLQueryItem(name: "d", value: day.string(from: date)),
                                URLQueryItem(name: "s", value: sport)]
            guard let url = parts.url else { failures += 1; continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let dayEvents = try JSONDecoder().decode(DayResponse.self, from: data).events ?? []
                for event in dayEvents { sportMap[event.idEvent] = sport }
                results.append(contentsOf: dayEvents)
            } catch {
                failures += 1
            }
        }
        if Task.isCancelled { return }
        // One event may appear under multiple sport labels. Keep its first copy.
        var ids = Set<String>()
        events = results.filter { ids.insert($0.idEvent).inserted }
        eventSports = sportMap
        if failures > 0 { error = failures == sports.count ? "Could not load sports schedules." : nil }
        // When today's slate has no future fixtures, get tomorrow's schedule
        // for the Coming up shelf without changing today's league summaries.
        guard Calendar.current.isDateInToday(date),
              !events.contains(where: { $0.isUpcoming }),
              let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date) else {
            nextDayEvents = []
            nextDaySports = [:]
            return
        }
        var upcoming: [SportEvent] = []
        var upcomingSports: [String: String] = [:]
        for sport in sports {
            if Task.isCancelled { return }
            var parts = URLComponents(string: "https://www.thesportsdb.com/api/v1/json/\(SportsDBAccess.apiKey)/eventsday.php")!
            parts.queryItems = [URLQueryItem(name: "d", value: day.string(from: tomorrow)),
                                URLQueryItem(name: "s", value: sport)]
            guard let url = parts.url else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                let dayEvents = try JSONDecoder().decode(DayResponse.self, from: data).events ?? []
                for event in dayEvents {
                    upcomingSports[event.idEvent] = sport
                    upcoming.append(event)
                }
            } catch {
                continue
            }
        }
        if Task.isCancelled { return }
        var upcomingIDs = Set<String>()
        nextDayEvents = upcoming.filter { upcomingIDs.insert($0.idEvent).inserted }
        nextDaySports = upcomingSports
    }
}
