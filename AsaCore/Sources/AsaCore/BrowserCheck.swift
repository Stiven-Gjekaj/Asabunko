import Foundation

/// Finds the answer of a site that asks for a check in a browser, such as the challenge of Cloudflare.
/// The app shows the page in a web view, the user passes the check, and the cookie of the check goes to the session.
public enum BrowserCheck {
    public static func isChallenge(status: Int, headers: [String: String], body: Data) -> Bool {
        let lower = Dictionary(headers.map { ($0.key.lowercased(), $0.value.lowercased()) }, uniquingKeysWith: { a, _ in a })
        if lower["cf-mitigated"] == "challenge" { return true }
        guard status == 403 || status == 503 || status == 429, lower["server"]?.contains("cloudflare") == true else { return false }
        let text = String(decoding: body.prefix(16_384), as: UTF8.self)
        return ["challenge-platform", "cf-chl", "Just a moment...", "cf_chl_opt", "Attention Required!"].contains { text.contains($0) }
    }

    /// True when the cookies hold the mark of a passed check for the host.
    public static func passed(_ cookies: [HTTPCookie], host: String) -> Bool {
        cookies.contains { cookie in
            cookie.name == "cf_clearance" && (host == cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) || host.hasSuffix(cookie.domain.hasPrefix(".") ? cookie.domain : "." + cookie.domain))
        }
    }
}
