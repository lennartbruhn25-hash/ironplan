import SwiftUI

// MARK: - Sportarten

enum Sport: String, Codable, CaseIterable, Identifiable {
    case swim, bike, run, brick, strength, rest, race, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .swim: return "Schwimmen"
        case .bike: return "Rad"
        case .run: return "Laufen"
        case .brick: return "Koppeltraining"
        case .strength: return "Kraft"
        case .rest: return "Ruhetag"
        case .race: return "Wettkampf"
        case .other: return "Sonstiges"
        }
    }

    var symbol: String {
        switch self {
        case .swim: return "figure.pool.swim"
        case .bike: return "figure.outdoor.cycle"
        case .run: return "figure.run"
        case .brick: return "arrow.triangle.2.circlepath"
        case .strength: return "dumbbell.fill"
        case .rest: return "bed.double.fill"
        case .race: return "flag.checkered"
        case .other: return "figure.mixed.cardio"
        }
    }

    var color: Color {
        switch self {
        case .swim: return .cyan
        case .bike: return .orange
        case .run: return .green
        case .brick: return .purple
        case .strength: return .pink
        case .rest: return .gray
        case .race: return .yellow
        case .other: return .indigo
        }
    }

    /// Die drei Triathlon-Sportarten plus Kraft – für Wochenauswertungen.
    static let tracked: [Sport] = [.swim, .bike, .run, .strength]
}

// MARK: - Trainingsphasen

enum Phase: String, Codable {
    case base1, base2, build1, build2, peak, taper, raceWeek

    var label: String {
        switch self {
        case .base1: return "Grundlage 1"
        case .base2: return "Grundlage 2"
        case .build1: return "Aufbau 1"
        case .build2: return "Aufbau 2"
        case .peak: return "Spitze"
        case .taper: return "Tapering"
        case .raceWeek: return "Wettkampfwoche"
        }
    }

    var summary: String {
        switch self {
        case .base1: return "Fundament legen: Kraul-Technik lernen, locker laufen, Körper an regelmäßiges Training gewöhnen. Fast alles ruhig."
        case .base2: return "Umfang langsam steigern, Kraul am Stück, Rad-Grundlage aufbauen."
        case .build1: return "Erste Tempoeinheiten, längere Rad- und Laufeinheiten."
        case .build2: return "Ironman-spezifisch: lange Ausfahrten, Koppeltraining, Verpflegung üben."
        case .peak: return "Höchster Umfang und Wettkampf-Simulationen. Schlaf ist jetzt Pflicht."
        case .taper: return "Umfang runter, Frische rauf. Nichts Neues mehr ausprobieren."
        case .raceWeek: return "Kurz, locker, ausruhen. Du bist bereit."
        }
    }

    var isBuildOrLater: Bool {
        switch self {
        case .base1, .base2: return false
        default: return true
        }
    }
}

// MARK: - Plan

struct TrainingSession: Identifiable, Codable, Hashable {
    let id: String
    let day: Date
    let sport: Sport
    let title: String
    let minutes: Int
    let details: String
    let isKey: Bool

    var isTraining: Bool { minutes > 0 && sport != .rest && sport != .race }
}

struct TrainingWeek: Identifiable, Hashable {
    let index: Int
    let start: Date
    let phase: Phase
    let isRecovery: Bool
    let isExam: Bool
    let sessions: [TrainingSession]

    var id: Int { index }
    var totalMinutes: Int { sessions.reduce(0) { $0 + $1.minutes } }
}

// MARK: - Erledigte Aktivitäten (Apple Health, Strava, …)

enum ActivitySource: String, Codable {
    case health, strava

    var label: String {
        switch self {
        case .health: return "Apple Health"
        case .strava: return "Strava"
        }
    }
}

struct ActivityRecord: Identifiable, Codable, Hashable {
    let id: String
    let source: ActivitySource
    /// Ursprüngliche App, z. B. „Suunto“ oder „Strava“.
    let appName: String
    let sport: Sport
    let name: String
    let start: Date
    let minutes: Int
    let distanceKm: Double?
    let avgHeartRate: Int?
}

// MARK: - Einstellungen

struct UserSettings: Codable, Equatable {
    var raceDate: Date
    var planStart: Date
    var halfMarathonMinutes: Int = 122
    var hasBike: Bool = false
    var bikeSince: Date = Date()
    var weekdayWake: Int = 6 * 60 + 30
    var weekdayBed: Int = 22 * 60 + 30
    var weekendWake: Int = 8 * 60
    var weekendBed: Int = 23 * 60
    var studyMinutes: Int = 60
    var animeMinutes: Int = 60
    var afterSchoolBuffer: Int = 45
    var waterGoalML: Int = 2500
    var includedCalendarIDs: [String] = []
    var schoolCalendarIDs: [String] = []
    var examWeeks: [String] = []
    var notifyTraining: Bool = true
    var notifyStudy: Bool = true
    var notifyWater: Bool = true
    var notifyBedtime: Bool = true
    var notifyMeals: Bool = true
    var healthEnabled: Bool = false
    var stravaClientID: String = ""
    var stravaClientSecret: String = ""

    static func defaults() -> UserSettings {
        let cal = Calendar.app
        // 299 Tage ab 26.10.2026 → 21.08.2027
        let race = cal.date(from: DateComponents(year: 2027, month: 8, day: 21)) ?? Date()
        return UserSettings(raceDate: race, planStart: cal.startOfWeek(Date()))
    }
}

