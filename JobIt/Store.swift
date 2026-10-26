import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published var data: AppData {
        didSet { dataDidChange(oldValue) }
    }
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var lastFetchTotal = 0
    @Published var lastFetchKept = 0

    /// Set when criteria or boards change, so leaving the Criteria tab can trigger a refresh.
    var criteriaChangedSinceRefresh = false

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?
    private var queueCache: [Job]?
    private var hiddenCache: Int?
    private var passCache: [String: Bool] = [:]
    private var fitCache: [String: Int] = [:]

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("jobit.json")
        fileURL = url
        if let raw = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(AppData.self, from: raw) {
            data = decoded
        } else {
            data = AppData()
        }
        migrate()
    }

    /// One-time upgrades for installs that predate later versions.
    private func migrate() {
        let defaults = UserDefaults.standard

        if !defaults.bool(forKey: "jobit.migrated.v12") {
            defaults.set(true, forKey: "jobit.migrated.v12")
            if data.boards.isEmpty {
                data.boards = Board.starter
            }
            var locations = data.criteria.locations
            for term in Criteria.extraLocations where !locations.contains(term) {
                locations.append(term)
            }
            data.criteria.locations = locations
        }

        if !defaults.bool(forKey: "jobit.migrated.v13") {
            defaults.set(true, forKey: "jobit.migrated.v13")
            // v1.2 saved every fetched posting with its full text. Keep only jobs you acted on, shrunk.
            var kept: [Job] = []
            for var j in data.jobs where j.status != .new || j.isManual {
                j.descriptionText = String(j.descriptionText.prefix(2500))
                kept.append(j)
            }
            data.jobs = kept
        }
    }

    private func dataDidChange(_ old: AppData) {
        queueCache = nil
        hiddenCache = nil
        let criteriaChanged = old.criteria != data.criteria
        if criteriaChanged || old.companyRatings != data.companyRatings || old.fitSkills != data.fitSkills {
            passCache.removeAll()
            fitCache.removeAll()
        }
        if criteriaChanged || old.boards != data.boards {
            criteriaChangedSinceRefresh = true
        }
        scheduleSave()
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = data
        let url = fileURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            if let raw = try? JSONEncoder().encode(snapshot) {
                try? raw.write(to: url, options: .atomic)
            }
        }
    }

    func saveNow() {
        saveTask?.cancel()
        if let raw = try? JSONEncoder().encode(data) {
            try? raw.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Queue (results are cached; the cache is cleared whenever data changes)

    private func passes(_ job: Job) -> Bool {
        if let cached = passCache[job.id] { return cached }
        let result = Matching.passes(job, criteria: data.criteria, ratings: data.companyRatings)
        passCache[job.id] = result
        return result
    }

    func fit(_ job: Job) -> Int {
        if let cached = fitCache[job.id] { return cached }
        let result = Matching.fit(job, include: data.criteria.includeKeywords, skills: data.fitSkills)
        fitCache[job.id] = result
        return result
    }

    var queue: [Job] {
        if let cached = queueCache { return cached }
        let items = data.jobs.filter { $0.status == .new && passes($0) }
        let sorted = Matching.sorted(items, mode: data.criteria.sortMode, fitOf: { fit($0) })
        queueCache = sorted
        return sorted
    }

    var approved: [Job] { data.jobs.filter { $0.status == .approved } }
    var undesired: [Job] { data.jobs.filter { $0.status == .undesired } }

    /// New jobs that are stored but filtered out by the current criteria.
    var hiddenCount: Int {
        if let cached = hiddenCache { return cached }
        let count = data.jobs.filter { $0.status == .new && !passes($0) }.count
        hiddenCache = count
        return count
    }

    var dueFollowUps: [Application] {
        data.applications.filter { $0.isActive && $0.followUpDue <= Date() }
    }

    var dueRecruiters: [Recruiter] { data.recruiters.filter { $0.isDue } }

    var needsAnswer: [AnswerEntry] {
        data.answers.filter { $0.answer.trimmingCharacters(in: .whitespaces).isEmpty && !$0.perApplication }
    }

    var applicantName: String {
        let full = answer(forKey: "full name")
        if !full.isEmpty { return full }
        let first = answer(forKey: "first name")
        let last = answer(forKey: "last name")
        return (first + " " + last).trimmingCharacters(in: .whitespaces)
    }

    func answer(forKey key: String) -> String {
        data.answers.first { $0.key == key }?.answer ?? ""
    }

    var dailyNudge: String {
        if !dueFollowUps.isEmpty {
            return "\(dueFollowUps.count) follow-up draft(s) are ready for you to approve."
        }
        if !approved.isEmpty {
            return "\(approved.count) application(s) are ready. One tap to start."
        }
        let n = queue.count
        if n > 0 {
            return "\(n) new match(es). Swipe right on the good ones."
        }
        return "Nothing urgent today. Pull to refresh for new matches."
    }

    // MARK: Jobs

    func refresh() async {
        if isRefreshing { return }
        isRefreshing = true
        lastError = nil
        criteriaChangedSinceRefresh = false

        var found: [Job] = []
        var errors: [String] = []
        for board in data.boards {
            do {
                found += try await JobFetcher.fetch(board)
            } catch {
                errors.append("\(board.displayName): \(error.localizedDescription)")
            }
        }

        // Filter off the main thread, and only keep postings that match, so thousands of
        // irrelevant listings are never stored or scanned again.
        let candidates = found
        let criteria = data.criteria
        let ratings = data.companyRatings
        let kept = await Task.detached(priority: .userInitiated) {
            candidates.filter { Matching.passes($0, criteria: criteria, ratings: ratings) }
        }.value

        var jobs = data.jobs
        if errors.isEmpty {
            jobs = jobs.filter { $0.status != .new || $0.isManual }
        }
        var known = Set(jobs.map { $0.id })
        for j in kept where !known.contains(j.id) {
            jobs.append(j)
            known.insert(j.id)
        }
        data.jobs = jobs

        lastFetchTotal = found.count
        lastFetchKept = kept.count
        if !errors.isEmpty {
            lastError = errors.joined(separator: "\n")
        }
        isRefreshing = false
    }

    private func setStatus(_ ids: Set<String>, _ status: JobStatus) {
        var jobs = data.jobs
        for i in jobs.indices where ids.contains(jobs[i].id) {
            jobs[i].status = status
        }
        data.jobs = jobs
    }

    func approve(_ job: Job) { setStatus([job.id], .approved) }
    func approveAll(_ jobs: [Job]) { setStatus(Set(jobs.map { $0.id }), .approved) }
    func unapprove(_ job: Job) { setStatus([job.id], .new) }
    func markUndesired(_ job: Job) { setStatus([job.id], .undesired) }
    func restore(_ job: Job) { setStatus([job.id], .new) }

    /// Adds a job you found yourself (pasted link, or saved from the LinkedIn/Indeed browser).
    /// Links to the same posting are matched, so saving twice never creates a duplicate.
    func addManual(title: String, company: String, url: String, location: String) {
        let n = JobSites.normalize(url)
        if let existing = data.jobs.first(where: { $0.id == n.id }) {
            if existing.status != .applied {
                setStatus([existing.id], .approved)
            }
            return
        }
        let job = Job(
            id: n.id,
            title: title,
            company: company,
            location: location,
            url: n.url,
            descriptionText: "",
            source: n.source,
            postedAt: Date(),
            applicants: nil,
            salaryMin: nil,
            status: .approved
        )
        data.jobs.append(job)
    }

    func markApplied(_ job: Job) {
        setStatus([job.id], .applied)
        let now = Date()
        let due = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let draft = Drafts.followUp(title: job.title, company: job.company, appliedAt: now, count: 0, name: applicantName)
        data.applications.append(
            Application(
                jobID: job.id,
                title: job.title,
                company: job.company,
                url: job.url,
                appliedAt: now,
                followUpDue: due,
                followUpDraft: draft
            )
        )
    }

    func markFollowUpSent(_ id: UUID) {
        guard let i = data.applications.firstIndex(where: { $0.id == id }) else { return }
        var a = data.applications[i]
        a.followUpCount += 1
        a.state = .followedUp
        a.followUpDue = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        a.followUpDraft = Drafts.followUp(
            title: a.title,
            company: a.company,
            appliedAt: a.appliedAt,
            count: a.followUpCount,
            name: applicantName
        )
        data.applications[i] = a
    }

    // MARK: Answers

    /// New form questions the autofill could not match are saved with a blank answer, so they
    /// show up in the Answers tab once and are filled automatically from then on.
    func recordUnknown(_ labels: [String]) {
        var answers = data.answers
        var keys = Set(answers.map { $0.key })
        for label in labels {
            let k = AnswerEntry.normalize(label)
            if k.isEmpty || keys.contains(k) { continue }
            answers.append(AnswerEntry.blank(label))
            keys.insert(k)
        }
        data.answers = answers
    }

    func fillEntries() -> [FillEntry] {
        data.answers.map { FillEntry(k: $0.key, a: $0.answer, i: $0.perApplication) }
    }
}
