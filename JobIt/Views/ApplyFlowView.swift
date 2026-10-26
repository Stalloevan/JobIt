import SwiftUI

/// Walks through approved jobs one at a time inside the app. Autofill fills what it knows and
/// outlines the rest; you confirm each submission yourself.
struct ApplyFlowView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var jobs: [Job]
    @State private var index = 0
    @State private var sentCount = 0
    @State private var filling = false
    @State private var status = ApplyFlowView.defaultStatus
    @StateObject private var web = WebController()

    private static let defaultStatus = "When the form has loaded, tap Autofill."

    /// The batch is copied when it starts, so approving or submitting jobs mid-batch cannot shift the order.
    init(jobs: [Job]) {
        _jobs = State(initialValue: jobs)
    }

    var body: some View {
        if index < jobs.count {
            content(jobs[index])
        } else {
            doneView
        }
    }

    @ViewBuilder
    private func content(_ job: Job) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title).font(.headline).lineLimit(1)
                    Text("\(job.company) · \(index + 1) of \(jobs.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()

            if let url = URL(string: job.url) {
                WebContainer(url: url, controller: web)
                    .id(job.id)
            } else {
                Text("This job has an invalid link.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(spacing: 8) {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack {
                    Button {
                        Task { await autofill() }
                    } label: {
                        Label("Autofill", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(filling)

                    Button {
                        store.markApplied(job)
                        sentCount += 1
                        advance()
                    } label: {
                        Label("Submitted", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)

                    Button("Skip") {
                        store.unapprove(job)
                        advance()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Batch finished").font(.title2.bold())
            Text("\(sentCount) application(s) logged. Follow-up drafts will be ready in a week.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func advance() {
        index += 1
        status = ApplyFlowView.defaultStatus
    }

    private func autofill() async {
        filling = true
        status = "Filling in what I know..."
        if let r = await web.fill(entries: store.fillEntries()) {
            store.recordUnknown(r.unknown)
            var parts = ["Filled \(r.filled) field(s)."]
            if !r.individual.isEmpty {
                parts.append("\(r.individual.count) need your own answer (orange).")
            }
            if !r.unknown.isEmpty {
                parts.append("\(r.unknown.count) new question(s) saved to Answers (red).")
            }
            status = parts.joined(separator: " ")
        } else {
            status = "Could not read the form yet. Wait for the page to load and try again."
        }
        filling = false
    }
}
