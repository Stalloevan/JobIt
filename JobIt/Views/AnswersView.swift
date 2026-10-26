import SwiftUI

struct AnswersView: View {
    @EnvironmentObject var store: Store
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                let needs = store.needsAnswer
                let saved = store.data.answers.filter {
                    !$0.perApplication && !$0.answer.trimmingCharacters(in: .whitespaces).isEmpty
                }
                let each = store.data.answers.filter { $0.perApplication }

                if !needs.isEmpty {
                    Section("Needs your answer (\(needs.count))") {
                        ForEach(needs) { e in row(e) }
                    }
                }
                if !saved.isEmpty {
                    Section("Filled in automatically") {
                        ForEach(saved) { e in row(e) }
                    }
                }
                if !each.isEmpty {
                    Section("Asked every time") {
                        ForEach(each) { e in row(e) }
                    }
                }
            }
            .navigationTitle("Answers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddAnswerView() }
        }
    }

    private func row(_ e: AnswerEntry) -> some View {
        NavigationLink {
            AnswerEditorView(id: e.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.question)
                if !e.answer.isEmpty {
                    Text(e.answer).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                store.data.answers.removeAll { $0.id == e.id }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct AnswerEditorView: View {
    @EnvironmentObject var store: Store
    let id: UUID

    private var idx: Int? {
        store.data.answers.firstIndex { $0.id == id }
    }

    var body: some View {
        if let i = idx {
            Form {
                Section("Question as it appears on forms") {
                    TextField("Question", text: $store.data.answers[i].question)
                }
                Section("Your answer") {
                    TextEditor(text: $store.data.answers[i].answer)
                        .frame(minHeight: 120)
                }
                Section {
                    Toggle("Ask me every time", isOn: $store.data.answers[i].perApplication)
                } footer: {
                    Text("Turn this on for questions that need a different answer for each application. Autofill will highlight them instead of filling them.")
                }
            }
            .navigationTitle("Answer")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            Text("This answer was removed.")
        }
    }
}

struct AddAnswerView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var answer = ""
    @State private var individual = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextField("e.g. Do you have a driver's license", text: $question)
                }
                Section("Answer") {
                    TextEditor(text: $answer).frame(minHeight: 100)
                }
                Section {
                    Toggle("Ask me every time", isOn: $individual)
                }
            }
            .navigationTitle("New answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.data.answers.append(
                            AnswerEntry(
                                question: question.trimmingCharacters(in: .whitespaces),
                                answer: answer,
                                perApplication: individual
                            )
                        )
                        dismiss()
                    }
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
