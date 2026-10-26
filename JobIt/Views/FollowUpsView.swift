import SwiftUI

struct FollowUpsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            List {
                let now = Date()
                let due = store.dueFollowUps
                let waiting = store.data.applications.filter { $0.isActive && $0.followUpDue > now }
                let finished = store.data.applications.filter { !$0.isActive }

                if !due.isEmpty {
                    Section("Ready to approve and send") {
                        ForEach(due) { a in row(a) }
                    }
                }
                if !waiting.isEmpty {
                    Section("Waiting") {
                        ForEach(waiting) { a in row(a) }
                    }
                }
                if !finished.isEmpty {
                    Section("Finished") {
                        ForEach(finished) { a in row(a) }
                    }
                }
            }
            .overlay {
                if store.data.applications.isEmpty {
                    ContentUnavailableView(
                        "Nothing sent yet",
                        systemImage: "envelope",
                        description: Text("Once you submit applications, a follow-up draft appears here a week later.")
                    )
                }
            }
            .navigationTitle("Follow-ups")
        }
    }

    private func row(_ a: Application) -> some View {
        NavigationLink {
            ApplicationDetailView(id: a.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(a.title).font(.headline)
                Text(a.company).font(.subheadline).foregroundStyle(.secondary)
                Text("\(a.state.label) · follow-up \(a.followUpDue.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(a.isActive && a.followUpDue <= Date() ? Color.orange : Color.secondary)
            }
        }
    }
}

struct ApplicationDetailView: View {
    @EnvironmentObject var store: Store
    let id: UUID

    private var idx: Int? {
        store.data.applications.firstIndex { $0.id == id }
    }

    var body: some View {
        if let i = idx {
            Form {
                Section {
                    Text(store.data.applications[i].title).font(.headline)
                    Text(store.data.applications[i].company).foregroundStyle(.secondary)
                    Picker("Status", selection: $store.data.applications[i].state) {
                        ForEach(AppState.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    DatePicker(
                        "Follow up on",
                        selection: $store.data.applications[i].followUpDue,
                        displayedComponents: .date
                    )
                    TextField("Recruiter or hiring contact email", text: $store.data.applications[i].contactEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Follow-up draft (edit freely)") {
                    TextEditor(text: $store.data.applications[i].followUpDraft)
                        .frame(minHeight: 220)
                }

                Section {
                    if let url = mailURL(
                        to: store.data.applications[i].contactEmail,
                        subject: "Following up: \(store.data.applications[i].title)",
                        body: store.data.applications[i].followUpDraft
                    ) {
                        Link(destination: url) {
                            Label("Open in Mail", systemImage: "envelope.open")
                        }
                    }
                    ShareLink(item: store.data.applications[i].followUpDraft) {
                        Label("Share or copy draft", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        store.markFollowUpSent(id)
                    } label: {
                        Label("I sent it", systemImage: "checkmark")
                    }
                    if let link = URL(string: store.data.applications[i].url) {
                        Link(destination: link) {
                            Label("Open the job posting", systemImage: "safari")
                        }
                    }
                }
            }
            .navigationTitle("Follow-up")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            Text("This application was removed.")
        }
    }
}
