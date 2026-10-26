import SwiftUI
import UIKit

private enum DeckKind {
    case approved, rejected, later
}

private struct DeckMove {
    let job: Job
    let kind: DeckKind
}

private struct DeckItem: Identifiable {
    let depth: Int
    let job: Job
    var id: String { job.id }
}

/// Tinder-style deck: right = approve, left = not for me, up = later. Buttons and undo underneath.
struct SwipeDeckView: View {
    @EnvironmentObject var store: Store
    @State private var deferred: Set<String> = []
    @State private var history: [DeckMove] = []
    @State private var drag: CGSize = .zero
    @State private var busy = false
    @State private var detail: Job?

    private var deck: [Job] {
        store.queue.filter { !deferred.contains($0.id) }
    }

    var body: some View {
        let cards = deck
        let items = Array(cards.prefix(3).enumerated().map { DeckItem(depth: $0.offset, job: $0.element) }.reversed())
        VStack(spacing: 16) {
            ZStack {
                if cards.isEmpty {
                    emptyState
                } else {
                    ForEach(items) { item in
                        card(item.job, depth: item.depth)
                    }
                }
            }
            .padding(.horizontal)
            .frame(maxHeight: .infinity)

            if let top = cards.first {
                controls(top)
            }
        }
        .padding(.vertical)
        .background(Color(.systemGroupedBackground))
        .sheet(item: $detail) { job in
            NavigationStack {
                JobDetailView(job: job)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.queue.isEmpty {
            EmptyQueueView()
        } else {
            ContentUnavailableView {
                Label("Seen them all", systemImage: "checkmark.circle")
            } description: {
                Text("\(deferred.count) job(s) are waiting in Later.")
            } actions: {
                Button("Bring them back") { deferred.removeAll() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func card(_ job: Job, depth: Int) -> some View {
        let isTop = depth == 0
        JobCard(job: job, fit: store.fit(job))
            .overlay {
                if isTop {
                    stamps.allowsHitTesting(false)
                }
            }
            .scaleEffect(isTop ? 1.0 : 1.0 - CGFloat(depth) * 0.05)
            .offset(x: isTop ? drag.width : 0, y: isTop ? drag.height : CGFloat(depth) * 14)
            .rotationEffect(.degrees(isTop ? Double(drag.width) / 18.0 : 0))
            .gesture(dragGesture(for: job), including: isTop ? .all : .none)
            .onTapGesture {
                if isTop && !busy { detail = job }
            }
    }

    private var stamps: some View {
        ZStack {
            stamp("APPLY", .green, opacity: Double(max(0, min(1, drag.width / 110))), angle: -12, alignment: .topLeading)
            stamp("NOPE", .red, opacity: Double(max(0, min(1, -drag.width / 110))), angle: 12, alignment: .topTrailing)
            stamp("LATER", .blue, opacity: Double(max(0, min(1, -drag.height / 140))), angle: 0, alignment: .bottom)
        }
    }

    private func stamp(_ text: String, _ color: Color, opacity: Double, angle: Double, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 34, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(angle))
            .opacity(opacity)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private func dragGesture(for job: Job) -> some Gesture {
        DragGesture()
            .onChanged { v in
                if !busy { drag = v.translation }
            }
            .onEnded { v in
                if busy { return }
                let w = v.translation.width
                let h = v.translation.height
                if w > 110 {
                    commit(.approved, job)
                } else if w < -110 {
                    commit(.rejected, job)
                } else if h < -140 {
                    commit(.later, job)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { drag = .zero }
                }
            }
    }

    private func controls(_ top: Job) -> some View {
        HStack(spacing: 24) {
            roundButton("xmark", .red) { commit(.rejected, top) }
            roundButton("arrow.uturn.backward", .orange, small: true) { undo() }
                .disabled(history.isEmpty)
            roundButton("clock", .blue, small: true) { commit(.later, top) }
            roundButton("checkmark", .green) { commit(.approved, top) }
        }
    }

    private func roundButton(_ icon: String, _ color: Color, small: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: small ? 20 : 28, weight: .bold))
                .foregroundStyle(color)
                .frame(width: small ? 52 : 68, height: small ? 52 : 68)
                .background(Circle().fill(Color(.secondarySystemBackground)))
                .overlay(Circle().stroke(color.opacity(0.5), lineWidth: 2))
        }
    }

    private func commit(_ kind: DeckKind, _ job: Job) {
        if busy { return }
        busy = true
        let target: CGSize
        switch kind {
        case .approved: target = CGSize(width: 800, height: 0)
        case .rejected: target = CGSize(width: -800, height: 0)
        case .later: target = CGSize(width: 0, height: -1000)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.22)) { drag = target }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            switch kind {
            case .approved: store.approve(job)
            case .rejected: store.markUndesired(job)
            case .later: deferred.insert(job.id)
            }
            history.append(DeckMove(job: job, kind: kind))
            drag = .zero
            busy = false
        }
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        switch last.kind {
        case .approved: store.unapprove(last.job)
        case .rejected: store.restore(last.job)
        case .later: deferred.remove(last.job.id)
        }
    }
}

struct JobCard: View {
    let job: Job
    let fit: Int

    private var fitColor: Color {
        fit >= 60 ? Color.green : (fit >= 30 ? Color.orange : Color.gray)
    }

    private var snippet: String {
        job.descriptionText.isEmpty ? "No description loaded." : String(job.descriptionText.prefix(600))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(fit)% fit")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(fitColor.opacity(0.18)))
                    .foregroundStyle(fitColor)
                Spacer()
                Text(job.source).font(.caption).foregroundStyle(.secondary)
            }
            Text(job.title).font(.title2.bold()).lineLimit(3)
            Text(job.company).font(.headline).foregroundStyle(.secondary)
            if !job.location.isEmpty {
                Label(job.location, systemImage: "mappin.and.ellipse").font(.subheadline)
            }
            HStack(spacing: 14) {
                if let a = job.applicants {
                    Label("\(a) applicants", systemImage: "person.2")
                }
                if let s = job.salaryMin {
                    Label("from $\(s)", systemImage: "dollarsign.circle")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Divider()
            Text(snippet).font(.callout).foregroundStyle(.secondary).lineLimit(9)
            Spacer(minLength: 0)
            Text("Tap for details")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 14, y: 6)
    }
}

struct EmptyQueueView: View {
    @EnvironmentObject var store: Store
    @State private var showFind = false

    private var message: String {
        if store.data.boards.isEmpty {
            return "Add company boards under Criteria, or add a job you found from the menu."
        }
        if store.isRefreshing {
            return "Loading jobs..."
        }
        if store.lastFetchTotal > 0 && store.lastFetchKept == 0 {
            return "Checked \(store.lastFetchTotal) postings and none match your criteria. Loosen the filters under Criteria."
        }
        if store.hiddenCount > 0 {
            return "\(store.hiddenCount) job(s) loaded, but your criteria hide them all. Loosen the filters under Criteria."
        }
        if store.data.jobs.isEmpty {
            return "Nothing loaded yet. Tap refresh."
        }
        return "You're caught up. Check back after the next refresh."
    }

    var body: some View {
        ContentUnavailableView {
            Label("No matches", systemImage: "tray")
        } description: {
            Text(message)
        } actions: {
            Button("Refresh") {
                Task { await store.refresh() }
            }
            .buttonStyle(.borderedProminent)
            Button("Find on LinkedIn or Indeed") {
                showFind = true
            }
        }
        .sheet(isPresented: $showFind) { FindOnSitesView() }
    }
}
