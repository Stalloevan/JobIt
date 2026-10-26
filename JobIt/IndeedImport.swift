import Foundation
import SwiftUI

struct IndeedItem: Codable {
    let jk: String
    let title: String
    let company: String
    let location: String
    let snippet: String
    let salary: String
    let easy: Bool
}

extension WebController {
    /// Reads the job cards on the current Indeed results page with indeed.js.
    func scrapeIndeed() async -> [IndeedItem]? {
        guard let wv = webView,
              let scriptURL = Bundle.main.url(forResource: "indeed", withExtension: "js"),
              let script = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            return nil
        }
        let call = script + "\n;window.__jobitIndeed();"
        return await withCheckedContinuation { (cont: CheckedContinuation<[IndeedItem]?, Never>) in
            wv.evaluateJavaScript(call) { value, _ in
                guard let text = value as? String,
                      let bytes = text.data(using: .utf8),
                      let items = try? JSONDecoder().decode([IndeedItem].self, from: bytes) else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: items)
            }
        }
    }

    func load(_ url: URL) {
        webView?.load(URLRequest(url: url))
    }
}

/// Reads Indeed search results page by page in a visible web view, so a human check can be
/// completed by hand if Indeed shows one. Pages are read slowly, with a pause between each.
@MainActor
final class IndeedImporter: ObservableObject {
    @Published var status = "Loading Indeed..."
    @Published var needsHuman = false
    @Published var finished = false
    @Published var foundCount = 0
    @Published var addedCount = 0

    let web = WebController()
    let keywords: String
    let location: String
    let maxPages: Int

    private weak var store: Store?
    private var scraped: [Job] = []
    private var seen = Set<String>()
    private var page = 0
    private var extracting = false

    init(store: Store, keywords: String, location: String, maxPages: Int) {
        self.store = store
        self.keywords = keywords
        self.location = location
        self.maxPages = maxPages
    }

    var firstURL: URL? {
        JobSites.indeedSearch(keywords: keywords, location: location, start: 0)
    }

    func pageLoaded() {
        Task { await extract() }
    }

    func retry() {
        Task { await extract() }
    }

    func stop() {
        Task { await finish() }
    }

    private func extract() async {
        if extracting || finished { return }
        extracting = true
        defer { extracting = false }

        try? await Task.sleep(nanoseconds: 1_500_000_000)
        if finished { return }

        guard let items = await web.scrapeIndeed() else {
            status = "Could not read this page."
            return
        }

        if items.isEmpty {
            if page == 0 {
                needsHuman = true
                status = "No jobs found yet. If Indeed shows a check, complete it, then tap Continue."
            } else {
                await finish()
            }
            return
        }

        needsHuman = false
        add(items)
        page += 1
        if page >= maxPages {
            await finish()
            return
        }

        status = "Read \(foundCount) jobs. Loading page \(page + 1)..."
        let pause = UInt64.random(in: 2_000_000_000...4_000_000_000)
        try? await Task.sleep(nanoseconds: pause)
        if finished { return }
        if let next = JobSites.indeedSearch(keywords: keywords, location: location, start: page * 10) {
            web.load(next)
        } else {
            await finish()
        }
    }

    private func add(_ items: [IndeedItem]) {
        for it in items where !it.jk.isEmpty && !seen.contains(it.jk) {
            seen.insert(it.jk)
            let desc = (it.easy ? "Easily apply. " : "") + it.salary + " " + it.snippet
            scraped.append(
                Job(
                    id: "in-" + it.jk,
                    title: it.title,
                    company: it.company,
                    location: it.location,
                    url: "https://www.indeed.com/viewjob?jk=" + it.jk,
                    descriptionText: desc,
                    source: "Indeed",
                    postedAt: Date(),
                    applicants: nil,
                    salaryMin: JobFetcher.guessSalaryMin(it.salary + " " + it.snippet),
                    status: .new
                )
            )
        }
        foundCount = scraped.count
    }

    private func finish() async {
        if finished { return }
        finished = true
        needsHuman = false
        if scraped.isEmpty {
            status = "Nothing was found. You can still browse Indeed and save jobs by hand."
            return
        }
        status = "Filtering with your criteria..."
        if let store = store {
            addedCount = await store.importIndeed(scraped)
        }
        status = "Read \(foundCount) jobs. \(addedCount) match your criteria and are in your queue."
    }
}
