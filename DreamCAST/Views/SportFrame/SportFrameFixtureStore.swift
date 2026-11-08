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
    @Published private(set) var liveEventIDs: Set<String> = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    func fetch(sports: [String], date: Date, quietly: Bool = false) async {
        if !quietly { loading = true; error = nil }
        defer { if !quietly { loading = false } }
        guard !sports.isEmpty else { events = []; eventSports = [:]; liveEventIDs = []; return }
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
        let activeIDs = await premiumLiveEventIDs()
        if Task.isCancelled { return }
        // One event may appear under multiple sport labels. Keep its first copy.
        var ids = Set<String>()
        let refreshed = results.filter { ids.insert($0.idEvent).inserted }
        // A failed background check must not erase the schedule already on screen.
        if !quietly || failures < sports.count {
            events = refreshed
            eventSports = sportMap
            liveEventIDs = activeIDs
        }
        if !quietly && failures > 0 { error = failures == sports.count ? "Could not load sports schedules." : nil }
    }

    private func premiumLiveEventIDs() async -> Set<String> {
        guard SportsDBAccess.hasPremiumKey,
              let url = URL(string: "https://www.thesportsdb.com/api/v2/json/livescore/all") else { return [] }
        var request = URLRequest(url: url)
        request.setValue(SportsDBAccess.apiKey, forHTTPHeaderField: "X_API_KEY")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
            let rows = payload.values.compactMap { $0 as? [[String: Any]] }.first ?? []
            return Set(rows.compactMap { row -> String? in
                if let id = row["idEvent"] as? String { return id }
                if let id = row["idEvent"] as? Int { return String(id) }
                return nil
            })
        } catch { return [] }
    }
}
