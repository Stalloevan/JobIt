import Foundation

enum JobStatus: String, Codable {
    case new, approved, applied, undesired
}

struct Job: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var company: String
    var location: String
    var url: String
    var descriptionText: String
    var source: String
    var postedAt: Date?
    var applicants: Int?
    var salaryMin: Int?
    var status: JobStatus
}

enum SortMode: String, Codable, CaseIterable, Identifiable {
    case bestFit, fewestApplicants, newest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bestFit: return "Best fit, then fewest applicants"
        case .fewestApplicants: return "Fewest applicants"
        case .newest: return "Newest"
        }
    }
}

struct Criteria: Codable, Equatable {
    var includeKeywords: [String]
    var excludeKeywords: [String]
    var locations: [String]
    var remoteOnly: Bool
    var minSalary: Int
    var minSatisfaction: Double
    var allowUnrated: Bool
    var blockedCompanies: [String]
    var blockedTerms: [String]
    var sortMode: SortMode

    static let starter = Criteria(
        includeKeywords: Criteria.defaultInclude,
        excludeKeywords: Criteria.defaultExclude,
        locations: ["rhode island", "providence", "massachusetts", "boston", "connecticut", "remote"] + Criteria.extraLocations,
        remoteOnly: false,
        minSalary: 0,
        minSatisfaction: 0,
        allowUnrated: true,
        blockedCompanies: [
            "lockheed", "raytheon", "rtx", "northrop", "general dynamics", "bae systems",
            "l3harris", "leidos", "booz allen", "saic", "caci", "huntington ingalls",
            "anduril", "palantir", "textron", "leonardo drs", "mantech", "peraton",
            "electric boat", "sikorsky", "kratos", "boeing defense"
        ],
        blockedTerms: [
            "security clearance", "department of defense", "defense contractor",
            "munitions", "weapons system", "missile", "dod contract"
        ],
        sortMode: .bestFit
    )

    static let defaultInclude: [String] = [
        "industrial", "process", "quality", "operations", "supply chain", "logistics", "manufacturing",
        "production", "continuous improvement", "lean", "analyst", "planner", "coordinator", "specialist",
        "project", "program", "associate", "technician", "procurement", "sourcing", "buyer", "inventory",
        "systems", "data", "engineer", "consultant", "scheduler", "optimization", "forecast"
    ]

    static let defaultExclude: [String] = [
        "senior", "sr.", "sr ", "director", "principal", "staff", "vice president", "vp ", "manager"
    ]

    static let newLocations: [String] = [
        "new hampshire", ", nh", "new york", ", ny", "vermont", ", vt"
    ]

    /// Postings often write "Cambridge, MA" without the state name, so match these too.
    static let extraLocations: [String] = [
        "cambridge", "somerville", "worcester", "hartford", "new haven", "stamford",
        "new england", ", ma", ", ri", ", ct"
    ]

    static let resumeSkills: [String] = [
        "python", "optimization", "simulation", "simio", "solidworks", "six sigma", "lean",
        "matlab", "r studio", "statistics", "data analysis", "manufacturing", "quality",
        "process improvement", "supply chain", "operations", "excel", "autodesk", "bash",
        "automation", "workflow"
    ]
}

struct AnswerEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var question: String
    var answer: String
    var perApplication: Bool

    var key: String { AnswerEntry.normalize(question) }

    static func normalize(_ s: String) -> String {
        let mapped = s.lowercased().map { ($0.isLetter || $0.isNumber) ? $0 : Character(" ") }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    static func blank(_ q: String, individual: Bool = false) -> AnswerEntry {
        AnswerEntry(question: q, answer: "", perApplication: individual)
    }

    static let seed: [AnswerEntry] = [
        blank("First name"), blank("Last name"), blank("Full name"), blank("Email"),
        blank("Phone"), blank("City"), blank("State"), blank("Zip code"),
        blank("LinkedIn"), blank("Website"), blank("GitHub"),
        blank("Are you legally authorized to work in the United States"),
        blank("Will you now or in the future require sponsorship"),
        blank("Salary expectations", individual: true),
        blank("Why do you want to work here", individual: true),
        blank("Cover letter", individual: true),
        blank("How did you hear about us")
    ]
}

enum AppState: String, Codable, CaseIterable, Identifiable {
    case applied, followedUp, interview, offer, closed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .applied: return "Applied"
        case .followedUp: return "Followed up"
        case .interview: return "Interviewing"
        case .offer: return "Offer"
        case .closed: return "Closed"
        }
    }
}

struct Application: Identifiable, Codable, Hashable {
    var id = UUID()
    var jobID: String
    var title: String
    var company: String
    var url: String
    var appliedAt: Date
    var contactEmail: String = ""
    var state: AppState = .applied
    var followUpDue: Date
    var followUpCount: Int = 0
    var followUpDraft: String

    var isActive: Bool { state == .applied || state == .followedUp }
}

struct Recruiter: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var firm: String
    var email: String
    var notes: String = ""
    var addedAt: Date = Date()
    var lastContact: Date?
    var checkInEveryDays: Int = 21

    var nextCheckIn: Date {
        Calendar.current.date(byAdding: .day, value: checkInEveryDays, to: lastContact ?? addedAt) ?? addedAt
    }

    var isDue: Bool { nextCheckIn <= Date() }
}

enum BoardKind: String, Codable, CaseIterable, Identifiable {
    case greenhouse, lever

    var id: String { rawValue }

    var label: String { self == .greenhouse ? "Greenhouse" : "Lever" }
}

struct Board: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: BoardKind
    var token: String
    var displayName: String

    /// Boards checked against the live APIs on 2026-10-26; each had open roles in operations,
    /// quality, supply chain, process or analysis.
    static let starter: [Board] = [
        Board(kind: .greenhouse, token: "formlabs", displayName: "Formlabs"),
        Board(kind: .greenhouse, token: "markforged", displayName: "Markforged"),
        Board(kind: .greenhouse, token: "ginkgobioworks", displayName: "Ginkgo Bioworks"),
        Board(kind: .greenhouse, token: "beamtherapeutics", displayName: "Beam Therapeutics"),
        Board(kind: .greenhouse, token: "flexport", displayName: "Flexport"),
        Board(kind: .greenhouse, token: "instacart", displayName: "Instacart"),
        Board(kind: .greenhouse, token: "samsara", displayName: "Samsara"),
        Board(kind: .greenhouse, token: "toast", displayName: "Toast"),
        Board(kind: .greenhouse, token: "carvana", displayName: "Carvana"),
        Board(kind: .greenhouse, token: "stripe", displayName: "Stripe"),
        Board(kind: .greenhouse, token: "affirm", displayName: "Affirm"),
        Board(kind: .greenhouse, token: "klaviyo", displayName: "Klaviyo"),
        Board(kind: .lever, token: "wealthfront", displayName: "Wealthfront")
    ]
}

struct AppData: Codable {
    var criteria = Criteria.starter
    var jobs: [Job] = []
    var answers: [AnswerEntry] = AnswerEntry.seed
    var applications: [Application] = []
    var recruiters: [Recruiter] = []
    var boards: [Board] = []
    var companyRatings: [String: Double] = [:]
    var fitSkills: [String] = Criteria.resumeSkills
    var reminderHour: Int = 9
}
