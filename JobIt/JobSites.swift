import Foundation

/// LinkedIn and Indeed have no public job feed, so jobs are found by searching inside the app's
/// browser and saving the ones you open. These helpers build the searches and clean up links.
enum JobSites {
    static func linkedInSearch(keywords: String, location: String, easyApplyOnly: Bool) -> URL? {
        var c = URLComponents(string: "https://www.linkedin.com/jobs/search/")
        var items = [
            URLQueryItem(name: "keywords", value: keywords),
            URLQueryItem(name: "location", value: location),
            URLQueryItem(name: "f_TPR", value: "r604800"),
            URLQueryItem(name: "f_E", value: "1,2"),
            URLQueryItem(name: "sortBy", value: "DD")
        ]
        if easyApplyOnly {
            items.append(URLQueryItem(name: "f_AL", value: "true"))
        }
        c?.queryItems = items
        return c?.url
    }

    static func indeedSearch(keywords: String, location: String) -> URL? {
        var c = URLComponents(string: "https://www.indeed.com/jobs")
        c?.queryItems = [
            URLQueryItem(name: "q", value: keywords),
            URLQueryItem(name: "l", value: location),
            URLQueryItem(name: "fromage", value: "7"),
            URLQueryItem(name: "sort", value: "date")
        ]
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

        if host.contains("linkedin.com") {
            var jobID: String?
            if let v = value("currentJobId"), !v.isEmpty {
                jobID = v
            } else if comps.path.contains("/jobs/view/") {
                let runs = comps.path.split(whereSeparator: { !$0.isNumber }).map(String.init).filter { $0.count >= 6 }
                jobID = runs.last
            }
            if let id = jobID {
                return ("li-" + id, "https://www.linkedin.com/jobs/view/" + id, "LinkedIn")
            }
            return (fallbackID, trimmed, "LinkedIn")
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
    /// Jobs you added or saved yourself are never dropped when the queue refreshes.
    var isManual: Bool {
        id.hasPrefix("manual-") || id.hasPrefix("li-") || id.hasPrefix("in-")
    }
}
