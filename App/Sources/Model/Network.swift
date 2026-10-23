import Foundation
import Security

/// The network of the app, with one session and the passwords of the servers in the Keychain.
enum Network {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: configuration)
    }()

    /// The user agent of Safari on iOS. Some sites refuse a request with no browser in it.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    enum Failure: LocalizedError {
        case status(Int)

        var errorDescription: String? {
            switch self {
            case let .status(code) where code == 401 || code == 403: "The server refused the user name or the password."
            case let .status(code): "The server answered with the code \(code)."
            }
        }
    }

    static func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            BrowserChecks.inspect(http, data: data)
            throw Failure.status(http.statusCode)
        }
        return data
    }
}

/// The passwords of the servers and the tokens of the trackers. They stay on this device and are not in a backup.
enum Keychain {
    private static let service = "io.github.stivengjekaj.asabunko.servers"

    static func password(for id: UUID) -> String? { secret(id.uuidString) }

    static func setPassword(_ password: String?, for id: UUID) { setSecret(password, for: id.uuidString) }

    /// A secret of the app with a name, such as the token of a tracker.
    static func secret(_ account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setSecret(_ password: String?, for account: String) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        SecItemDelete(query as CFDictionary)
        guard let password, !password.isEmpty else { return }
        var add = query
        add[kSecValueData] = Data(password.utf8)
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
