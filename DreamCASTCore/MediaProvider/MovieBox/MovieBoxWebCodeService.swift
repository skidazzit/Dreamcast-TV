// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import Foundation

/// Only the public browser code-login flow is used. No Android app keys are copied.
nonisolated enum MovieBoxWebCodeError: LocalizedError, Sendable {
    case pageUnavailable
    case invalidCodePage
    case invalidCheckResponse
    case redirectedOutsideProvider

    var errorDescription: String? {
        switch self {
        case .pageUnavailable:
            "MovieBox Pro did not return a usable login page. Please try again later."
        case .invalidCodePage:
            "MovieBox Pro did not issue a TV code. The website may have changed."
        case .invalidCheckResponse:
            "MovieBox Pro returned an unknown code status. Please try a new code."
        case .redirectedOutsideProvider:
            "MovieBox Pro redirected login to another site. Sign-in stopped."
        }
    }
}

/// Parsing is kept apart from networking so the web contract can be tested offline.
nonisolated enum MovieBoxWebCodeParser {
    private static let codePattern = #"<[^>]*\bid\s*=\s*["']qrcode["'][^>]*>\s*([0-9]{6,10})\s*<"#

    static func challenge(from html: String, now: Date = Date()) throws -> MovieBoxDeviceCodeChallenge {
        let expression = try NSRegularExpression(pattern: codePattern, options: [.caseInsensitive])
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = expression.firstMatch(in: html, range: range),
              let codeRange = Range(match.range(at: 1), in: html),
              let challenge = MovieBoxDeviceCodeChallenge(
                  code: String(html[codeRange]),
                  expiresAt: now.addingTimeInterval(120),
                  pollInterval: 1.5,
                  now: now
              ) else {
            throw MovieBoxWebCodeError.invalidCodePage
        }
        return challenge
    }

    static func status(from data: Data) throws -> MovieBoxDeviceCodeStatus {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawCode = json["code"] else {
            throw MovieBoxWebCodeError.invalidCheckResponse
        }
        let number: Int?
        if let numericCode = rawCode as? NSNumber {
            number = numericCode.intValue
        } else if let stringCode = rawCode as? String {
            number = Int(stringCode)
        } else {
            number = nil
        }
        guard let number else { throw MovieBoxWebCodeError.invalidCheckResponse }
        return number == 1 ? .approved : .awaitingPhone
    }

    /// The website may include login values after the phone approves the code.
    /// Never expose these values through UI or diagnostic logs.
    static func approvedSession(from data: Data) -> MovieBoxWebSession? {
        guard (try? status(from: data)) == .approved,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ui = json["ui"] as? String else { return nil }
        return MovieBoxWebSession(ui: ui, ci: json["ci"] as? String)
    }
}

