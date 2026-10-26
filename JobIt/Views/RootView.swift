import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            QueueView()
                .tabItem { Label("Queue", systemImage: "tray.full") }
                .badge(store.approved.count)
            FollowUpsView()
                .tabItem { Label("Follow-ups", systemImage: "envelope") }
                .badge(store.dueFollowUps.count)
            RecruitersView()
                .tabItem { Label("Recruiters", systemImage: "person.2") }
                .badge(store.dueRecruiters.count)
            AnswersView()
                .tabItem { Label("Answers", systemImage: "text.book.closed") }
                .badge(store.needsAnswer.count)
            CriteriaView()
                .tabItem { Label("Criteria", systemImage: "slider.horizontal.3") }
        }
        .task {
            Reminders.requestPermission()
            Reminders.refresh(store: store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                store.saveNow()
                Reminders.refresh(store: store)
            }
        }
    }
}
