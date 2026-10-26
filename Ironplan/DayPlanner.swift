import Foundation

struct TimeRange: Hashable {
    var start: Date
    var end: Date
    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

enum BlockKind: String {
    case sleep, school, event, training, study, meal, anime, windDown, free
}

struct BusyEvent {
    let title: String
    let start: Date
    let end: Date
    let isSchool: Bool
    let isAllDay: Bool
}

struct PlanBlock: Identifiable, Hashable {
    let kind: BlockKind
    let title: String
    let start: Date
    let end: Date
    var detail: String? = nil
    var session: TrainingSession? = nil

    var id: String { "\(kind.rawValue)-\(Int(start.timeIntervalSince1970))-\(title)" }
    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

struct DayPlan {
    let date: Date
    let wake: Date
    let bed: Date
    let blocks: [PlanBlock]
    let unplaced: [TrainingSession]
    let allDayEvents: [String]
}

/// Verteilt Training, Lernen, Essen und Freizeit in die freien Lücken eines Tages.
/// Schule und Termine kommen aus dem iPhone-Kalender (z. B. Untis-Abo, Fahrstunden).
struct DayPlanner {
    let settings: UserSettings
    let cal: Calendar

    func plan(date: Date, events: [BusyEvent], sessions: [TrainingSession]) -> DayPlan {
        let day = cal.startOfDay(for: date)
        let nextDay = cal.date(byAdding: .day, value: 1, to: day) ?? day
        let todayFree = cal.isDateInWeekend(day)
        let tomorrowFree = cal.isDateInWeekend(nextDay)

        // Aufstehen richtet sich nach heute, Schlafengehen danach, ob morgen Schule ist.
        let wake = at(day, settings: todayFree ? settings.weekendWake : settings.weekdayWake)
        let bedMinutes = tomorrowFree ? settings.weekendBed : settings.weekdayBed
        let bed = at(day, settings: bedMinutes < 4 * 60 ? bedMinutes + 24 * 60 : bedMinutes)
        let nextWake = at(nextDay, settings: tomorrowFree ? settings.weekendWake : settings.weekdayWake)

        let timed = events.filter { !$0.isAllDay && $0.end > day && $0.start < nextDay }
        let allDay = events.filter { $0.isAllDay }.map { $0.title }

        var blocks: [PlanBlock] = []
        let dayStart = wake.addingTimeInterval(20 * 60)
        let windDownStart = bed.addingTimeInterval(-30 * 60)
        var free: [TimeRange] = dayStart < windDownStart ? [TimeRange(start: dayStart, end: windDownStart)] : []

        blocks.append(PlanBlock(kind: .meal, title: "Aufstehen & Frühstück", start: wake, end: dayStart))

        // Schule: einzelne Stunden zu Blöcken zusammenfassen
        let schoolEvents = timed.filter { $0.isSchool }.sorted { $0.start < $1.start }
        var schoolRanges: [TimeRange] = []
        for e in schoolEvents {
            if var last = schoolRanges.last, e.start.timeIntervalSince(last.end) <= 30 * 60 {
                last.end = max(last.end, e.end)
                schoolRanges[schoolRanges.count - 1] = last
            } else {
                schoolRanges.append(TimeRange(start: e.start, end: e.end))
            }
        }

        let buffer = TimeInterval(settings.afterSchoolBuffer * 60)
        for r in schoolRanges {
            var subjects: [String] = []
            for e in schoolEvents where e.start >= r.start && e.end <= r.end && !subjects.contains(e.title) {
                subjects.append(e.title)
            }
            blocks.append(PlanBlock(kind: .school, title: "Schule", start: r.start, end: r.end,
                                    detail: subjects.joined(separator: " · ")))
            free = subtract(free, TimeRange(start: r.start.addingTimeInterval(-20 * 60),
                                            end: r.end.addingTimeInterval(buffer)))
        }

        var lastSchoolEnd: Date? = nil
        if let last = schoolRanges.last {
            let end = last.end.addingTimeInterval(buffer)
            lastSchoolEnd = end
            if buffer > 0 {
                blocks.append(PlanBlock(kind: .meal, title: "Heimweg & Essen", start: last.end, end: end))
            }
        }

        // Andere Termine (Fahrstunden usw.) mit 15 min Weg davor und danach
        for e in timed where !e.isSchool {
            blocks.append(PlanBlock(kind: .event, title: e.title, start: e.start, end: e.end))
            free = subtract(free, TimeRange(start: e.start.addingTimeInterval(-15 * 60),
                                            end: e.end.addingTimeInterval(15 * 60)))
        }

        // Training: längste Einheit zuerst, nicht zu spät am Abend
        var unplaced: [TrainingSession] = []
        let trainingNotBefore = lastSchoolEnd ?? wake.addingTimeInterval(90 * 60)
        let trainingLatestEnd = bed.addingTimeInterval(-75 * 60)
        for s in sessions.filter({ $0.isTraining }).sorted(by: { $0.minutes > $1.minutes }) {
            let need = s.minutes + 20
            let slot = take(need, from: &free, notBefore: trainingNotBefore, latestEnd: trainingLatestEnd)
                ?? take(need, from: &free, notBefore: nil, latestEnd: trainingLatestEnd)
            if let slot {
                let end = slot.start.addingTimeInterval(TimeInterval(s.minutes * 60))
                blocks.append(PlanBlock(kind: .training, title: s.title, start: slot.start, end: end,
                                        detail: Fmt.duration(s.minutes), session: s))
                blocks.append(PlanBlock(kind: .meal, title: "Duschen & Snack", start: end, end: slot.end))
            } else {
                unplaced.append(s)
            }
        }

        // Abendessen
        if let slot = take(30, from: &free, notBefore: at(day, settings: 17 * 60 + 30), latestEnd: at(day, settings: 20 * 60 + 30))
            ?? take(30, from: &free, notBefore: at(day, settings: 17 * 60), latestEnd: windDownStart) {
            blocks.append(PlanBlock(kind: .meal, title: "Abendessen", start: slot.start, end: slot.end))
        }

        // Lernen (außer samstags)
        let isSaturday = cal.component(.weekday, from: day) == 7
        if !isSaturday && settings.studyMinutes > 0 {
            let notBefore = lastSchoolEnd ?? wake.addingTimeInterval(60 * 60)
            let latest = bed.addingTimeInterval(-45 * 60)
            if let slot = take(settings.studyMinutes, from: &free, notBefore: notBefore, latestEnd: latest) {
                blocks.append(PlanBlock(kind: .study, title: "Lernen & Hausaufgaben", start: slot.start, end: slot.end))
            } else {
                let half = max(20, settings.studyMinutes / 2 / 5 * 5)
                for _ in 0..<2 {
                    if let slot = take(half, from: &free, notBefore: nil, latestEnd: latest) {
                        blocks.append(PlanBlock(kind: .study, title: "Lernen & Hausaufgaben", start: slot.start, end: slot.end))
                    }
                }
            }
        }

        // Anime / Freizeit – möglichst am Abend
        if settings.animeMinutes > 0,
           let slot = take(settings.animeMinutes, from: &free, notBefore: nil, latestEnd: windDownStart, preferLate: true)
            ?? take(max(20, settings.animeMinutes / 2), from: &free, notBefore: nil, latestEnd: windDownStart, preferLate: true) {
            blocks.append(PlanBlock(kind: .anime, title: "Anime & Freizeit", start: slot.start, end: slot.end))
        }

        // Abend & Schlaf
        if windDownStart < bed {
            blocks.append(PlanBlock(kind: .windDown, title: "Runterfahren", start: windDownStart, end: bed,
                                    detail: "Handy weg, Sachen für morgen packen, Licht dimmen"))
        }
        let sleepMinutes = Int(nextWake.timeIntervalSince(bed) / 60)
        if sleepMinutes > 0 {
            blocks.append(PlanBlock(kind: .sleep, title: "Schlafen", start: bed, end: nextWake,
                                    detail: "\(Fmt.duration(sleepMinutes)) Schlaf"))
        }

        for r in free where r.minutes >= 20 {
            blocks.append(PlanBlock(kind: .free, title: "Frei", start: r.start, end: r.end))
        }

        blocks.sort { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        return DayPlan(date: day, wake: wake, bed: bed, blocks: blocks, unplaced: unplaced, allDayEvents: allDay)
    }

    // MARK: Hilfsfunktionen

    private func at(_ day: Date, settings minutes: Int) -> Date {
        cal.date(byAdding: .minute, value: minutes, to: day) ?? day
    }

    private func subtract(_ ranges: [TimeRange], _ cut: TimeRange) -> [TimeRange] {
        var out: [TimeRange] = []
        for r in ranges {
            if cut.end <= r.start || cut.start >= r.end {
                out.append(r)
                continue
            }
            if cut.start > r.start { out.append(TimeRange(start: r.start, end: cut.start)) }
            if cut.end < r.end { out.append(TimeRange(start: cut.end, end: r.end)) }
        }
        return out
    }

    /// Nimmt `minutes` aus der ersten (oder bei `preferLate` letzten) passenden Lücke heraus.
    private func take(_ minutes: Int, from free: inout [TimeRange], notBefore: Date?,
                      latestEnd: Date?, preferLate: Bool = false) -> TimeRange? {
        let need = TimeInterval(minutes * 60)
        let ordered = free.sorted { preferLate ? $0.start > $1.start : $0.start < $1.start }
        for r in ordered {
            let lo = roundUp(max(r.start, notBefore ?? r.start))
            let hi = roundDown(min(r.end, latestEnd ?? r.end))
            guard hi.timeIntervalSince(lo) >= need else { continue }
            let slot = preferLate
                ? TimeRange(start: hi.addingTimeInterval(-need), end: hi)
                : TimeRange(start: lo, end: lo.addingTimeInterval(need))
            free = subtract(free, slot)
            return slot
        }
        return nil
    }

    private func roundUp(_ d: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (d.timeIntervalSinceReferenceDate / 300).rounded(.up) * 300)
    }

    private func roundDown(_ d: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (d.timeIntervalSinceReferenceDate / 300).rounded(.down) * 300)
    }
}
