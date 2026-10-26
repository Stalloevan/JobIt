import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published var data: AppData {
        didSet { scheduleSave() }
    }
    @Published var isRefreshing = false
    @Published var lastError: String?

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("jobit.json")
        fileURL = url
        if let raw = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(AppData.self, from: raw) {
            data = decoded
        } else {
            data = AppData()
        }
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

    // MARK: Queue

    var queue: [Job] {
        let c = data.criteria
        let items = data.jobs.filter {
            $0.status == .new && Matching.passes($0, criteria: c, ratings: data.companyRatings)
        }
        return Matching.sorted(items, mode: c.sortMode, include: c.includeKeywords, skills: data.fitSkills)
    }

    var approved: [Job] { data.jobs.filter { $0.status == .approved } }
    var undesired: [Job] { data.jobs.filter { $0.status == .undesired } }

    var dueFollowUps: [Application] {
        data.applications.filter { $0.isActive && $0.followUpDue <= Date() }
    }

    var dueRecruiters: [Recruiter] { data.recruiters.filter { $0.isDue } }

    var needsAnswer: [AnswerEntry] {
        data.answers.filter { $0.answer.trimmingCharacters(in: .whitespaces).isEmpty && !$0.perApplication }
    }

    func fit(_ job: Job) -> Int {
        Matching.fit(job, include: data.criteria.includeKeywords, skills: data.fitSkills)
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
        isRefreshing = true
        lastError = nil
        var found: [Job] = []
        var errors: [String] = []
        for board in data.boards {
            do {
                found += try await JobFetcher.fetch(board)
            } catch {
                errors.append("\(board.displayName): \(error.localizedDescription)")
            }
        }
        var jobs = data.jobs
        var known = Set(jobs.map { $0.id })
        for j in found where !known.contains(j.id) {
            jobs.append(j)
            known.insert(j.id)
        }
        data.jobs = jobs
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

    func addManual(title: String, company: String, url: String, location: String) {
        let job = Job(
            id: "manual-" + UUID().uuidString,
            title: title,
            company: company,
            location: location,
            url: url,
            descriptionText: "",
            source: "Added by me",
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