/// Holds cookies only in memory. Approval does not yet grant catalog access.
actor MovieBoxWebCodeService: MovieBoxDeviceCodeService {
    private let session: URLSession
    private let baseURL = URL(string: "https://www.movieboxpro.app")!

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let settings = URLSessionConfiguration.ephemeral
        settings.httpShouldSetCookies = true
        settings.httpCookieAcceptPolicy = .always
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData

        // This is a fresh browser-style ID, not another device's identity.
        // The site's device_bind.js sets these cookies for new visitors.
        let savedSession = MovieBoxWebSessionStore.load()
        let clientID = savedSession?.ci ?? ("mbp_" + UUID().uuidString.lowercased())
        if let cookies = settings.httpCookieStorage {
            for name in ["ci", "cl"] {
                if let cookie = HTTPCookie(properties: [
                    .domain: "www.movieboxpro.app",
                    .path: "/",
                    .name: name,
                    .value: clientID,
                    .secure: "TRUE"
                ]) {
                    cookies.setCookie(cookie)
                }
            }
            if let savedSession {
                Self.installCookie(name: "ui", value: savedSession.ui, into: cookies)
            }
        }
        self.session = URLSession(configuration: settings)
    }

    func requestCode() async throws -> MovieBoxDeviceCodeChallenge {
        var request = URLRequest(url: baseURL.appendingPathComponent("index/login/code_login"))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        guard let html = String(data: data, encoding: .utf8) else {
            throw MovieBoxWebCodeError.invalidCodePage
        }
        return try MovieBoxWebCodeParser.challenge(from: html)
    }

    func checkStatus(for challenge: MovieBoxDeviceCodeChallenge) async throws -> MovieBoxDeviceCodeStatus {
        guard !challenge.isExpired() else { return .expired }
        var request = URLRequest(url: baseURL.appendingPathComponent("index/login/captcha_query"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data("qr_code=\(challenge.code)".utf8)

        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        let status = try MovieBoxWebCodeParser.status(from: data)
        if status == .approved {
            // An approval reply may send ui/ci directly, or set them as cookies.
            let websiteCookies = session.configuration.httpCookieStorage?.cookies ?? []
            let cookieUI = websiteCookies.first(where: { $0.name == "ui" && Self.isProviderCookie($0) })?.value
            let cookieCI = websiteCookies.first(where: { $0.name == "ci" && Self.isProviderCookie($0) })?.value
            let responseSession = MovieBoxWebCodeParser.approvedSession(from: data)
            let approved = responseSession.flatMap {
                MovieBoxWebSession(ui: $0.ui, ci: $0.ci ?? cookieCI)
            } ?? cookieUI.flatMap { MovieBoxWebSession(ui: $0, ci: cookieCI) }
            if let approved {
                try MovieBoxWebSessionStore.save(approved)
                if let storage = session.configuration.httpCookieStorage {
                    Self.installCookie(name: "ui", value: approved.ui, into: storage)
                    if let ci = approved.ci {
                        Self.installCookie(name: "ci", value: ci, into: storage)
                    }
                }
            }
        }
        return status
    }

    func hasSavedSession() -> Bool {
        MovieBoxWebSessionStore.load() != nil
    }

    /// Loads the website's first page of movie cards without playback requests.
    func fetchMovies() async throws -> [MovieBoxWebMovieCard] {
        guard MovieBoxWebSessionStore.load() != nil else {
            throw MovieBoxWebCatalogError.noSavedSession
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("movie"))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        guard let html = String(data: data, encoding: .utf8) else {
            throw MovieBoxWebCatalogError.noMovieCards
        }
        let movies = try MovieBoxWebCatalogParser.movies(from: html)
        guard !movies.isEmpty else { throw MovieBoxWebCatalogError.noMovieCards }
        return movies
    }

    /// Loads the first page of TV show cards. No episode or video requests.
    func fetchShows() async throws -> [MovieBoxWebShowCard] {
        guard MovieBoxWebSessionStore.load() != nil else {
            throw MovieBoxWebCatalogError.noSavedSession
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("tvshow"))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        guard let html = String(data: data, encoding: .utf8) else {
            throw MovieBoxWebCatalogError.noShowCards
        }
        let shows = try MovieBoxWebCatalogParser.shows(from: html)
        guard !shows.isEmpty else { throw MovieBoxWebCatalogError.noShowCards }
        return shows
    }

    /// Reads a show's page and its embedded season list. Does not request video URLs.
    func fetchShowDetail(id: String, season: Int? = nil) async throws -> MovieBoxWebShowDetail {
        guard MovieBoxWebSessionStore.load() != nil else {
            throw MovieBoxWebCatalogError.noSavedSession
        }
        guard !id.isEmpty, id.count <= 20,
              id.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            throw MovieBoxWebShowDetailError.invalidShowID
        }
        if let season, !(0...100).contains(season) {
            throw MovieBoxWebShowDetailError.missingEpisodeData
        }

        let detailURL = baseURL.appendingPathComponent("tvshow").appendingPathComponent(id)
        var components = URLComponents(url: detailURL, resolvingAgainstBaseURL: false)
        if let season {
            components?.queryItems = [URLQueryItem(name: "season", value: String(season))]
        }
        var request = URLRequest(url: components?.url ?? detailURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        guard response.url?.path.hasPrefix("/tvshow/\(id)") == true else {
            throw MovieBoxWebShowDetailError.signInRequired
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw MovieBoxWebShowDetailError.missingEpisodeData
        }
        return try MovieBoxWebShowDetailParser.detail(from: html, id: id)
    }

    func forgetSavedSession() throws {
        try MovieBoxWebSessionStore.clear()
        if let cookies = session.configuration.httpCookieStorage {
            for cookie in cookies.cookies ?? [] where Self.isProviderCookie(cookie) {
                cookies.deleteCookie(cookie)
            }
        }
    }

    private static func isProviderCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domain == "movieboxpro.app" || domain == "www.movieboxpro.app"
    }

    private static func installCookie(name: String, value: String, into storage: HTTPCookieStorage) {
        if let cookie = HTTPCookie(properties: [
            .domain: "www.movieboxpro.app",
            .path: "/",
            .name: name,
            .value: value,
            .secure: "TRUE"
        ]) {
            storage.setCookie(cookie)
        }
    }

    private func checkResponse(_ response: URLResponse) throws {
        guard let url = response.url, url.scheme == "https",
              ["movieboxpro.app", "www.movieboxpro.app"].contains(url.host ?? "") else {
            throw MovieBoxWebCodeError.redirectedOutsideProvider
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MovieBoxWebCodeError.pageUnavailable
        }
    }
}
