import Foundation
import UserNotifications

enum Reminders {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    /// One repeating daily notification. The text is refreshed whenever the app goes to the
    /// background, so it reflects what is waiting for you.
    @MainActor
    static func refresh(store: Store) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["jobit.daily"])

        let content = UNMutableNotificationContent()
        content.title = "JobIt: one small step"
        content.body = store.dailyNudge
        content.sound = .default

        var comps = DateComponents()
        comps.hour = store.data.reminderHour
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: "jobit.daily", content: content, trigger: trigger))
    }
}
