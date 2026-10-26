import Foundation

enum Matching {
    static func searchText(_ j: Job) -> String {
        (j.title + " " + j.company + " " + j.location + " " + j.descriptionText).lowercased()
    }

    static func ratingKey(_ company: String) -> String {
        company.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// Cheap checks on short fields run first so most postings are rejected before their
    /// description is ever scanned.
    static func passes(_ j: Job, criteria c: Criteria, ratings: [String: Double]) -> Bool {
        let title = j.title.lowercased()
        let company = j.company.lowercased()
        let loc = j.location.lowercased()

        for b in c.blockedCompanies where !b.isEmpty && company.contains(b.lowercased()) {
            return false
        }
        for k in c.excludeKeywords where !k.isEmpty && title.contains(k.lowercased()) {
            return false
        }

        let isRemote = loc.contains("remote") || title.contains("remote")
        if c.remoteOnly {
            if !isRemote { return false }
        } else if !c.locations.isEmpty {
            let inArea = c.locations.contains { !$0.isEmpty && loc.contains($0.lowercased()) }
            if !inArea && !isRemote { return false }
        }

        if c.minSalary > 0, let s = j.salaryMin, s < c.minSalary {
            return false
        }

        if c.minSatisfaction > 0 {
            if let r = ratings[ratingKey(j.company)] {
                if r < c.minSatisfaction { return false }
            } else if !c.allowUnrated {
                return false
            }
        }

        // Description-based checks, only for postings that survived the cheap ones.
        if !c.includeKeywords.isEmpty {
            let hit = c.includeKeywords.contains { !$0.isEmpty && title.contains($0.lowercased()) }
            if !hit { return false }
        }
        let text = title + " " + company + " " + loc + " " + j.descriptionText.lowercased()
        for term in c.blockedTerms where !term.isEmpty && text.contains(term.lowercased()) {
            return false
        }
        return true
    }

    /// 0...100. Title match on your target keywords counts most, resume skills in the description add the rest.
    static func fit(_ j: Job, include: [String], skills: [String]) -> Int {
        let title = j.title.lowercased()
        let text = searchText(j)
        var score = 0
        if include.contains(where: { !$0.isEmpty && title.contains($0.lowercased()) }) {
            score += 40
        }
        var hits = 0
        for s in skills where !s.isEmpty && text.contains(s.lowercased()) {
            hits += 1
        }
        score += min(60, hits * 10)
        return min(100, score)
    }

    private static func applicantsKey(_ j: Job) -> Int {
        j.applicants ?? Int.max
    }

    /// `fitOf` is supplied by the caller so fit scores can be cached.
    static func sorted(_ jobs: [Job], mode: SortMode, fitOf: (Job) -> Int) -> [Job] {
        var scored: [(job: Job, fit: Int)] = []
        for j in jobs {
            scored.append((job: j, fit: fitOf(j)))
        }
        scored.sort { a, b in
            switch mode {
            case .bestFit:
                if a.fit != b.fit { return a.fit > b.fit }
                return applicantsKey(a.job) < applicantsKey(b.job)
            case .fewestApplicants:
                let x = applicantsKey(a.job)
                let y = applicantsKey(b.job)
                if x != y { return x < y }
                return a.fit > b.fit
            case .newest:
                let x = a.job.postedAt ?? Date.distantPast
                let y = b.job.postedAt ?? Date.distantPast
                return x > y
            }
        }
        return scored.map { $0.job }
    }
}