extension UserSettings {
    /// Tolerantes Laden: fehlende Felder (z. B. nach einem App-Update) bekommen Standardwerte.
    init(from decoder: Decoder) throws {
        let d = UserSettings.defaults()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        raceDate = try c.decodeIfPresent(Date.self, forKey: .raceDate) ?? d.raceDate
        planStart = try c.decodeIfPresent(Date.self, forKey: .planStart) ?? d.planStart
        halfMarathonMinutes = try c.decodeIfPresent(Int.self, forKey: .halfMarathonMinutes) ?? d.halfMarathonMinutes
        hasBike = try c.decodeIfPresent(Bool.self, forKey: .hasBike) ?? d.hasBike
        bikeSince = try c.decodeIfPresent(Date.self, forKey: .bikeSince) ?? d.bikeSince
        weekdayWake = try c.decodeIfPresent(Int.self, forKey: .weekdayWake) ?? d.weekdayWake
        weekdayBed = try c.decodeIfPresent(Int.self, forKey: .weekdayBed) ?? d.weekdayBed
        weekendWake = try c.decodeIfPresent(Int.self, forKey: .weekendWake) ?? d.weekendWake
        weekendBed = try c.decodeIfPresent(Int.self, forKey: .weekendBed) ?? d.weekendBed
        studyMinutes = try c.decodeIfPresent(Int.self, forKey: .studyMinutes) ?? d.studyMinutes
        animeMinutes = try c.decodeIfPresent(Int.self, forKey: .animeMinutes) ?? d.animeMinutes
        afterSchoolBuffer = try c.decodeIfPresent(Int.self, forKey: .afterSchoolBuffer) ?? d.afterSchoolBuffer
        waterGoalML = try c.decodeIfPresent(Int.self, forKey: .waterGoalML) ?? d.waterGoalML
        includedCalendarIDs = try c.decodeIfPresent([String].self, forKey: .includedCalendarIDs) ?? d.includedCalendarIDs
        schoolCalendarIDs = try c.decodeIfPresent([String].self, forKey: .schoolCalendarIDs) ?? d.schoolCalendarIDs
        examWeeks = try c.decodeIfPresent([String].self, forKey: .examWeeks) ?? d.examWeeks
        notifyTraining = try c.decodeIfPresent(Bool.self, forKey: .notifyTraining) ?? d.notifyTraining
        notifyStudy = try c.decodeIfPresent(Bool.self, forKey: .notifyStudy) ?? d.notifyStudy
        notifyWater = try c.decodeIfPresent(Bool.self, forKey: .notifyWater) ?? d.notifyWater
        notifyBedtime = try c.decodeIfPresent(Bool.self, forKey: .notifyBedtime) ?? d.notifyBedtime
        notifyMeals = try c.decodeIfPresent(Bool.self, forKey: .notifyMeals) ?? d.notifyMeals
        healthEnabled = try c.decodeIfPresent(Bool.self, forKey: .healthEnabled) ?? d.healthEnabled
        stravaClientID = try c.decodeIfPresent(String.self, forKey: .stravaClientID) ?? d.stravaClientID
        stravaClientSecret = try c.decodeIfPresent(String.self, forKey: .stravaClientSecret) ?? d.stravaClientSecret
    }
}

// MARK: - Speicher

enum Storage {
    static let settingsKey = "settings.v1"
    static let completedKey = "completed.v1"
    static let waterKey = "water.v1"
    static let activitiesKey = "activities.v1"
    static let stravaTokenKey = "strava.token.v1"

    static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func remove(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Kalender & Formatierung

extension Calendar {
    static var app: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.locale = Locale(identifier: "de_DE")
        c.timeZone = .current
        return c
    }

    /// Montag 00:00 der Woche, in der `date` liegt.
    func startOfWeek(_ date: Date) -> Date {
        let day = startOfDay(for: date)
        let weekday = component(.weekday, from: day) // 1 = Sonntag … 7 = Samstag
        let offset = (weekday + 5) % 7
        return self.date(byAdding: .day, value: -offset, to: day) ?? day
    }
}

enum Fmt {
    private static func formatter(_ format: String, locale: String = "de_DE") -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: locale)
        f.timeZone = .current
        f.dateFormat = format
        return f
    }

    private static let keyFormatter = formatter("yyyy-MM-dd", locale: "en_US_POSIX")
    private static let timeFormatter = formatter("HH:mm")
    private static let longDayFormatter = formatter("EEEE, d. MMMM")
    private static let shortDayFormatter = formatter("EE d.M.")
    private static let weekdayFormatter = formatter("EEEE")
    private static let dateFormatter = formatter("d. MMMM yyyy")

    static func dayKey(_ date: Date) -> String { keyFormatter.string(from: date) }
    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }
    static func longDay(_ date: Date) -> String { longDayFormatter.string(from: date) }
    static func shortDay(_ date: Date) -> String { shortDayFormatter.string(from: date) }
    static func weekday(_ date: Date) -> String { weekdayFormatter.string(from: date) }
    static func date(_ date: Date) -> String { dateFormatter.string(from: date) }

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) h" : String(format: "%d:%02d h", h, m)
    }

    static func pace(_ secondsPerKm: Double) -> String {
        let s = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func liters(_ ml: Int) -> String {
        String(format: "%.2f l", Double(ml) / 1000).replacingOccurrences(of: ".", with: ",")
    }

    static func km(_ km: Double) -> String {
        String(format: "%.1f km", km).replacingOccurrences(of: ".", with: ",")
    }
}
