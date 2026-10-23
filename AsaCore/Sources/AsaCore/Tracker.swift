import Foundation

/// A site that keeps the reading list of the user.
public enum TrackerKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case anilist, myanimelist

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .anilist: "AniList"
        case .myanimelist: "MyAnimeList"
        }
    }

    /// The redirect URI that the user gives to the site when the user registers a client for Asabunko.
    public var redirect: String { "asabunko://\(rawValue)" }
}

/// The entry of a book on a tracker.
public struct TrackLink: Codable, Sendable, Equatable, Hashable {
    public var kind: TrackerKind
    public var id: Int
    public var title: String
    /// The number of chapters that the tracker has now from the app.
    public var sent: Int

    public init(kind: TrackerKind, id: Int, title: String, sent: Int = 0) {
        self.kind = kind; self.id = id; self.title = title; self.sent = sent
    }
}

/// A title of a search on a tracker.
public struct TrackerHit: Sendable, Equatable, Identifiable {
    public var id: Int
    public var title: String
    public var chapters: Int?
}

public enum TrackerError: Error, Equatable, LocalizedError {
    case notSignedIn
    case refused(String)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: "Sign in to the tracker in Settings first."
        case let .refused(text): "The tracker refused the request: \(text)"
        }
    }
}

/// The calls to AniList or MyAnimeList. The user registers a client on the site and gives its ID to the app,
/// because the app has no client of its own.
public struct Tracker: Sendable {
    public let kind: TrackerKind
    public let clientID: String
    public let token: String?
    private let fetcher: Fetcher
    /// The base of each URL, which a test changes to a local server.
    private let base: URL?

    public init(kind: TrackerKind, clientID: String, token: String?, fetcher: @escaping Fetcher, base: URL? = nil) {
        self.kind = kind; self.clientID = clientID; self.token = token; self.fetcher = fetcher; self.base = base
    }

    private func url(_ real: String, test path: String) -> URL {
        if let base { return base.appendingPathComponent(kind.rawValue).appendingPathComponent(path) }
        return URL(string: real)!
    }

