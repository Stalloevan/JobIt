import Foundation

enum JobSites {
    /// Indeed search for the last 7 days, newest first. `start` is the result offset (10 per page).
    static func indeedSearch(keywords: String, location: String, start: Int = 0) -> URL? {
        var c = URLComponents(string: "https://www.indeed.com/jobs")
        var items = [
            URLQueryItem(name: "q", value: keywords),
            URLQueryItem(name: "l", value: location),
            URLQueryItem(name: "fromage", value: "7"),
            URLQueryItem(name: "sort", value: "date")
        ]
        if start > 0 {
            items.append(URLQueryItem(name: "start", value: String(start)))
        }
        c?.queryItems = items
        return c?.url
    }

    /// Turns a pasted or captured link into a stable job id and a clean link, so saving the same
    /// posting twice does not create duplicates.
    static func normalize(_ raw: String) -> (id: String, url: String, source: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackID = "manual-" + UUID().uuidString
        guard let comps = URLComponents(string: trimmed), let host = comps.host?.lowercased() else {
            return (fallbackID, trimmed, "Added by me")
        }
        let query = comps.queryItems ?? []

        func value(_ name: String) -> String? {
            query.first { $0.name == name }?.value
        }

        if host.contains("indeed.com") {
            if let v = value("jk") ?? value("vjk"), !v.isEmpty {
                return ("in-" + v, "https://www.indeed.com/viewjob?jk=" + v, "Indeed")
            }
            return (fallbackID, trimmed, "Indeed")
        }

        return (fallbackID, trimmed, "Added by me")
    }
}

extension Job {
    /// Postings fetched from company boards. Only these are replaced when the board queue refreshes.
    var isBoardJob: Bool {
        id.hasPrefix("gh-") || id.hasPrefix("lv-") || id.hasPrefix("ab-") || id.hasPrefix("sr-")
    }
}
