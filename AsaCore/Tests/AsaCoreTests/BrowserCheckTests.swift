import Foundation
import Testing
@testable import AsaCore

@Suite struct BrowserCheckTests {
    @Test func findsTheChallengeOfCloudflare() {
        #expect(BrowserCheck.isChallenge(status: 403, headers: ["cf-mitigated": "challenge"], body: Data()))
        let page = Data("<html><title>Just a moment...</title><script src=\"/cdn-cgi/challenge-platform/h/b/orchestrate\"></script>".utf8)
        #expect(BrowserCheck.isChallenge(status: 503, headers: ["Server": "cloudflare"], body: page))
    }

    @Test func aRefusalWithNoChallengeIsNotACheck() {
        #expect(!BrowserCheck.isChallenge(status: 403, headers: ["Server": "cloudflare"], body: Data("Forbidden".utf8)))
        #expect(!BrowserCheck.isChallenge(status: 503, headers: ["Server": "nginx"], body: Data("Just a moment...".utf8)))
        #expect(!BrowserCheck.isChallenge(status: 200, headers: ["Server": "cloudflare"], body: Data("cf-chl".utf8)))
    }

    @Test func theClearanceCookieOfTheSiteMarksAPassedCheck() throws {
        func cookie(_ name: String, _ domain: String) throws -> HTTPCookie {
            try #require(HTTPCookie(properties: [.name: name, .value: "x", .domain: domain, .path: "/"]))
        }
        #expect(BrowserCheck.passed([try cookie("cf_clearance", ".mangasite.test")], host: "www.mangasite.test"))
        #expect(BrowserCheck.passed([try cookie("cf_clearance", "mangasite.test")], host: "mangasite.test"))
        #expect(!BrowserCheck.passed([try cookie("cf_clearance", ".other.test")], host: "mangasite.test"))
        #expect(!BrowserCheck.passed([try cookie("session", ".mangasite.test")], host: "mangasite.test"))
    }
}
