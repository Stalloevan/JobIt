import SwiftUI

struct QueueView: View {
    @EnvironmentObject var store: Store
    @AppStorage("queueCardMode") private var cardMode = true
    @State private var applying = false
    @State private var showAdd = false
    @State private var showFind = false
    @State private var didAutoRefresh = false

    var body: some View {
        NavigationStack {
            Group {
                if cardMode {
                    deckScreen
                } else {
                    listScreen
                }
            }
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        cardMode.toggle()
                    } label: {
                        Image(systemName: cardMode ? "list.bullet" : "rectangle.stack")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            store.approveAll(store.queue)
                        } label: {
                            Label("Approve all matches", systemImage: "checkmark.circle")
                        }
                        Button {
                            showFind = true
                        } label: {
                            Label("Find on LinkedIn or Indeed", systemImage: "magnifyingglass")
                        }
                        Button {
                            showAdd = true
                        } label: {
                            Label("Add a job by link", systemImage: "plus")
                        }
                        Button {
                            Task { await store.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        if store.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddJobView() }
            .sheet(isPresented: $showFind) { FindOnSitesView() }
            .fullScreenCover(isPresented: $applying) {
                ApplyFlowView(jobs: store.approved)
            }
            .task {
                if !didAutoRefresh {
                    didAutoRefresh = true
                    await store.refresh()
                }
            }
        }
    }

    private var deckScreen: some View {
        VStack(spacing: 0) {
            if !store.approved.isEmpty {
                Button {
                    applying = true
                } label: {
                    Label("Apply to \(store.approved.count) approved", systemImage: "paperplane.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            if let err = store.lastError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            SwipeDeckView()
        }
    }

    private var listScreen: some View {
        List {
            if !store.approved.isEmpty {
                Section("Approved (\(store.approved.count))") {
                    Button {
                        applying = true
                    } label: {
                        Label("Apply to all \(store.approved.count)", systemImage: "paperplane.fill")
                            .font(.headline)
                    }
                    ForEach(store.approved) { job in
                        JobRow(job: job)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    store.unapprove(job)
                                } label: {
                                    Label("Remove", systemImage: "arrow.uturn.backward")
                                }
                            }
                    }
                }
            }

            if let err = store.lastError {
                Section {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }
            }

            let matches = store.queue
            Section {
                ForEach(matches) { job in
                    NavigationLink {
                        JobDetailView(job: job)
                    } label: {
                        JobRow(job: job)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            store.approve(job)
                        } label: {
                            Label("Approve", systemImage: "checkmark")
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.markUndesired(job)
                        } label: {
                            Label("Not for me", systemImage: "hand.thumbsdown")
                        }
                    }
                }
            } header: {
                Text("Today's matches (\(matches.count))")
            } footer: {
                if store.hiddenCount > 0 {
                    Text("\(store.hiddenCount) more hidden by your criteria.")
                }
            }
        }
        .overlay {
            if store.queue.isEmpty && store.approved.isEmpty {
                EmptyQueueView()
            }
        }
        .refreshable { await store.refresh() }
    }
}

struct JobRow: View {
    @EnvironmentObject var store: Store
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.title).font(.headline)
            Text(job.company + (job.location.isEmpty ? "" : " · " + job.location))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Label("\(store.fit(job))% fit", systemImage: "target")
                if let a = job.applicants {
                    Label("\(a) applicants", systemImage: "person.2")
                }
                Text(job.source)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct JobDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let job: Job
    @State private var applying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(job.title).font(.title2.bold())
                Text(job.company + (job.location.isEmpty ? "" : " · " + job.location))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label("\(store.fit(job))% fit", systemImage: "target")
                    if let a = job.applicants {
                        Label("\(a) applicants", systemImage: "person.2")
                    }
                    if let s = job.salaryMin {
                        Label("from $\(s)", systemImage: "dollarsign.circle")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Button {
                    store.approve(job)
                    dismiss()
                } label: {
                    Label("Approve for batch", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                HStack {
                    Button {
                        applying = true
                    } label: {
                        Label("Apply now", systemImage: "paperplane")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        store.markUndesired(job)
                        dismiss()
                    } label: {
                        Label("Not for me", systemImage: "hand.thumbsdown")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Divider()
                Text(String(job.descriptionText.prefix(4000))).font(.callout)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $applying) {
            ApplyFlowView(jobs: [job])
        }
    }
}

struct AddJobView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var company = ""
    @State private var url = ""
    @State private var location = ""

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && URL(string: url.trimmingCharacters(in: .whitespaces)) != nil && !url.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Job title", text: $title)
                    TextField("Company", text: $company)
                    TextField("Location", text: $location)
                    TextField("Link to the application", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first {
                            url = first
                        }
                    }
                } footer: {
                    Text("Paste a LinkedIn, Indeed or recruiter link. It goes straight to your approved list.")
                }
            }
            .navigationTitle("Add a job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addManual(
                            title: title.trimmingCharacters(in: .whitespaces),
                            company: company.trimmingCharacters(in: .whitespaces),
                            url: url.trimmingCharacters(in: .whitespaces),
                            location: location.trimmingCharacters(in: .whitespaces)
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
