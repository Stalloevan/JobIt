import SwiftUI

struct CriteriaView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            Form {
                Section("Sorting") {
                    Picker("Sort the queue by", selection: $store.data.criteria.sortMode) {
                        ForEach(SortMode.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                }

                StringListEditor(
                    title: "Job must mention one of (title or description)",
                    placeholder: "e.g. process improvement",
                    items: $store.data.criteria.includeKeywords
                )
                StringListEditor(
                    title: "Skip if the title contains",
                    placeholder: "e.g. senior",
                    items: $store.data.criteria.excludeKeywords
                )

                Section("Location") {
                    Toggle("Remote only", isOn: $store.data.criteria.remoteOnly)
                }
                StringListEditor(
                    title: "Places I'd work (remote always allowed)",
                    placeholder: "e.g. providence",
                    items: $store.data.criteria.locations
                )

                Section {
                    Stepper(value: $store.data.criteria.minSalary, in: 0...300000, step: 5000) {
                        Text(store.data.criteria.minSalary == 0
                             ? "Minimum salary: none"
                             : "Minimum salary: $\(store.data.criteria.minSalary)")
                    }
                } header: {
                    Text("Pay")
                } footer: {
                    Text("Read from the posting when it lists pay. Jobs with no pay listed are kept.")
                }

                Section {
                    Stepper(value: $store.data.criteria.minSatisfaction, in: 0...5, step: 0.5) {
                        Text(store.data.criteria.minSatisfaction == 0
                             ? "Minimum employee rating: off"
                             : "Minimum employee rating: \(String(format: "%.1f", store.data.criteria.minSatisfaction))")
                    }
                    Toggle("Keep companies I haven't rated", isOn: $store.data.criteria.allowUnrated)
                    NavigationLink("Rate companies") { RatingsView() }
                } header: {
                    Text("Employee satisfaction")
                } footer: {
                    Text("There is no free official ratings feed, so you enter ratings yourself from a site like Glassdoor.")
                }

                StringListEditor(
                    title: "Never show these companies (military contractors etc.)",
                    placeholder: "company name",
                    items: $store.data.criteria.blockedCompanies
                )
                StringListEditor(
                    title: "Never show jobs mentioning",
                    placeholder: "e.g. security clearance",
                    items: $store.data.criteria.blockedTerms
                )
                StringListEditor(
                    title: "My skills (used to rank fit)",
                    placeholder: "e.g. python",
                    items: $store.data.fitSkills
                )

                Section("Where jobs come from") {
                    NavigationLink("Company job boards (\(store.data.boards.count))") { BoardsView() }
                    NavigationLink("Jobs marked not for me (\(store.undesired.count))") { UndesiredView() }
                }

                Section {
                    Stepper(value: $store.data.reminderHour, in: 5...22) {
                        Text("Daily nudge at \(store.data.reminderHour):00")
                    }
                } header: {
                    Text("Reminder")
                }
            }
            .navigationTitle("Criteria")
            .onDisappear {
                if store.criteriaChangedSinceRefresh {
                    Task { await store.refresh() }
                }
            }
        }
    }
}

struct RatingsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let companies = Array(Set(store.data.jobs.map { $0.company })).sorted()
        List(companies, id: \.self) { company in
            Stepper(value: ratingBinding(company), in: 0...5, step: 0.5) {
                HStack {
                    Text(company)
                    Spacer()
                    Text(ratingText(company)).foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if companies.isEmpty {
                ContentUnavailableView(
                    "No companies yet",
                    systemImage: "building.2",
                    description: Text("Companies appear here after jobs are loaded.")
                )
            }
        }
        .navigationTitle("Company ratings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ratingBinding(_ company: String) -> Binding<Double> {
        let key = Matching.ratingKey(company)
        return Binding(
            get: { store.data.companyRatings[key] ?? 0 },
            set: { v in
                if v <= 0 {
                    store.data.companyRatings.removeValue(forKey: key)
                } else {
                    store.data.companyRatings[key] = v
                }
            }
        )
    }

    private func ratingText(_ company: String) -> String {
        if let r = store.data.companyRatings[Matching.ratingKey(company)] {
            return String(format: "%.1f", r)
        }
        return "unrated"
    }
}

struct BoardsView: View {
    @EnvironmentObject var store: Store
    @State private var kind: BoardKind = .greenhouse
    @State private var name = ""
    @State private var token = ""

    var body: some View {
        Form {
            Section("Watching") {
                ForEach(store.data.boards) { b in
                    VStack(alignment: .leading) {
                        Text(b.displayName)
                        Text("\(b.kind.label) · \(b.token)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    store.data.boards.remove(atOffsets: offsets)
                }
            }

            Section {
                Picker("Type", selection: $kind) {
                    ForEach(BoardKind.allCases) { k in
                        Text(k.label).tag(k)
                    }
                }
                TextField("Company name", text: $name)
                TextField("Board token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add board") {
                    store.data.boards.append(
                        Board(
                            kind: kind,
                            token: token.trimmingCharacters(in: .whitespaces),
                            displayName: name.trimmingCharacters(in: .whitespaces)
                        )
                    )
                    name = ""
                    token = ""
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || token.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Add a company")
            } footer: {
                Text("The token is the last part of the company's careers link: boards.greenhouse.io/TOKEN or jobs.lever.co/TOKEN. LinkedIn and Indeed have no public feed, so add those jobs by link from the Queue menu.")
            }
        }
        .navigationTitle("Job boards")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct UndesiredView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        List {
            ForEach(store.undesired) { job in
                JobRow(job: job)
                    .swipeActions {
                        Button {
                            store.restore(job)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                    }
            }
        }
        .overlay {
            if store.undesired.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: "hand.thumbsdown")
            }
        }
        .navigationTitle("Not for me")
        .navigationBarTitleDisplayMode(.inline)
    }
}
