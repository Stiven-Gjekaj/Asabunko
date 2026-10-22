import Testing
@testable import AsaCore

@Suite struct AppVersionTests {
    @Test func comparesEachNumber() {
        #expect(AppVersion.isNewer("v0.10.0", than: "0.9.3"))
        #expect(AppVersion.isNewer("1.0.1", than: "1.0"))
        #expect(!AppVersion.isNewer("v0.1.0", than: "0.1.0"))
        #expect(!AppVersion.isNewer("0.2.0", than: "0.10.0"))
    }
}
