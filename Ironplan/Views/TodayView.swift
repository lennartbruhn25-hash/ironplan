import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @State private var date = Date()
    @State private var selected: TrainingSession?

    private var isToday: Bool { model.cal.isDateInToday(date) }

    var body: some View {
        let plan = model.dayPlan(for: date)
        let sessions = model.sessions(on: date)
        let training = sessions.filter { $0.isTraining || $0.sport == .race }

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if isToday { countdown }
                    daySwitcher

                    if !model.calendarAuthorized { connectCalendarCard }
                    if model.needsBikeSoon { bikeCard }

                    trainingCard(training: training, isRestDay: training.isEmpty)

                    if !plan.unplaced.isEmpty { unplacedCard(plan.unplaced) }

                    HStack(spacing: 14) {
                        waterCard
                        sleepCard(plan: plan)
                    }

                    Card {
                        Label("Essen heute", systemImage: "fork.knife")
                            .font(.headline)
                        Text(model.nutritionTip(for: date))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    timeline(plan)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(isToday ? "Heute" : Fmt.weekday(date))
            .refreshable { await model.appBecameActive() }
            .sheet(item: $selected) { session in
                SessionDetailView(session: session)
                    .environmentObject(model)
            }
        }
    }

    // MARK: Countdown

    private var countdown: some View {
        let week = model.currentWeek
        return Card {
            HStack(alignment: .firstTextBaseline) {
                Text("\(max(0, model.daysUntilRace))")
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                VStack(alignment: .leading) {
                    Text("Tage bis Vichy").font(.headline)
                    Text(Fmt.date(model.settings.raceDate)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let week {
                HStack {
                    Text("Woche \(week.index + 1) von \(model.weeks.count)")
                    Text("·")
                    Text(week.phase.label).bold()
                    if week.isRecovery { Text("· Erholung").foregroundStyle(.green) }
                    if week.isExam { Text("· Prüfungen").foregroundStyle(.blue) }
                }
                .font(.subheadline)
                ProgressView(value: Double(week.index + 1), total: Double(max(1, model.weeks.count)))
                    .tint(.orange)
            }
        }
    }

    // MARK: Tag wechseln

    private var daySwitcher: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left.circle.fill").font(.title2) }
            Spacer()
            VStack(spacing: 2) {
                Text(Fmt.longDay(date)).font(.headline)
                if !isToday {
                    Button("Zurück zu heute") { date = Date() }.font(.caption)
                }
            }
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right.circle.fill").font(.title2) }
        }
        .padding(.vertical, 4)
    }

    private func shift(_ days: Int) {
        date = model.cal.date(byAdding: .day, value: days, to: date) ?? date
    }

    // MARK: Training

    private func trainingCard(training: [TrainingSession], isRestDay: Bool) -> some View {
        Card {
            HStack {
                Label(isRestDay ? "Ruhetag" : "Training", systemImage: isRestDay ? "bed.double.fill" : "flame.fill")
                    .font(.headline)
                    .foregroundStyle(isRestDay ? Color.secondary : Color.orange)
                Spacer()
                if !isRestDay {
                    Text(Fmt.duration(training.reduce(0) { $0 + $1.minutes }))
                        .font(.subheadline.bold())
                        .monospacedDigit()
                }
            }
            if isRestDay {
                Text("Heute erholst du dich. Das gehört genauso zum Plan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(training) { session in
                    HStack {
                        SessionRow(session: session)
                            .onTapGesture { selected = session }
                        if session.isTraining {
                            Button {
                                model.toggleDone(session)
                            } label: {
                                Image(systemName: model.isDone(session) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(model.isDone(session) ? Color.green : Color.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            let done = model.doneActivities(on: date).filter { a in
                !training.contains { model.matchedActivity(for: $0)?.id == a.id }
            }
            if !done.isEmpty {
                Divider()
                Text("Außerdem gemacht").font(.caption).foregroundStyle(.secondary)
                ForEach(done) { ActivityLine(activity: $0) }
            }
        }
    }

    private func unplacedCard(_ sessions: [TrainingSession]) -> some View {
        Card {
            Label("Kein Platz im Kalender", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.yellow)
            Text("Für \(sessions.map { $0.title }.joined(separator: ", ")) ist heute keine passende Lücke frei. Kürzer machen, auf morgen schieben oder einen Termin verschieben.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Wasser & Schlaf

    private var waterCard: some View {
        let ml = model.waterML(on: date)
        let goal = model.waterGoal(on: date)
        return Card {
            Label("Wasser", systemImage: "drop.fill")
                .font(.headline)
                .foregroundStyle(.cyan)
            Text("\(Fmt.liters(ml)) / \(Fmt.liters(goal))")
                .font(.subheadline.bold())
                .monospacedDigit()
            ProgressView(value: min(Double(ml), Double(goal)), total: Double(max(goal, 1)))
                .tint(.cyan)
            HStack {
                Button { model.addWater(-250, on: date) } label: { Image(systemName: "minus") }
                    .buttonStyle(.bordered)
                Button { model.addWater(250, on: date) } label: { Text("+250 ml").font(.caption.bold()) }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
            }
            .controlSize(.small)
        }
    }

    private func sleepCard(plan: DayPlan) -> some View {
        Card {
            Label("Schlaf", systemImage: "moon.zzz.fill")
                .font(.headline)
                .foregroundStyle(.indigo)
            Text("Ins Bett: \(Fmt.time(plan.bed))")
                .font(.subheadline.bold())
                .monospacedDigit()
            if isToday, let slept = model.lastNightSleep {
                Text("Letzte Nacht: \(Fmt.duration(slept))")
                    .font(.caption)
                    .foregroundStyle(slept >= 8 * 60 ? Color.green : Color.orange)
            } else {
                Text("Ziel: 8–9 h – im Training wächst du im Schlaf.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Zeitplan

    private func timeline(_ plan: DayPlan) -> some View {
        Card {
            Label("Zeitplan", systemImage: "clock.fill").font(.headline)
            if !plan.allDayEvents.isEmpty {
                Text(plan.allDayEvents.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(plan.blocks) { block in
                HStack(alignment: .top, spacing: 12) {
                    Text(Fmt.time(block.start))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .leading)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(block.kind.color)
                        .frame(width: 4)
                        .frame(minHeight: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Label(block.title, systemImage: block.session?.sport.symbol ?? block.kind.symbol)
                            .font(.subheadline.weight(block.kind == .training ? .bold : .regular))
                            .foregroundStyle(block.kind == .free ? Color.secondary : Color.primary)
                        Text(block.detail ?? "bis \(Fmt.time(block.end)) · \(Fmt.duration(block.minutes))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if let s = block.session { selected = s }
                }
            }
        }
    }

    // MARK: Hinweise

    private var connectCalendarCard: some View {
        Card {
            Label("Kalender verbinden", systemImage: "calendar.badge.plus").font(.headline)
            Text("Damit die App Schule (Untis) und Termine wie Fahrstunden kennt und Training in die Lücken legt.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Zugriff erlauben") {
                Task { await model.requestCalendarAccess() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var bikeCard: some View {
        Card {
            Label("Zeit fürs Rennrad", systemImage: "bicycle").font(.headline).foregroundStyle(.orange)
            Text("Du bist in der Aufbauphase. Ohne Rad fehlen dir die langen Ausfahrten. Sobald du eins hast: in den Einstellungen „Ich habe ein Rennrad“ einschalten, dann baut sich der Plan um.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
