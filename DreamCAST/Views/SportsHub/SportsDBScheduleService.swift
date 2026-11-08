// TheSportsDB public v1 read-only schedule client.
// Free key 123 is published in the provider's API documentation.
import Foundation
import Combine

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

actor SportsDBScheduleClient {
    static let shared = SportsDBScheduleClient()

    private struct CacheEntry {
        let fetchedAt: Date
        let events: [SportsDBEvent]
    }
    private var cache: [String: CacheEntry] = [:]
    private let ttl: TimeInterval = 15 * 60
    private let base = URL(string: "https://www.thesportsdb.com/api/v1/json/123/eventsday.php")!

    func events(on date: Date) async throws -> [SportsDBEvent] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let key = formatter.string(from: date)
        if let entry = cache[key], Date().timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.events
        }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "d", value: key)]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let events = try JSONDecoder().decode(SportsDBDayResponse.self, from: data).events ?? []
        cache[key] = CacheEntry(fetchedAt: Date(), events: events)
        return events
    }
}

@MainActor
final class SportsDBScheduleModel: ObservableObject {
    @Published private(set) var events: [SportsDBEvent] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var generation = 0

    func load(date: Date) {
        generation += 1
        let current = generation
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let results = try await SportsDBScheduleClient.shared.events(on: date)
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
