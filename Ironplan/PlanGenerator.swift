import Foundation

/// Baut den kompletten Trainingsplan vom Planstart bis zum Wettkampf.
/// Grundidee: Umfang steigt langsam von ~4,5 h auf ~13,5 h pro Woche,
/// jede 4. Woche ist eine Erholungswoche, Prüfungswochen werden stark reduziert.
struct PlanGenerator {
    let settings: UserSettings
    let cal: Calendar

    private enum Kind { case easy, technique, endurance, quality, long, mid, brick, strength, rest }

    private struct Slot {
        let day: Int          // 0 = Montag … 6 = Sonntag
        let sport: Sport
        let kind: Kind
        let weight: Double
        let fixedMinutes: Int?

        init(_ day: Int, _ sport: Sport, _ kind: Kind, _ weight: Double, fixed: Int? = nil) {
            self.day = day
            self.sport = sport
            self.kind = kind
            self.weight = weight
            self.fixedMinutes = fixed
        }
    }

    func generate() -> [TrainingWeek] {
        let start = cal.startOfWeek(settings.planStart)
        let raceDay = cal.startOfDay(for: settings.raceDate)
        let raceWeekStart = cal.startOfWeek(raceDay)
        let days = cal.dateComponents([.day], from: start, to: raceWeekStart).day ?? -1
        guard days >= 0 else { return [] }
        let weekCount = days / 7 + 1

        var weeks: [TrainingWeek] = []
        for i in 0..<weekCount {
            guard let weekStart = cal.date(byAdding: .day, value: i * 7, to: start) else { continue }
            let remaining = weekCount - 1 - i
            let phase = phaseFor(remaining: remaining)
            let exam = settings.examWeeks.contains(Fmt.dayKey(weekStart))
            let recovery = isRecovery(index: i, remaining: remaining)

            let sessions: [TrainingSession]
            if remaining == 0 {
                sessions = raceWeekSessions(weekStart: weekStart, raceDay: raceDay)
            } else {
                var hours = targetHours(index: i, remaining: remaining, weekCount: weekCount)
                if recovery { hours *= 0.65 }
                if exam { hours *= 0.55 }
                sessions = buildWeek(weekStart: weekStart, phase: phase, totalMinutes: Int(hours * 60),
                                     exam: exam, recovery: recovery)
            }
            weeks.append(TrainingWeek(index: i, start: weekStart, phase: phase,
                                      isRecovery: recovery, isExam: exam, sessions: sessions))
        }
        return weeks
    }

    // MARK: Periodisierung

    private func phaseFor(remaining: Int) -> Phase {
        switch remaining {
        case 0: return .raceWeek
        case 1...2: return .taper
        case 3...7: return .peak
        case 8...17: return .build2
        case 18...27: return .build1
        case 28...35: return .base2
        default: return .base1
        }
    }

    private func isRecovery(index: Int, remaining: Int) -> Bool {
        (remaining >= 8 && index % 4 == 3) || remaining == 5
    }

    private func targetHours(index: Int, remaining: Int, weekCount: Int) -> Double {
        switch remaining {
        case 1: return 6.5
        case 2: return 9
        case 3...7: return 14
        default:
            let peakStart = max(1, weekCount - 8)
            let progress = min(1, Double(index) / Double(peakStart))
            return 4.5 + (13.5 - 4.5) * progress
        }
    }

