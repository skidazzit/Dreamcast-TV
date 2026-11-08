// TheSportsDB public v1 read-only schedule client.
// Free key 123 is published in the provider's API documentation.
import Foundation
import Combine
import Security

nonisolated struct SportsDBEvent: Decodable, Identifiable, Sendable {
    let idEvent: String
    let strEvent: String?
    let strSport: String?
    let strLeague: String?
    let strLeagueBadge: String?
    let strHomeTeam: String?
    let strAwayTeam: String?
    let strHomeTeamBadge: String?
    let strAwayTeamBadge: String?
    let strThumb: String?
    let dateEvent: String?
    let strTime: String?
    let intHomeScore: String?
    let intAwayScore: String?
    let strStatus: String?

    var id: String { idEvent }
    var title: String { strEvent ?? [strHomeTeam, strAwayTeam].compactMap { $0 }.joined(separator: " vs ") }
    var league: String { strLeague ?? "Sport" }
    var sport: String { strSport ?? "" }

    var startTime: Date? {
        guard let dateEvent else { return nil }
        let combined = "\(dateEvent)T\(strTime ?? "00:00:00")Z"
        return ISO8601DateFormatter().date(from: combined)
    }

    var homeBadge: URL? { secureURL(strHomeTeamBadge) }
    var awayBadge: URL? { secureURL(strAwayTeamBadge) }
    var leagueBadge: URL? { secureURL(strLeagueBadge) }
    var artwork: URL? { secureURL(strThumb) }

    private func secureURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }
}

private struct SportsDBDayResponse: Decodable, Sendable {
    let events: [SportsDBEvent]?
}

// Saved only on this Apple TV or simulator, never in the Git repository.
nonisolated enum SportsDBPremiumKeyStore {
    private static let service = "DreamCAST.TheSportsDB"
    private static let account = "premium-api-key"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    static func save(_ key: String?) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let deletion = SecItemDelete(query as CFDictionary)
        guard deletion == errSecSuccess || deletion == errSecItemNotFound else { return false }
        guard let key, !key.isEmpty else { return true }
        var attributes = query
        attributes[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}

actor SportsDBScheduleClient {
    static let shared = SportsDBScheduleClient()

    private struct CacheEntry {
        let fetchedAt: Date
        let events: [SportsDBEvent]
    }
    private var cache: [String: CacheEntry] = [:]
    private let ttl: TimeInterval = 15 * 60
    func events(on date: Date, forceRefresh: Bool = false) async throws -> [SportsDBEvent] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        let premiumKey = SportsDBPremiumKeyStore.read()
        let tier = premiumKey == nil ? "free" : "premium"
        let cacheKey = "\(tier):\(day)"
        if !forceRefresh, let entry = cache[cacheKey], Date().timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.events
        }
        let apiKey = premiumKey ?? "123"
        guard let base = URL(string: "https://www.thesportsdb.com/api/v1/json/\(apiKey)/eventsday.php") else {
            throw URLError(.badURL)
        }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "d", value: day)]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let events = try JSONDecoder().decode(SportsDBDayResponse.self, from: data).events ?? []
        cache[cacheKey] = CacheEntry(fetchedAt: Date(), events: events)
        return events
    }
}

@MainActor
final class SportsDBScheduleModel: ObservableObject {
    @Published private(set) var events: [SportsDBEvent] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var generation = 0

    func load(date: Date, forceRefresh: Bool = false) {
        generation += 1
        let current = generation
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let results = try await SportsDBScheduleClient.shared.events(on: date, forceRefresh: forceRefresh)
                guard current == generation else { return }
                events = results
                isLoading = false
            } catch {
                guard current == generation else { return }
                events = []
                errorMessage = "TheSportsDB schedule is unavailable right now."
                isLoading = false
            }
        }
    }
}
