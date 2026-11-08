import Foundation
import Combine

@MainActor
final class FixtureStore: ObservableObject {
    @Published private(set) var events: [SportEvent] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    func fetch(sport: String, date: Date) async {
        loading = true
        error = nil
        defer { loading = false }
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = .current
        var parts = URLComponents(string: "https://www.thesportsdb.com/api/v1/json/123/eventsday.php")!
        parts.queryItems = [URLQueryItem(name: "d", value: day.string(from: date)),
                            URLQueryItem(name: "s", value: sport)]
        guard let url = parts.url else { error = "Invalid schedule URL"; return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            events = try JSONDecoder().decode(DayResponse.self, from: data).events ?? []
        } catch {
            events = []
            self.error = "Could not load events. Check your internet connection."
        }
    }
}
