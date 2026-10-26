import Foundation

/// Downloads the daily job feed (built by a GitHub Action from thousands of company boards).
enum FeedClient {
    static let feedURL = URL(string: "https://raw.githubusercontent.com/Stalloevan/JobIt/feed/jobs.json")!

    private struct Record: Decodable {
        let i: String
        let t: String
        let c: String
        let l: String
        let u: String
        let p: Double?
        let s: Int?
        let d: String?
    }

    enum FeedError: LocalizedError {
        case http(Int)
        var errorDescription: String? {
            switch self {
            case .http(let code): return "The job feed returned an error (\(code))."
            }
        }
    }

    /// Fetches and decodes the feed. Decoding runs off the main thread.
    static func fetch() async throws -> [Job] {
        var request = URLRequest(url: feedURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw FeedError.http(http.statusCode)
        }
        return try await Task.detached(priority: .userInitiated) {
            let records = try JSONDecoder().decode([Record].self, from: data)
            return records.map { r in
                Job(
                    id: r.i,
                    title: r.t,
                    company: r.c,
                    location: r.l,
                    url: r.u,
                    descriptionText: r.d ?? "",
                    source: sourceName(r.i),
                    postedAt: (r.p ?? 0) > 0 ? Date(timeIntervalSince1970: r.p ?? 0) : nil,
                    applicants: nil,
                    salaryMin: (r.s ?? 0) > 0 ? r.s : nil,
                    status: .new
                )
            }
        }.value
    }

    private static func sourceName(_ id: String) -> String {
        if id.hasPrefix("gh-") { return "Greenhouse" }
        if id.hasPrefix("lv-") { return "Lever" }
        if id.hasPrefix("ab-") { return "Ashby" }
        if id.hasPrefix("sr-") { return "SmartRecruiters" }
        return "Company"
    }
}
