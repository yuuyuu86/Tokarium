import Foundation
import UserNotifications

/// 通知
extension GameStore {
    // MARK: 通知

    func requestNotificationPermission() {
        guard settings.notificationsEnabled, Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyChanges(before: [Fish]) {
        for f in state.tank.fish {
            let old = before.first { $0.id == f.id }
            if f.condition.isDanger && !state.notifiedDangerFish.contains(f.id) {
                state.notifiedDangerFish.insert(f.id)
                post(title: String(localized: "\(f.name)が危険な状態です"), body: String(localized: "餌やりと水換えをしてあげてください。"))
            } else if f.condition != .critical && f.isAlive {
                state.notifiedDangerFish.remove(f.id)
            }
            if old?.isAlive == true && !f.isAlive {
                post(title: (f.deathCause ?? .neglect).message(name: f.name), body: String(localized: "お世話画面でお別れできます。"))
            }
        }
    }

    func post(title: String, body: String) {
        guard settings.notificationsEnabled, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

// MARK: - お世話のリマインド

extension GameStore {
    /// 決まった時刻に「そろそろ餌の時間です」を知らせる（毎日くり返す）。
    func scheduleReminders() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let ids = (0..<10).map { "tokarium-reminder-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard settings.remindersEnabled, settings.notificationsEnabled else { return }
        requestNotificationPermission()
        for (i, minutes) in settings.reminderTimes.prefix(ids.count).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "そろそろ餌の時間です")
            content.body = String(localized: "水槽の魚たちが待っています。")
            var when = DateComponents()
            when.hour = minutes / 60
            when.minute = minutes % 60
            center.add(UNNotificationRequest(identifier: ids[i], content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
        }
    }
}
