import SwiftUI

func mailURL(to: String, subject: String, body: String) -> URL? {
    let address = to.trimmingCharacters(in: .whitespaces)
    if address.isEmpty { return nil }
    var c = URLComponents()
    c.scheme = "mailto"
    c.path = address
    c.queryItems = [
        URLQueryItem(name: "subject", value: subject),
        URLQueryItem(name: "body", value: body)
    ]
    return c.url
}

/// An editable list of short strings, used for keywords, locations and blocklists.
struct StringListEditor: View {
    let title: String
    let placeholder: String
    @Binding var items: [String]
    @State private var newItem = ""

    var body: some View {
        Section(title) {
            ForEach(items, id: \.self) { item in
                Text(item)
            }
            .onDelete { offsets in
                items.remove(atOffsets: offsets)
            }
            HStack {
                TextField(placeholder, text: $newItem)
                    .textInputAutocapitalization(.never)
                    .onSubmit { add() }
                Button("Add") { add() }
                    .buttonStyle(.borderless)
                    .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func add() {
        let t = newItem.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !items.contains(t) else { return }
        items.append(t)
        newItem = ""
    }
}
