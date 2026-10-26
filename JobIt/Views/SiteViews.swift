import SwiftUI

struct BrowserTarget: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
}

struct CapturedJob: Identifiable {
    let id = UUID()
    var title: String
    var company: String
    var location: String
    var url: String
}

/// Pick keywords and a place, then search LinkedIn or Indeed inside the app.
struct FindOnSitesView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("findKeywords") private var keywords = ""
    @AppStorage("findLocation") private var location = "Rhode Island"
    @AppStorage("findEasyApply") private var easyApply = true
    @State private var target: BrowserTarget?

    var body: some View {
        NavigationStack {
            Form {
                Section("Search for") {
                    TextField("Keywords", text: $keywords, axis: .vertical)
                        .textInputAutocapitalization(.never)
                    TextField("Location", text: $location)
                }

                Section {
                    Toggle("LinkedIn: Easy Apply only", isOn: $easyApply)
                } footer: {
                    Text("Easy Apply jobs are applied to inside LinkedIn, so you are never sent to another site.")
                }

                Section {
                    Button {
                        if let url = JobSites.linkedInSearch(keywords: keywords, location: location, easyApplyOnly: easyApply) {
                            target = BrowserTarget(url: url, name: "LinkedIn")
                        }
                    } label: {
                        Label("Search LinkedIn", systemImage: "magnifyingglass")
                    }
                    Button {
                        if let url = JobSites.indeedSearch(keywords: keywords, location: location) {
                            target = BrowserTarget(url: url, name: "Indeed")
                        }
                    } label: {
                        Label("Search Indeed", systemImage: "magnifyingglass")
                    }
                } footer: {
                    Text("Sign in once and the app remembers it. Open a job, then tap \"Save this job\". Saved jobs go straight to your approved list.")
                }
            }
            .navigationTitle("Find jobs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if keywords.isEmpty {
                    let terms = store.data.criteria.includeKeywords.prefix(4).map { "\"" + $0 + "\"" }
                    keywords = terms.joined(separator: " OR ")
                }
            }
            .fullScreenCover(item: $target) { t in
                SiteBrowserView(url: t.url, siteName: t.name)
            }
        }
    }
}

struct SiteBrowserView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let siteName: String

    @StateObject private var web = WebController()
    @State private var captured: CapturedJob?
    @State private var saved = 0
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(siteName).font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            WebContainer(url: url, controller: web)

            VStack(spacing: 6) {
                Text(message.isEmpty ? "Open a job, then tap save. \(saved) saved so far." : message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await capture() }
                } label: {
                    Label("Save this job", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
            }
            .padding()
        }
        .sheet(item: $captured) { job in
            CaptureConfirmView(job: job) {
                saved += 1
                message = "Saved. \(saved) in your approved list from this search."
            }
        }
    }

    private func capture() async {
        busy = true
        if let raw = await web.capture() {
            captured = CapturedJob(title: raw.title, company: raw.company, location: raw.location, url: raw.url)
        } else {
            message = "Could not read this page. Open a job posting and try again."
        }
        busy = false
    }
}

/// Shows what was read from the page so you can fix it before it is saved.
struct CaptureConfirmView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var job: CapturedJob
    let onSaved: () -> Void

    private var canSave: Bool {
        !job.title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Job title", text: $job.title, axis: .vertical)
                    TextField("Company", text: $job.company)
                    TextField("Location", text: $job.location)
                } footer: {
                    Text("Check these look right. The page layout can change, so edit anything that is off.")
                }
            }
            .navigationTitle("Save job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.addManual(
                            title: job.title.trimmingCharacters(in: .whitespaces),
                            company: job.company.trimmingCharacters(in: .whitespaces),
                            url: job.url,
                            location: job.location.trimmingCharacters(in: .whitespaces)
                        )
                        onSaved()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