    private func hasBike(inWeekStarting weekStart: Date) -> Bool {
        guard settings.hasBike else { return false }
        guard let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) else { return true }
        return cal.startOfDay(for: settings.bikeSince) <= weekEnd
    }

    // MARK: Wochen-Vorlagen

    private func template(phase: Phase, bike: Bool) -> [Slot] {
        let isBase = !phase.isBuildOrLater
        let late = phase == .build2 || phase == .peak || phase == .taper

        if !bike {
            // Ohne Rad: 3× Schwimmen, 3× Laufen, Kraft
            return [
                Slot(0, .rest, .rest, 0),
                Slot(1, .swim, .technique, 0.18),
                Slot(2, .run, isBase ? .easy : .quality, 0.18),
                Slot(3, .swim, isBase ? .technique : .endurance, 0.18),
                Slot(3, .strength, .strength, 0, fixed: 25),
                Slot(4, .run, .easy, 0.12),
                Slot(5, .swim, .endurance, 0.14),
                Slot(6, .run, .long, 0.20),
            ]
        }

        var slots: [Slot] = [
            Slot(0, .rest, .rest, 0),
            Slot(1, .swim, isBase ? .technique : .endurance, late ? 0.11 : 0.13),
            Slot(2, .run, isBase ? .easy : .quality, late ? 0.13 : 0.14),
            Slot(3, .bike, isBase ? .mid : .quality, 0.16),
        ]
        if isBase { slots.append(Slot(3, .strength, .strength, 0, fixed: 20)) }
        slots.append(Slot(4, .swim, .endurance, late ? 0.11 : 0.12))
        if late {
            slots.append(Slot(5, .brick, .brick, 0.34))
        } else {
            slots.append(Slot(5, .bike, .long, 0.27))
        }
        slots.append(Slot(6, .run, .long, late ? 0.15 : 0.18))
        return slots
    }

    private func allowedRange(sport: Sport, kind: Kind, phase: Phase) -> ClosedRange<Int> {
        let longSwim = phase == .build2 || phase == .peak
        switch (sport, kind) {
        case (.swim, .technique): return 30...60
        case (.swim, _): return 30...(longSwim ? 90 : 75)
        case (.run, .long): return 45...150
        case (.run, .quality): return 40...75
        case (.run, _): return 25...60
        case (.bike, .long): return 60...330
        case (.bike, _): return 45...120
        case (.brick, _): return 90...360
        default: return 0...600
        }
    }

    private func buildWeek(weekStart: Date, phase: Phase, totalMinutes: Int, exam: Bool, recovery: Bool) -> [TrainingSession] {
        let slots = template(phase: phase, bike: hasBike(inWeekStarting: weekStart))
        let fixed = slots.compactMap { $0.fixedMinutes }.reduce(0, +)
        let flexible = max(0, totalMinutes - fixed)
        let weightSum = slots.filter { $0.fixedMinutes == nil }.map { $0.weight }.reduce(0, +)

        var result: [TrainingSession] = []
        for slot in slots {
            guard let day = cal.date(byAdding: .day, value: slot.day, to: weekStart) else { continue }
            var minutes: Int
            if slot.sport == .rest {
                minutes = 0
            } else if let f = slot.fixedMinutes {
                minutes = f
            } else {
                let raw = weightSum > 0 ? Double(flexible) * slot.weight / weightSum : 0
                let rounded = Int((raw / 5).rounded()) * 5
                let range = allowedRange(sport: slot.sport, kind: slot.kind, phase: phase)
                minutes = min(max(rounded, range.lowerBound), range.upperBound)
            }
            if exam && minutes > 75 { minutes = 75 }

            let text = describe(sport: slot.sport, kind: slot.kind, minutes: minutes, phase: phase,
                                recovery: recovery, exam: exam)
            result.append(TrainingSession(
                id: "\(Fmt.dayKey(day))-\(slot.sport.rawValue)",
                day: day,
                sport: slot.sport,
                title: text.title,
                minutes: minutes,
                details: text.details,
                isKey: slot.kind == .long || slot.kind == .brick))
        }
        return result
    }

    // MARK: Beschreibungen

    private var hmPace: Double { Double(settings.halfMarathonMinutes * 60) / 21.0975 }
    private var easyPace: String { "\(Fmt.pace(hmPace + 55))–\(Fmt.pace(hmPace + 85))" }
    private var tempoPace: String { Fmt.pace(hmPace) }
    private var intervalPace: String { Fmt.pace(hmPace - 20) }

    private func describe(sport: Sport, kind: Kind, minutes: Int, phase: Phase,
                          recovery: Bool, exam: Bool) -> (title: String, details: String) {
        var title: String
        var details: String

        switch (sport, kind) {
        case (.rest, _):
            title = "Ruhetag"
            details = "Erholung ist Training: früh schlafen, gut essen. Lockeres Dehnen oder Spazierengehen ist okay."

        case (.swim, .technique):
            let dist = swimDistance(minutes)
            title = "Schwimmen · Technik"
            details = """
            ca. \(dist) m
            • 200 m einschwimmen (Brust oder Kraul)
            • 6–10 × 50 m Kraul-Technik: Abschlagschwimmen, einarmig, Züge zählen – je 30 s Pause
            • 4 × 100 m Kraul ruhig, 30 s Pause
            • 100 m ausschwimmen

            Fokus: unter Wasser komplett ausatmen, Kopf ruhig, lange Züge. Ziel der Phase: 400 m Kraul am Stück.
            """

        case (.swim, _):
            let dist = swimDistance(minutes)
            title = "Schwimmen · Ausdauer"
            switch phase {
            case .base1, .base2:
                details = "ca. \(dist) m\n• 200 m einschwimmen\n• 6–10 × 100 m Kraul, 20 s Pause\n• 4 × 50 m Technik\n• ausschwimmen\n\nAtmung jeden 3. Zug üben – das brauchst du im Freiwasser."
            case .build1:
                details = "ca. \(dist) m\n• 300 m einschwimmen\n• 3–4 × 400 m Kraul ruhig, 45 s Pause\n• 4 × 50 m zügig\n• ausschwimmen"
            case .taper, .raceWeek:
                details = "ca. \(dist) m locker, dazwischen 4 × 100 m im Wettkampftempo."
            default:
                details = "ca. \(dist) m\nLange Strecke am Stück im ruhigen Ironman-Tempo (Ziel: 3,8 km schaffen). Ab Mai, wenn möglich, im Freiwasser mit Neoprenanzug."
            }

        case (.run, .long):
            title = "Laufen · lang"
            details = "Lang und locker bei \(easyPace) min/km. Ab 75 min Getränk/Gel mitnehmen und Verpflegung üben."

        case (.run, .quality):
            title = "Laufen · Tempo"
            switch phase {
            case .build1:
                details = "15 min einlaufen · 5 × 4 min bei ~\(intervalPace) min/km, je 2 min traben · 10 min auslaufen"
            case .taper, .raceWeek:
                details = "Locker laufen, dazwischen 4 × 1 min zügig."
            default:
                details = "15 min einlaufen · 2 × 15 min bei ~\(tempoPace) min/km (Halbmarathon-Tempo), 5 min locker dazwischen · auslaufen"
            }

        case (.run, _):
            title = "Laufen · locker"
            details = "Plaudertempo: \(easyPace) min/km. Wenn du nicht mehr reden kannst, bist du zu schnell."

        case (.bike, .long):
            title = "Rad · lang"
            details = "Lange Ausfahrt im Grundlagenbereich. Alle 20 min trinken, alle 30–40 min essen – genau wie im Wettkampf."

        case (.bike, .quality):
            title = "Rad · Intervalle"
            details = phase == .build1
                ? "20 min locker · 3 × 10 min zügig (Sweetspot), je 5 min locker · ausrollen. Bei Dunkelheit: Rolle oder Spinning."
                : "20 min locker · 2 × 20 min im geplanten Ironman-Tempo · ausrollen."

        case (.bike, _):
            title = "Rad · Grundlage"
            details = "Locker (Zone 2), Trittfrequenz 85–95 U/min. Bei Regen oder Dunkelheit: Rollentrainer oder Spinning."

        case (.brick, _):
            let run = min(30, max(15, (minutes / 10) / 5 * 5))
            let bike = max(0, minutes - run)
            title = "Koppeltraining · Rad \(Fmt.duration(bike)) + Lauf \(run) min"
            details = "Lange Radeinheit im Ironman-Tempo, direkt danach laufen (Wechsel unter 5 min). Die ersten Kilometer fühlen sich komisch an – genau das trainierst du. Verpflegung wie im Wettkampf."

        case (.strength, _):
            title = "Kraft & Stabi"
            details = "2–3 Runden: 15 Kniebeugen, 10 Ausfallschritte je Bein, 45 s Unterarmstütz, 30 s Seitstütz je Seite, 15 × einbeiniges Wadenheben. Schützt Knie und Rücken."

        default:
            title = sport.label
            details = ""
        }

        if recovery && sport != .rest {
            details = "Erholungswoche – bewusst locker bleiben.\n\n" + details
        }
        if exam && sport != .rest {
            details = "Prüfungswoche – Training ist gekürzt, Schule geht vor.\n\n" + details
        }
        return (title, details)
    }

    private func swimDistance(_ minutes: Int) -> Int {
        max(500, Int((Double(minutes) * 28 / 100).rounded()) * 100)
    }

    // MARK: Wettkampfwoche

    private func raceWeekSessions(weekStart: Date, raceDay: Date) -> [TrainingSession] {
        let bike = hasBike(inWeekStarting: weekStart)
        var out: [TrainingSession] = []
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let before = cal.dateComponents([.day], from: day, to: raceDay).day ?? 0
            let item: (sport: Sport, title: String, minutes: Int, details: String)
            switch before {
            case 0:
                item = (.race, "IRONMAN VICHY 🏁", 0,
                        "3,8 km Schwimmen · 180 km Rad · 42,2 km Laufen.\nRuhig starten, eigenes Tempo, essen und trinken nach Plan. Du hast lange dafür gearbeitet.")
            case 1:
                item = (.run, "Aktivierung", 25,
                        "15 min Rad oder locker joggen, dazu 3 kurze Steigerungen. Rad und Wechselbeutel einchecken. Früh essen, früh schlafen.")
            case 2:
                item = (.rest, "Ruhetag", 0, "Beine hoch, Startunterlagen abholen, Wettkampfbesprechung.")
            case 3:
                item = (.swim, "Schwimmen · locker", 25, "Locker schwimmen, 4 × 50 m Renntempo. Wenn möglich: Probeschwimmen vor Ort.")
            case 4:
                item = (.run, "Laufen · locker", 30, "Locker laufen, 4 × 20 s Steigerungen.")
            case 5:
                if bike {
                    item = (.bike, "Rad · locker", 60, "Locker fahren, 3 × 5 min im Renntempo.")
                } else {
                    item = (.run, "Laufen · locker", 30, "Locker laufen.")
                }
            case 6:
                item = (.swim, "Schwimmen · locker", 30, "Locker, ein paar Abschnitte im Renntempo.")
            default:
                item = (.rest, "Erholung", 0, "Erholung. Du bist IRONMAN. 🎉")
            }
            out.append(TrainingSession(
                id: "\(Fmt.dayKey(day))-\(item.sport.rawValue)",
                day: day, sport: item.sport, title: item.title,
                minutes: item.minutes, details: item.details, isKey: before == 0))
        }
        return out
    }
}
