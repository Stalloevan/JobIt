import SwiftUI

struct IndeedImportView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("findKeywords") private var keywords = ""
    @AppStorage("findLocation") private var location = "Rhode Island"
    @AppStorage("indeedPages") private var pages = 4
    @State private var importer: IndeedImporter?
    @State private var browser: BrowserTarget?

    var body: some View {
        NavigationStack {
            if let current = importer {
                IndeedRunView(importer: current) { dismiss() }
            } else {
                setupForm
            }
        }
    }

    private var setupForm: some View {
        Form {
            Section("Search for") {
                TextField("Keywords", text: $keywords, axis: .vertical)
                    .textInputAutocapitalization(.never)
                TextField("Location", text: $location)
                Stepper("Pages to read: \(pages)", value: $pages, in: 1...8)
            }

            Section {
                Button {
                    importer = IndeedImporter(
                        store: store,
                        keywords: keywords,
                        location: location,
                        maxPages: pages
                    )
                } label: {
                    Label("Start import", systemImage: "arrow.down.circle.fill")
                }
                .disabled(keywords.trimmingCharacters(in: .whitespaces).isEmpty)

                Button {
                    if let url = JobSites.indeedSearch(keywords: keywords, location: location) {
                        browser = BrowserTarget(url: url, name: "Indeed")
                    }
                } label: {
                    Label("Browse Indeed and save jobs myself", systemImage: "safari")
                }
            } footer: {
                Text("Import reads about 15 jobs per page from the last 7 days and adds the ones that match your criteria to your queue. Pages load slowly on purpose. If Indeed asks you to verify you're human, do it in the window, then tap Continue.")
            }
        }
        .navigationTitle("Import from Indeed")
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
        .fullScreenCover(item: $browser) { t in
            SiteBrowserView(url: t.url, siteName: t.name)
        }
    }
}

struct IndeedRunView: View {
    @ObservedObject var importer: IndeedImporter
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                if !importer.finished {
                    ProgressView()
                }
                Text(importer.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack {
                    if importer.needsHuman {
                        Button("Continue") { importer.retry() }
                            .buttonStyle(.borderedProminent)
                    }
                    if importer.finished {
                        Button("Done") { onClose() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Stop and keep what's found") { importer.stop() }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding()

            if !importer.finished, let url = importer.firstURL {
                WebContainer(url: url, controller: importer.web, onLoaded: { importer.pageLoaded() })
            } else {
                Spacer()
            }
        }
        .navigationTitle("Indeed")
        .navigationBarTitleDisplayMode(.inline)
    }
}
