import SwiftUI

struct RecruitersView: View {
    @EnvironmentObject var store: Store
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.data.recruiters) { r in
                    NavigationLink {
                        RecruiterDetailView(id: r.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.name).font(.headline)
                            if !r.firm.isEmpty {
                                Text(r.firm).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text(r.isDue
                                 ? "Check-in due"
                                 : "Next check-in \(r.nextCheckIn.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(r.isDue ? Color.orange : Color.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    store.data.recruiters.remove(atOffsets: offsets)
                }
            }
            .overlay {
                if store.data.recruiters.isEmpty {
                    ContentUnavailableView(
                        "No recruiters yet",
                        systemImage: "person.2",
                        description: Text("Recruiters have worked best for you. Add them here and get a drafted check-in every few weeks.")
                    )
                }
            }
            .navigationTitle("Recruiters")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddRecruiterView() }
        }
    }
}

struct AddRecruiterView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var firm = ""
    @State private var email = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Firm", text: $firm)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .navigationTitle("New recruiter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.data.recruiters.append(
                            Recruiter(
                                name: name.trimmingCharacters(in: .whitespaces),
                                firm: firm.trimmingCharacters(in: .whitespaces),
                                email: email.trimmingCharacters(in: .whitespaces)
                            )
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct RecruiterDetailView: View {
    @EnvironmentObject var store: Store
    let id: UUID

    private var idx: Int? {
        store.data.recruiters.firstIndex { $0.id == id }
    }

    var body: some View {
        if let i = idx {
            let draft = Drafts.recruiter(
                name: store.data.recruiters[i].name,
                firm: store.data.recruiters[i].firm,
                myName: store.applicantName
            )
            Form {
                Section {
                    TextField("Name", text: $store.data.recruiters[i].name)
                    TextField("Firm", text: $store.data.recruiters[i].firm)
                    TextField("Email", text: $store.data.recruiters[i].email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Stepper(
                        "Check in every \(store.data.recruiters[i].checkInEveryDays) days",
                        value: $store.data.recruiters[i].checkInEveryDays,
                        in: 7...90,
                        step: 7
                    )
                }

                Section("Notes") {
                    TextEditor(text: $store.data.recruiters[i].notes)
                        .frame(minHeight: 80)
                }

                Section("Suggested check-in") {
                    Text(draft).font(.callout)
                    if let url = mailURL(
                        to: store.data.recruiters[i].email,
                        subject: "Checking in",
                        body: draft
                    ) {
                        Link(destination: url) {
                            Label("Open in Mail", systemImage: "envelope.open")
                        }
                    }
                    ShareLink(item: draft) {
                        Label("Share or copy", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        store.data.recruiters[i].lastContact = Date()
                    } label: {
                        Label("I contacted them today", systemImage: "checkmark")
                    }
                }
            }
            .navigationTitle(store.data.recruiters[i].name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            Text("This recruiter was removed.")
        }
    }
}