    /// The page of the sign-in. MyAnimeList needs a code verifier, which the app keeps until the callback.
    public func signInURL(verifier: String, state: String) -> URL {
        switch kind {
        case .anilist:
            var parts = URLComponents(url: url("https://anilist.co/api/v2/oauth/authorize", test: "authorize"), resolvingAgainstBaseURL: false)!
            parts.queryItems = [URLQueryItem(name: "client_id", value: clientID), URLQueryItem(name: "response_type", value: "token")]
            return parts.url!
        case .myanimelist:
            // MyAnimeList takes only the plain method of PKCE.
            var parts = URLComponents(url: url("https://myanimelist.net/v1/oauth2/authorize", test: "authorize"), resolvingAgainstBaseURL: false)!
            parts.queryItems = [
                URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "code_challenge", value: verifier), URLQueryItem(name: "code_challenge_method", value: "plain"),
                URLQueryItem(name: "state", value: state), URLQueryItem(name: "redirect_uri", value: kind.redirect),
            ]
            return parts.url!
        }
    }

    /// The token of the callback. AniList puts it in the fragment. MyAnimeList gives a code, which changes into a token.
    public func token(from callback: URL, verifier: String) async throws -> String {
        let fragment = URLComponents(string: "x://x?" + (callback.fragment ?? ""))?.queryItems ?? []
        let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch kind {
        case .anilist:
            guard let token = fragment.first(where: { $0.name == "access_token" })?.value else { throw TrackerError.refused("no token") }
            return token
        case .myanimelist:
            guard let code = query.first(where: { $0.name == "code" })?.value else { throw TrackerError.refused("no code") }
            var request = URLRequest(url: url("https://myanimelist.net/v1/oauth2/token", test: "token"))
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.form(["client_id": clientID, "code": code, "code_verifier": verifier,
                                          "grant_type": "authorization_code", "redirect_uri": kind.redirect])
            let answer = try await json(request)
            guard let token = answer["access_token"] as? String else { throw TrackerError.refused("no token") }
            return token
        }
    }

    /// The titles of the tracker for the words of a search.
    public func search(_ words: String) async throws -> [TrackerHit] {
        switch kind {
        case .anilist:
            let answer = try await graphQL("""
            query ($search: String) { Page(perPage: 10) { media(search: $search, type: MANGA) { id chapters title { userPreferred } } } }
            """, ["search": words])
            let media = ((answer["data"] as? [String: Any])?["Page"] as? [String: Any])?["media"] as? [[String: Any]] ?? []
            return media.compactMap { item in
                guard let id = item["id"] as? Int else { return nil }
                let title = (item["title"] as? [String: Any])?["userPreferred"] as? String ?? ""
                return TrackerHit(id: id, title: title, chapters: item["chapters"] as? Int)
            }
        case .myanimelist:
            var parts = URLComponents(url: url("https://api.myanimelist.net/v2/manga", test: "manga"), resolvingAgainstBaseURL: false)!
            parts.queryItems = [URLQueryItem(name: "q", value: String(words.prefix(64))), URLQueryItem(name: "limit", value: "10"),
                                URLQueryItem(name: "fields", value: "num_chapters")]
            let answer = try await json(try signed(URLRequest(url: parts.url!)))
            let list = answer["data"] as? [[String: Any]] ?? []
            return list.compactMap { entry in
                guard let node = entry["node"] as? [String: Any], let id = node["id"] as? Int else { return nil }
                let chapters = node["num_chapters"] as? Int
                return TrackerHit(id: id, title: node["title"] as? String ?? "", chapters: chapters == 0 ? nil : chapters)
            }
        }
    }

    /// Tells the tracker the number of chapters that the user read.
    public func setProgress(of link: TrackLink, chapters: Int, finished: Bool) async throws {
        switch kind {
        case .anilist:
            _ = try await graphQL("""
            mutation ($id: Int, $progress: Int, $status: MediaListStatus) { SaveMediaListEntry(mediaId: $id, progress: $progress, status: $status) { id progress } }
            """, ["id": link.id, "progress": chapters, "status": finished ? "COMPLETED" : "CURRENT"])
        case .myanimelist:
            var request = try signed(URLRequest(url: url("https://api.myanimelist.net/v2/manga/\(link.id)/my_list_status", test: "manga/\(link.id)/my_list_status")))
            request.httpMethod = "PATCH"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.form(["num_chapters_read": String(chapters), "status": finished ? "completed" : "reading"])
            _ = try await json(request)
        }
    }

    // MARK: The requests

    private func signed(_ request: URLRequest) throws -> URLRequest {
        guard let token else { throw TrackerError.notSignedIn }
        var request = request
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        return request
    }

    private func graphQL(_ query: String, _ variables: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url("https://graphql.anilist.co", test: "graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        // A search works with no token. A change of the list needs one.
        if token != nil || query.hasPrefix("mutation") { request = try signed(request) }
        let answer = try await json(request)
        if let message = (answer["errors"] as? [[String: Any]])?.first?["message"] as? String { throw TrackerError.refused(message) }
        return answer
    }

    private func json(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await fetcher(request)
        let answer = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (200..<300).contains(response.statusCode) else {
            let message = (answer["message"] as? String) ?? (answer["error"] as? String) ?? "HTTP \(response.statusCode)"
            throw response.statusCode == 401 ? TrackerError.notSignedIn : TrackerError.refused(message)
        }
        return answer
    }

    static func form(_ values: [String: String]) -> Data {
        // A form value keeps only the unreserved characters of RFC 3986.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(values.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&").utf8)
    }

    /// The number of chapters that the tracker gets for a place in a book: the chapters before the open one,
    /// or all chapters of a finished book. The number does not go down, because a tracker counts the chapters read.
    public static func progress(page: Int, pageCount: Int, finished: Bool, sent: Int) -> Int? {
        let read = finished ? pageCount : max(page, 0)
        return read > sent ? read : nil
    }
}
