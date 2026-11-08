import Foundation
import Combine

struct SportCategory: Decodable {
    let strSport: String
}

struct SportsCatalogLeague: Decodable, Identifiable {
    let idLeague: String
    let strLeague: String
    let strSport: String
    var id: String { idLeague }
}

private struct SportsListResponse: Decodable { let sports: [SportCategory]? }
private struct SportsLeaguesResponse: Decodable { let leagues: [SportsCatalogLeague]? }

@MainActor
final class SportFrameCatalog: ObservableObject {
    @Published private(set) var sports: [String] = []
    @Published private(set) var leagues: [SportsCatalogLeague] = []
    @Published private(set) var message: String?

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
}
