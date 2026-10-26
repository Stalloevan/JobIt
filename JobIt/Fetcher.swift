import Foundation

enum FetchError: LocalizedError {
    case badURL
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Bad address"
        case .http(let code): return "Server returned \(code)"
        }
    }
}

private struct GHResponse: Decodable {
    let jobs: [GHJob]
}

private struct GHJob: Decodable {
    let id: Int
    let title: String
    let absolute_url: String
    let updated_at: String?
    let location: GHLocation?
    let content: String?
}

private struct GHLocation: Decodable {
    let name: String?
}

private struct LeverPosting: Decodable {
    let id: String
    let text: String
    let hostedUrl: String
    let createdAt: Double?
    let categories: LeverCategories?
    let descriptionPlain: String?
}

private struct LeverCategories: Decodable {
    let location: String?
}

/// Reads the public job-board APIs that Greenhouse and Lever offer. Indeed jobs are read by the
/// in-app importer instead (see IndeedImport.swift).
enum JobFetcher {
    static func fetch(_ board: Board) async throws -> [Job] {
        switch board.kind {
        case .greenhouse: return try await greenhouse(board)
        case .lever: return try await lever(board)
        }
    }

    private static func load(_ address: String) async throws -> Data {
        guard let url = URL(string: address) else { throw FetchError.badURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw FetchError.http(http.statusCode)
        }
        return data
    }

    private static func greenhouse(_ b: Board) async throws -> [Job] {
        let token = b.token.trimmingCharacters(in: .whitespaces)
        let data = try await load("https://boards-api.greenhouse.io/v1/boards/\(token)/jobs?content=true")
        let r = try JSONDecoder().decode(GHResponse.self, from: data)
        let iso = ISO8601DateFormatter()
        return r.jobs.map { j in
            let raw = j.content ?? ""
            // Pay is read from the full text; only a short excerpt is kept to stay light on memory.
            let salary = guessSalaryMin(raw)
            let body = String(stripHTML(String(raw.prefix(8000))).prefix(2500))
            return Job(
                id: "gh-\(token)-\(j.id)",
                title: j.title,
                company: b.displayName,
                location: j.location?.name ?? "",
                url: j.absolute_url,
                descriptionText: body,
                source: "Greenhouse",
                postedAt: j.updated_at.flatMap { iso.date(from: $0) },
                applicants: nil,
                salaryMin: salary,
                status: .new
            )
        }
    }

    private static func lever(_ b: Board) async throws -> [Job] {
        let token = b.token.trimmingCharacters(in: .whitespaces)
        let data = try await load("https://api.lever.co/v0/postings/\(token)?mode=json")
        let postings = try JSONDecoder().decode([LeverPosting].self, from: data)
        return postings.map { p in
            let raw = p.descriptionPlain ?? ""
            let salary = guessSalaryMin(raw)
            let body = String(raw.prefix(2500))
            return Job(
                id: "lv-\(token)-\(p.id)",
                title: p.text,
                company: b.displayName,
                location: p.categories?.location ?? "",
                url: p.hostedUrl,
                descriptionText: body,
                source: "Lever",
                postedAt: p.createdAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                applicants: nil,
                salaryMin: salary,
                status: .new
            )
        }
    }

    static func stripHTML(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "&lt;", with: "<")
        t = t.replacingOccurrences(of: "&gt;", with: ">")
        t = t.replacingOccurrences(of: "&amp;", with: "&")
        t = t.replacingOccurrences(of: "&quot;", with: "\"")
        t = t.replacingOccurrences(of: "&#39;", with: "'")
        t = t.replacingOccurrences(of: "&nbsp;", with: " ")
        t = t.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Best guess: the first dollar figure in the text, usually the low end of a pay range.
    static func guessSalaryMin(_ text: String) -> Int? {
        guard let r = text.range(of: "\\$[0-9]{2,3}(,[0-9]{3}|[kK])", options: .regularExpression) else {
            return nil
        }
        let m = text[r].lowercased()
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        if m.hasSuffix("k") {
            return (Int(m.dropLast()) ?? 0) * 1000
        }
        return Int(m)
    }
}
