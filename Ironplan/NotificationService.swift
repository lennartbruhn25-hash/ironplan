import Foundation
import UserNotifications

/// Plant lokale Benachrichtigungen für die nächsten Tage.
/// iOS erlaubt max. 64 geplante Benachrichtigungen – deshalb nur ein paar Tage im Voraus.
/// Jedes Öffnen der App plant neu.
enum NotificationService {
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func isAuthorized() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    private struct Item {
        let date: Date
        let title: String
        let body: String
    }

    static func reschedule(plans: [DayPlan], settings: UserSettings, cal: Calendar, tips: [Date: String]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let now = Date()
        var items: [Item] = []

        for plan in plans {
            for block in plan.blocks {
                switch block.kind {
                case .training where settings.notifyTraining:
                    items.append(Item(date: block.start.addingTimeInterval(-15 * 60),
                                      title: "In 15 min: Training 💪",
                                      body: "\(block.title) – \(Fmt.duration(block.minutes)) ab \(Fmt.time(block.start))."))
                case .study where settings.notifyStudy:
                    items.append(Item(date: block.start,
                                      title: "Lernzeit 📚",
                                      body: "\(Fmt.duration(block.minutes)) konzentriert. Handy weg, eine Sache nach der anderen."))
                case .meal where settings.notifyMeals && block.title == "Abendessen":
                    let tip = tips[cal.startOfDay(for: plan.date)] ?? "Gemüse, Eiweiß und Kohlenhydrate auf den Teller."
                    items.append(Item(date: block.start, title: "Abendessen 🍝", body: tip))
                case .windDown where settings.notifyBedtime:
                    items.append(Item(date: block.start,
                                      title: "Zeit runterzufahren 🌙",
                                      body: "In 30 min ist Schlafenszeit. Handy weg – Schlaf macht dich schneller."))
                case .anime:
                    items.append(Item(date: block.start,
                                      title: "Freizeit 🍿",
                                      body: "Jetzt ist Anime-Zeit. Ohne schlechtes Gewissen."))
                default:
                    break
                }
            }

            if settings.notifyWater {
                var t = plan.wake.addingTimeInterval(2 * 3600)
                let last = plan.bed.addingTimeInterval(-90 * 60)
                while t <= last {
                    items.append(Item(date: t, title: "Trinken 💧", body: "Ein großes Glas Wasser. Dein Körper trainiert auch heute."))
                    t = t.addingTimeInterval(2 * 3600)
                }
            }
        }

        let upcoming = items.filter { $0.date > now }.sorted { $0.date < $1.date }.prefix(60)
        for (i, item) in upcoming.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: "ironplan-\(i)-\(Int(item.date.timeIntervalSince1970))",
                                                content: content, trigger: trigger)
            center.add(request)
        }
    }
}
