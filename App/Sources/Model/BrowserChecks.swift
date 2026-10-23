import AsaCore
import Foundation
import Observation

/// The sites that asked for a check in a browser, such as the challenge of Cloudflare.
/// The fetcher of the sources reports a site here, and the app offers to open it in a web view.
@MainActor
@Observable
final class BrowserChecks {
    static let shared = BrowserChecks()

    /// The page of the last site that asked for a check, until the user opens it or closes the banner.
    var pending: URL?
    /// The hosts that the user passed in this session, so that a late answer of the same host does not ask again.
    private var passed: Set<String> = []
    /// The number of checks that the user passed. A screen with a fault loads again when it changes.
    private(set) var passes = 0

    func report(_ url: URL) {
        guard let host = url.host, !passed.contains(host), pending?.host != host else { return }
        pending = url
    }

    func markPassed(_ host: String) {
        passed.insert(host)
        passes += 1
        if pending?.host == host { pending = nil }
    }

    /// Looks at an answer of a source, and reports the site when the answer is a check.
    nonisolated static func inspect(_ response: HTTPURLResponse, data: Data) {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { $0["\($1.key)"] = "\($1.value)" }
        guard BrowserCheck.isChallenge(status: response.statusCode, headers: headers, body: data), let url = response.url else { return }
        Task { @MainActor in BrowserChecks.shared.report(url) }
    }
}
