import Foundation

enum Drafts {
    static func followUp(title: String, company: String, appliedAt: Date, count: Int, name: String) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        let when = df.string(from: appliedAt)
        let signoff = name.isEmpty ? "Best regards" : "Best regards,\n\(name)"

        if count == 0 {
            return "Hello,\n\nI applied for the \(title) position at \(company) on \(when) and wanted to confirm my application was received. I'm very interested in the role and would welcome the chance to talk about how my background fits the team. Is there anything else you need from me?\n\nThank you for your time.\n\n\(signoff)"
        }
        if count == 1 {
            return "Hello,\n\nI'm following up on my application for the \(title) role at \(company). I remain very interested and am happy to provide anything that would help with your review. Could you share where the hiring process stands?\n\nThank you again.\n\n\(signoff)"
        }
        return "Hello,\n\nI wanted to check in one last time about the \(title) role at \(company). If the position has been filled or the team has gone another direction, I'd appreciate knowing, and I'd welcome being considered for future openings.\n\nThank you for your time.\n\n\(signoff)"
    }

    static func recruiter(name: String, firm: String, myName: String) -> String {
        let first = name.split(separator: " ").first.map(String.init) ?? name
        let signoff = myName.isEmpty ? "Thanks" : "Thanks,\n\(myName)"
        let firmLine = firm.isEmpty ? "" : " at \(firm)"
        return "Hi \(first),\n\nI hope you're doing well. I wanted to check in\(firmLine) and let you know I'm still actively looking for operations, quality and process-improvement roles. If anything comes across your desk that could be a fit, I'd love to hear about it.\n\n\(signoff)"
    }
}
