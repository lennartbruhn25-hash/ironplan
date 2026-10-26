import SwiftUI
import EventKit

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: UserSettings {
        didSet {
            guard settings != oldValue else { return }
            Storage.save(settings, key: Storage.settingsKey)
            rebuildPlan()
            scheduleNotificationRefresh()
        }
    }
    @Published private(set) var weeks: [TrainingWeek] = []
    @Published private(set) var completed: Set<String>
    @Published private(set) var water: [String: Int]
    @Published private(set) var activities: [ActivityRecord]
    @Published private(set) var calendarAuthorized = false
    @Published private(set) var calendars: [CalendarInfo] = []
    @Published private(set) var calendarVersion = 0
    @Published private(set) var lastNightSleep: Int? = nil
    @Published private(set) var syncMessage: String? = nil
    @Published private(set) var isSyncing = false

    let cal = Calendar.app
    let strava = StravaService()
    private let calendarService = CalendarService()
    private let health = HealthService()
    private var sessionsByDay: [String: [TrainingSession]] = [:]
    private var notificationTask: Task<Void, Never>?
    private var calendarObserver: NSObjectProtocol?

    init() {
        let stored = Storage.load(UserSettings.self, key: Storage.settingsKey)
        let initial = stored ?? UserSettings.defaults()
        settings = initial
        completed = Storage.load(Set<String>.self, key: Storage.completedKey) ?? []
        water = Storage.load([String: Int].self, key: Storage.waterKey) ?? [:]
        activities = Storage.load([ActivityRecord].self, key: Storage.activitiesKey) ?? []
        if stored == nil { Storage.save(initial, key: Storage.settingsKey) }

        rebuildPlan()
        calendarAuthorized = calendarService.hasAccess
        calendars = calendarService.calendars()

        calendarObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.calendarDidChange() }
        }
    }

    // MARK: Lebenszyklus

    func bootstrap() async {
        if !(await NotificationService.isAuthorized()) {
            _ = await NotificationService.requestAuthorization()
        }
        await appBecameActive()
    }

    func appBecameActive() async {
        calendarAuthorized = calendarService.hasAccess
        calendars = calendarService.calendars()
        calendarVersion += 1
        scheduleNotificationRefresh()
        await syncActivities()
    }

    private func calendarDidChange() {
        calendars = calendarService.calendars()
        calendarVersion += 1
        scheduleNotificationRefresh()
    }

    // MARK: Plan

    private func rebuildPlan() {
        weeks = PlanGenerator(settings: settings, cal: cal).generate()
        sessionsByDay = Dictionary(grouping: weeks.flatMap { $0.sessions }, by: { Fmt.dayKey($0.day) })
    }

    func sessions(on date: Date) -> [TrainingSession] {
        sessionsByDay[Fmt.dayKey(date)] ?? []
    }

    func week(containing date: Date) -> TrainingWeek? {
        let start = cal.startOfWeek(date)
        return weeks.first { $0.start == start }
    }

    var currentWeek: TrainingWeek? { week(containing: Date()) }

    var daysUntilRace: Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                           to: cal.startOfDay(for: settings.raceDate)).day ?? 0
    }

    var needsBikeSoon: Bool {
        !settings.hasBike && (currentWeek?.phase.isBuildOrLater ?? false)
    }

    func toggleExamWeek(_ weekStart: Date) {
        let key = Fmt.dayKey(weekStart)
        if let i = settings.examWeeks.firstIndex(of: key) {
            settings.examWeeks.remove(at: i)
        } else {
            settings.examWeeks.append(key)
        }
    }

    // MARK: Tagesplan

    func dayPlan(for date: Date) -> DayPlan {
        _ = calendarVersion
        let events = calendarService.events(on: date, settings: settings, cal: cal)
        return DayPlanner(settings: settings, cal: cal).plan(date: date, events: events, sessions: sessions(on: date))
    }

    // MARK: Erledigt

    /// Passende Aktivität aus Apple Health / Strava zu einer geplanten Einheit.
    func matchedActivity(for session: TrainingSession) -> ActivityRecord? {
        guard session.isTraining else { return nil }
        let sameDay = activities.filter { cal.isDate($0.start, inSameDayAs: session.day) }
        let fits: (ActivityRecord) -> Bool = { a in
            switch session.sport {
            case .brick: return a.sport == .bike || a.sport == .run || a.sport == .brick
            default: return a.sport == session.sport
            }
        }
        return sameDay.filter(fits).max { $0.minutes < $1.minutes }
    }

    func isDone(_ session: TrainingSession) -> Bool {
        completed.contains(session.id) || matchedActivity(for: session) != nil
    }

    func toggleDone(_ session: TrainingSession) {
        if completed.contains(session.id) {
            completed.remove(session.id)
        } else {
            completed.insert(session.id)
        }
        Storage.save(completed, key: Storage.completedKey)
    }

    // MARK: Wasser

    func waterML(on date: Date) -> Int { water[Fmt.dayKey(date)] ?? 0 }

    func waterGoal(on date: Date) -> Int {
        let trainingMinutes = sessions(on: date).filter { $0.isTraining }.reduce(0) { $0 + $1.minutes }
        let extra = Int((Double(trainingMinutes) / 60 * 500 / 250).rounded()) * 250
        return settings.waterGoalML + extra
    }

    func addWater(_ ml: Int, on date: Date) {
        let key = Fmt.dayKey(date)
        water[key] = max(0, (water[key] ?? 0) + ml)
        Storage.save(water, key: Storage.waterKey)
        if ml > 0 && settings.healthEnabled && cal.isDateInToday(date) {
            health.logWater(ml: ml)
        }
    }

    // MARK: Ernährung

    func nutritionTip(for date: Date) -> String {
        let training = sessions(on: date).filter { $0.isTraining }
        let total = training.reduce(0) { $0 + $1.minutes }
        if sessions(on: date).contains(where: { $0.sport == .race }) {
            return "Wettkampftag: Frühstück 3 h vor dem Start, das du kennst. Unterwegs nach Plan essen und trinken."
        }
        if total == 0 {
            return "Ruhetag: normal essen, viel Gemüse und Obst, genug Eiweiß (z. B. Quark, Eier, Hülsenfrüchte) für die Erholung."
        }
        if total >= 120 || training.contains(where: { $0.isKey }) {
            return "Langer Trainingstag: vorher kohlenhydratreich (Haferflocken, Nudeln, Reis), unterwegs trinken, danach innerhalb einer Stunde Eiweiß + Kohlenhydrate."
        }
        return "Trainingstag: 1–2 h vorher ein kleiner Snack (Banane, Brot), danach eine richtige Mahlzeit mit Eiweiß und Kohlenhydraten."
    }

    // MARK: Kalender

    func requestCalendarAccess() async {
        _ = await calendarService.requestAccess()
        calendarAuthorized = calendarService.hasAccess
        calendars = calendarService.calendars()
        calendarVersion += 1
        scheduleNotificationRefresh()
    }

    func isCalendarIncluded(_ id: String) -> Bool {
        settings.includedCalendarIDs.isEmpty || settings.includedCalendarIDs.contains(id)
    }

    func setCalendar(_ id: String, included: Bool) {
        var ids = settings.includedCalendarIDs.isEmpty ? calendars.map { $0.id } : settings.includedCalendarIDs
        if included {
            if !ids.contains(id) { ids.append(id) }
        } else {
            ids.removeAll { $0 == id }
        }
        settings.includedCalendarIDs = ids.count == calendars.count ? [] : ids
    }

    func isSchoolCalendar(_ id: String) -> Bool {
        settings.schoolCalendarIDs.contains(id)
    }

    func setSchoolCalendar(_ id: String, _ isSchool: Bool) {
        settings.schoolCalendarIDs.removeAll { $0 == id }
        if isSchool { settings.schoolCalendarIDs.append(id) }
    }

    // MARK: Aktivitäten-Hub

    func connectHealth() async {
        let error = await health.requestAuthorization()
        if let error {
            syncMessage = error
        } else {
            settings.healthEnabled = true
            await syncActivities()
        }
    }

    func disconnectHealth() {
        settings.healthEnabled = false
        activities.removeAll { $0.source == .health }
        Storage.save(activities, key: Storage.activitiesKey)
    }

    func connectStrava() async {
        do {
            try await strava.connect(clientID: settings.stravaClientID, clientSecret: settings.stravaClientSecret)
            objectWillChange.send()
            await syncActivities()
        } catch {
            syncMessage = error.localizedDescription
        }
    }

    func disconnectStrava() {
        strava.disconnect()
        activities.removeAll { $0.source == .strava }
        Storage.save(activities, key: Storage.activitiesKey)
        objectWillChange.send()
    }

    func syncActivities() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let since = cal.date(byAdding: .day, value: -60, to: cal.startOfDay(for: Date())) ?? Date()
        var fromHealth: [ActivityRecord] = activities.filter { $0.source == .health }
        var fromStrava: [ActivityRecord] = activities.filter { $0.source == .strava }
        var messages: [String] = []

        if settings.healthEnabled {
            fromHealth = await health.workouts(since: since)
            lastNightSleep = await health.sleepMinutes(endingOn: Date(), cal: cal)
        }
        if strava.isConnected {
            do {
                fromStrava = try await strava.activities(since: since, clientID: settings.stravaClientID,
                                                         clientSecret: settings.stravaClientSecret)
            } catch {
                messages.append(error.localizedDescription)
            }
        }

        activities = Self.merge(health: fromHealth, strava: fromStrava)
        Storage.save(activities, key: Storage.activitiesKey)
        syncMessage = messages.isEmpty ? nil : messages.joined(separator: "\n")
        objectWillChange.send()
    }

    /// Doppelte Workouts (z. B. Suunto → Health UND Suunto → Strava) zusammenführen:
    /// gleiche Sportart und Start innerhalb von 10 Minuten = dasselbe Workout.
    private static func merge(health: [ActivityRecord], strava: [ActivityRecord]) -> [ActivityRecord] {
        var result = health
        for s in strava {
            let duplicate = health.contains { h in
                h.sport == s.sport && abs(h.start.timeIntervalSince(s.start)) < 600
            }
            if !duplicate { result.append(s) }
        }
        return result.sorted { $0.start > $1.start }
    }

    func doneActivities(on date: Date) -> [ActivityRecord] {
        activities.filter { cal.isDate($0.start, inSameDayAs: date) }
    }

    /// Geplante vs. erledigte Minuten pro Sportart in einer Woche.
    func weekSummary(_ week: TrainingWeek) -> [(sport: Sport, planned: Int, done: Int)] {
        guard let end = cal.date(byAdding: .day, value: 7, to: week.start) else { return [] }
        let done = activities.filter { $0.start >= week.start && $0.start < end }
        return Sport.tracked.map { sport -> (sport: Sport, planned: Int, done: Int) in
            let planned = week.sessions.reduce(0) { sum, s in
                if s.sport == sport { return sum + s.minutes }
                if s.sport == .brick && (sport == .bike || sport == .run) {
                    let run = min(30, max(15, (s.minutes / 10) / 5 * 5))
                    return sum + (sport == .run ? run : s.minutes - run)
                }
                return sum
            }
            let actual = done.filter { $0.sport == sport }.reduce(0) { $0 + $1.minutes }
            return (sport: sport, planned: planned, done: actual)
        }
    }

    // MARK: Benachrichtigungen

    func scheduleNotificationRefresh() {
        notificationTask?.cancel()
        notificationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self else { return }
            self.rescheduleNotificationsNow()
        }
    }

    private func rescheduleNotificationsNow() {
        let today = cal.startOfDay(for: Date())
        var plans: [DayPlan] = []
        var tips: [Date: String] = [:]
        for offset in 0..<4 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            plans.append(dayPlan(for: day))
            tips[day] = nutritionTip(for: day)
        }
        NotificationService.reschedule(plans: plans, settings: settings, cal: cal, tips: tips)
    }
}
