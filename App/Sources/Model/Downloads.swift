import AsaCore
import Foundation
import Observation

/// The downloads of the chapters of online series, one chapter at a time.
@MainActor
@Observable
final class Downloads {
    struct Job: Hashable {
        let book: Book.ID
        let chapter: Int
    }

    /// The chapters that wait, in order. The first one downloads now.
    private(set) var queue: [Job] = []
    /// The pages of the chapter that downloads now.
    private(set) var progress: (done: Int, total: Int)?
    /// A number that changes when a chapter finishes, so that the screens read the files again.
    private(set) var changes = 0
    /// The chapters that did not download, with the reason.
    private(set) var failed: [Job: String] = [:]
    private var running = false
    /// The download of the first job, so that a cancel can stop it.
    private var current: Task<Void, Error>?

    func isWaiting(_ book: Book.ID, _ chapter: Int) -> Bool { queue.contains(Job(book: book, chapter: chapter)) }
    func isActive(_ book: Book.ID, _ chapter: Int) -> Bool { queue.first == Job(book: book, chapter: chapter) }
    func fault(_ book: Book.ID, _ chapter: Int) -> String? { failed[Job(book: book, chapter: chapter)] }
    func failedCount(_ book: Book.ID) -> Int { failed.keys.filter { $0.book == book }.count }

    func enqueue(_ jobs: [Job], app: AppModel) {
        for job in jobs where !queue.contains(job) {
            failed[job] = nil
            queue.append(job)
        }
        guard !running else { return }
        running = true
        Task { await run(app) }
    }

    /// Tells the screens to read the files again.
    func touch() { changes += 1 }

    /// Stops the downloads of a book: the chapters that wait, and the chapter that downloads now.
    func cancel(_ book: Book.ID) {
        queue.removeAll { $0.book == book && $0 != queue.first }
        if queue.first?.book == book { current?.cancel() }
        failed = failed.filter { $0.key.book != book }
    }

    /// Downloads the chapters of a book that did not download, again.
    func retry(_ book: Book.ID, app: AppModel) {
        enqueue(failed.keys.filter { $0.book == book }.sorted { $0.chapter < $1.chapter }, app: app)
    }

    private func run(_ app: AppModel) async {
        while let job = queue.first {
            progress = (0, 0)
            let task = Task {
                try await app.downloadChapter(job.book, index: job.chapter) { done, total in
                    Task { @MainActor in self.progress = (done, total) }
                }
            }
            current = task
            do {
                try await task.value
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                failed[job] = error.localizedDescription
            }
            current = nil
            // A book that the user deleted while its chapter downloaded leaves no folder.
            if app.book(job.book) == nil { app.removeFolder(of: job.book) }
            queue.removeFirst()
            progress = nil
            changes += 1
        }
        running = false
    }
}

extension AppModel {
    private func chapterAndFolder(_ id: Book.ID, _ index: Int) -> (Book, Novel.Chapter, URL)? {
        guard let book = book(id), let novel = novel(of: book), novel.chapters.indices.contains(index) else { return nil }
        return (book, novel.chapters[index], folder(of: book))
    }

    /// The pages of a chapter on the device, or nil when it did not download.
    func downloadedPages(_ id: Book.ID, index: Int) -> [URL]? {
        guard let (_, chapter, folder) = chapterAndFolder(id, index) else { return nil }
        let pages = ChapterDownload.pages(of: chapter, in: folder)
        return pages.isEmpty ? nil : pages
    }

    func isDownloaded(_ id: Book.ID, index: Int) -> Bool {
        guard let (book, chapter, folder) = chapterAndFolder(id, index) else { return false }
        if book.format == .novel { return FileManager.default.fileExists(atPath: folder.appendingPathComponent(chapter.path).path) }
        return ChapterDownload.isDownloaded(chapter, in: folder)
    }

    /// Asks the source for the pages of a chapter, and keeps them on the device.
    func downloadChapter(_ id: Book.ID, index: Int, progress: @escaping @Sendable (Int, Int) -> Void) async throws {
        guard let (book, chapter, folder) = chapterAndFolder(id, index), let remote = chapter.remote, let origin = book.origin else { return }
        guard let installed = installed(for: book) else { throw ChapterFault.sourceGone }
        // A chapter of a novel is one file, which the reader of novels downloads too.
        if book.format == .novel {
            _ = try await chapterFile(of: book, index: index)
            progress(1, 1)
            return
        }
        guard !ChapterDownload.isDownloaded(chapter, in: folder) else { return }
        let source = try await load(installed)
        let content = try await source.content(of: OnlineChapter(id: remote, title: chapter.title ?? ""), in: OnlineSeries(id: origin.series, title: book.title))
        guard case let .pages(requests) = content else { throw ChapterFault.notPages }
        try await ChapterDownload.download(requests, chapter: chapter, in: folder, fetcher: appFetcher, progress: progress)
    }

    /// Removes the downloaded pages of each chapter of a book.
    func removeDownloads(_ id: Book.ID) {
        guard let book = book(id), let novel = novel(of: book) else { return }
        for chapter in novel.chapters {
            if book.format == .novel {
                try? FileManager.default.removeItem(at: folder(of: book).appendingPathComponent(chapter.path))
            } else {
                ChapterDownload.remove(chapter, in: folder(of: book))
            }
        }
        downloads.touch()
    }

    /// Removes the downloads of the chapters before `end`, which are the chapters that the user read.
    func removeDownloads(_ id: Book.ID, before end: Int) {
        guard let book = book(id), let novel = novel(of: book) else { return }
        for (index, chapter) in novel.chapters.enumerated() where index < end {
            if book.format == .novel {
                try? FileManager.default.removeItem(at: folder(of: book).appendingPathComponent(chapter.path))
            } else {
                ChapterDownload.remove(chapter, in: folder(of: book))
            }
        }
        downloads.touch()
    }

    /// The number of chapters of a book that downloaded.
    func downloadedCount(_ id: Book.ID) -> Int {
        guard let novel = book(id).flatMap(novel(of:)) else { return 0 }
        return novel.chapters.indices.filter { isDownloaded(id, index: $0) }.count
    }

    /// Downloads each chapter of a book from `start` that is not on the device.
    func downloadChapters(_ id: Book.ID, from start: Int = 0) {
        guard let novel = book(id).flatMap(novel(of:)) else { return }
        let jobs = novel.chapters.indices.filter { $0 >= start && !isDownloaded(id, index: $0) }.map { Downloads.Job(book: id, chapter: $0) }
        downloads.enqueue(jobs, app: self)
    }
}
