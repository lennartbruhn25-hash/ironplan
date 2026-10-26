import EventKit
import SwiftUI

struct CalendarInfo: Identifiable {
    let id: String
    let title: String
    let source: String
    let color: Color
}

/// Liest alle Kalender, die auf dem iPhone eingerichtet sind –
/// z. B. ein abonnierter Untis-Stundenplan oder Google-Kalender mit Fahrstunden.
final class CalendarService {
    private let store = EKEventStore()

    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    func calendars() -> [CalendarInfo] {
        guard hasAccess else { return [] }
        return store.calendars(for: .event)
            .map { c in
                CalendarInfo(id: c.calendarIdentifier,
                             title: c.title,
                             source: c.source.title,
                             color: Color(cgColor: c.cgColor))
            }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    func events(on date: Date, settings: UserSettings, cal: Calendar) -> [BusyEvent] {
        guard hasAccess else { return [] }
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }

        let all = store.calendars(for: .event)
        let chosen = settings.includedCalendarIDs.isEmpty
            ? all
            : all.filter { settings.includedCalendarIDs.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: chosen)
        return store.events(matching: predicate).map { e in
            BusyEvent(title: e.title ?? "Termin",
                      start: e.startDate,
                      end: e.endDate,
                      isSchool: settings.schoolCalendarIDs.contains(e.calendar.calendarIdentifier),
                      isAllDay: e.isAllDay)
        }
    }
}
