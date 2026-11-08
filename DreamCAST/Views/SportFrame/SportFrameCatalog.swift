import Foundation
import Combine

struct SportCategory: Decodable {
    let strSport: String
}

struct SportsCatalogLeague: Decodable, Identifiable {
    let idLeague: String
    let strLeague: String
    let strSport: String
    let strBadge: String?
    let strLogo: String?
    var id: String { idLeague }
}

private struct SportsListResponse: Decodable { let sports: [SportCategory]? }
private struct SportsLeaguesResponse: Decodable { let leagues: [SportsCatalogLeague]? }

@MainActor
final class SportFrameCatalog: ObservableObject {
    @Published private(set) var sports: [String] = []
    @Published private(set) var leagues: [SportsCatalogLeague] = []
    @Published private(set) var message: String?
    @Published private(set) var badgeURLs: [String: URL] = [:]
    private var requestedBadges = Set<String>()

    func refresh() async {
        let base = "https://www.thesportsdb.com/api/v1/json/\(SportsDBAccess.apiKey)/"
        do {
            async let sportsRequest = URLSession.shared.data(from: URL(string: base + "all_sports.php")!)
            async let leaguesRequest = URLSession.shared.data(from: URL(string: base + "all_leagues.php")!)
            let (sportData, sportResponse) = try await sportsRequest
            let (leagueData, leagueResponse) = try await leaguesRequest
            guard (sportResponse as? HTTPURLResponse)?.statusCode == 200,
                  (leagueResponse as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            sports = Array(Set((try JSONDecoder().decode(SportsListResponse.self, from: sportData).sports ?? []).map(\.strSport)))
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            leagues = try JSONDecoder().decode(SportsLeaguesResponse.self, from: leagueData).leagues ?? []
            message = nil
        } catch {
            message = "Could not load the sport catalog. Existing choices are still available."
        }
    }

    func leagues(for sport: String) -> [SportsCatalogLeague] {
        leagues.filter { $0.strSport.caseInsensitiveCompare(sport) == .orderedSame }
            .sorted { $0.strLeague.localizedStandardCompare($1.strLeague) == .orderedAscending }
    }

    func badgeURL(for leagueName: String, sport: String) -> URL? {
        guard let league = matchingLeague(leagueName, sport: sport) else { return nil }
        return badgeURLs[league.idLeague] ?? URL(string: league.strBadge ?? league.strLogo ?? "")
    }

    func loadBadge(for leagueName: String, sport: String) async {
        guard let league = matchingLeague(leagueName, sport: sport),
              badgeURL(for: leagueName, sport: sport) == nil,
              requestedBadges.insert(league.idLeague).inserted else { return }
        guard let url = URL(string: "https://www.thesportsdb.com/api/v1/json/\(SportsDBAccess.apiKey)/lookupleague.php?id=\(league.idLeague)") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let detail = (payload["leagues"] as? [[String: Any]])?.first,
                  let badge = (detail["strBadge"] as? String) ?? (detail["strLogo"] as? String),
                  let badgeURL = URL(string: badge), !Task.isCancelled else { return }
            badgeURLs[league.idLeague] = badgeURL
        } catch {
            // Keep the sport icon when the league has no available artwork.
        }
    }

    private func matchingLeague(_ name: String, sport: String) -> SportsCatalogLeague? {
        leagues.first {
            $0.strSport.caseInsensitiveCompare(sport) == .orderedSame &&
            $0.strLeague.caseInsensitiveCompare(name) == .orderedSame
        }
    }
}
