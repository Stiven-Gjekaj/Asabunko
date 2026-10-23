import AsaCore
import Foundation

/// The accounts of the trackers. The client ID of each site is a setting. The token is in the Keychain.
enum TrackerAccounts {
    static func clientKey(_ kind: TrackerKind) -> String { "tracker.\(kind.rawValue).client" }
    private static func tokenKey(_ kind: TrackerKind) -> String { "tracker.\(kind.rawValue)" }

    static func clientID(_ kind: TrackerKind) -> String {
        (UserDefaults.standard.string(forKey: clientKey(kind)) ?? "").trimmingCharacters(in: .whitespaces)
    }

    static func token(_ kind: TrackerKind) -> String? { Keychain.secret(tokenKey(kind)) }

    static func setToken(_ token: String?, for kind: TrackerKind) { Keychain.setSecret(token, for: tokenKey(kind)) }

    /// A UI test sends the calls of the trackers to the test server.
    private static let base = ProcessInfo.processInfo.environment["ASABUNKO_TRACKER_BASE"].flatMap(URL.init(string:))

    static func tracker(_ kind: TrackerKind) -> Tracker {
        Tracker(kind: kind, clientID: clientID(kind), token: token(kind), fetcher: appFetcher, base: base)
    }
}

extension AppModel {
    /// Sends the progress of a book to each of its trackers. A tracker gets only a number that goes up.
    /// A failed call tries again at the next change of the book.
    func sendProgress(of id: Book.ID) {
        guard let book = book(id), !book.tracking.isEmpty else { return }
        for link in book.tracking {
            guard TrackerAccounts.token(link.kind) != nil,
                  let chapters = Tracker.progress(page: book.page, pageCount: book.pageCount, finished: book.finished, sent: link.sent)
            else { continue }
            Task {
                do {
                    try await TrackerAccounts.tracker(link.kind).setProgress(of: link, chapters: chapters, finished: book.finished)
                    changeLibrary { library in
                        guard let index = library.books.firstIndex(where: { $0.id == id }),
                              let place = library.books[index].tracking.firstIndex(where: { $0.kind == link.kind }) else { return }
                        library.books[index].tracking[place].sent = max(library.books[index].tracking[place].sent, chapters)
                    }
                } catch TrackerError.notSignedIn {
                    fault = "Sign in to \(link.kind.name) again in Settings to send your progress."
                } catch {}
            }
        }
    }

    /// Links a book to an entry of a tracker, and sends the progress at once.
    func track(_ id: Book.ID, with hit: TrackerHit, on kind: TrackerKind) {
        update(id) { book in
            book.tracking.removeAll { $0.kind == kind }
            book.tracking.append(TrackLink(kind: kind, id: hit.id, title: hit.title))
        }
        sendProgress(of: id)
    }

    func untrack(_ id: Book.ID, from kind: TrackerKind) {
        update(id) { $0.tracking.removeAll { $0.kind == kind } }
    }
}
