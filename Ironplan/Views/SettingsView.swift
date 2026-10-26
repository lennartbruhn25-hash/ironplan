import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showStrava = false

    var body: some View {
        NavigationStack {
            Form {
                raceSection
                bikeSection
                sleepSection
                daySection
                calendarSection
                notificationSection
                Section("Verbindungen") {
                    Button("Strava einrichten") { showStrava = true }
                }
            }
            .navigationTitle("Einstellungen")
            .sheet(isPresented: $showStrava) { StravaSetupView().environmentObject(model) }
        }
    }

    // MARK: Abschnitte

    private var raceSection: some View {
        Section {
            DatePicker("Wettkampf", selection: $model.settings.raceDate, displayedComponents: .date)
            Stepper(value: $model.settings.halfMarathonMinutes, in: 80...200) {
                HStack {
                    Text("Halbmarathon-Zeit")
                    Spacer()
                    Text(Fmt.duration(model.settings.halfMarathonMinutes)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Ziel")
        } footer: {
            Text("Aus deiner Halbmarathon-Zeit werden die Lauftempos im Plan berechnet. Wenn du schneller wirst: hier anpassen.")
        }
    }

    private var bikeSection: some View {
        Section {
            Toggle("Ich habe ein Rennrad", isOn: $model.settings.hasBike)
            if model.settings.hasBike {
                DatePicker("Seit", selection: $model.settings.bikeSince, displayedComponents: .date)
            }
        } header: {
            Text("Rad")
        } footer: {
            Text("Bis du ein Rad hast, schwimmst und läufst du mehr. Danach baut sich der Plan automatisch mit Radeinheiten um.")
        }
    }

    private var sleepSection: some View {
        Section {
            DatePicker("Aufstehen (Schultag)", selection: time(\.weekdayWake), displayedComponents: .hourAndMinute)
            DatePicker("Ins Bett (vor Schultag)", selection: time(\.weekdayBed), displayedComponents: .hourAndMinute)
            DatePicker("Aufstehen (Wochenende)", selection: time(\.weekendWake), displayedComponents: .hourAndMinute)
            DatePicker("Ins Bett (vor freiem Tag)", selection: time(\.weekendBed), displayedComponents: .hourAndMinute)
        } header: {
            Text("Schlaf")
        } footer: {
            Text("Mit viel Training brauchst du 8–9 Stunden Schlaf. Darin passiert die Anpassung.")
        }
    }

    private var daySection: some View {
        Section {
            minutesStepper("Lernen pro Tag", value: $model.settings.studyMinutes, range: 0...240, step: 15)
            minutesStepper("Anime & Freizeit", value: $model.settings.animeMinutes, range: 0...240, step: 15)
            minutesStepper("Heimweg & Essen nach der Schule", value: $model.settings.afterSchoolBuffer, range: 0...120, step: 15)
            Stepper(value: $model.settings.waterGoalML, in: 1500...4500, step: 250) {
                HStack {
                    Text("Wasser (Grundbedarf)")
                    Spacer()
                    Text(Fmt.liters(model.settings.waterGoalML)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Tagesablauf")
        } footer: {
            Text("An Trainingstagen kommt pro Stunde Training ca. ½ l Wasser dazu.")
        }
    }

    private var calendarSection: some View {
        Section {
            if !model.calendarAuthorized {
                Button("Kalenderzugriff erlauben") {
                    Task { await model.requestCalendarAccess() }
                }
            } else if model.calendars.isEmpty {
                Text("Keine Kalender gefunden.").foregroundStyle(.secondary)
            } else {
                ForEach(model.calendars) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle().fill(c.color).frame(width: 10, height: 10)
                            Text(c.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(c.source).font(.caption).foregroundStyle(.secondary)
                        }
                        Toggle("Einbeziehen", isOn: Binding(
                            get: { model.isCalendarIncluded(c.id) },
                            set: { model.setCalendar(c.id, included: $0) }))
                            .font(.caption)
                        Toggle("Das ist mein Stundenplan", isOn: Binding(
                            get: { model.isSchoolCalendar(c.id) },
                            set: { model.setSchoolCalendar(c.id, $0) }))
                            .font(.caption)
                            .disabled(!model.isCalendarIncluded(c.id))
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Kalender & Untis")
        } footer: {
            Text("""
            Untis aufs iPhone holen: In WebUntis im Browser den Kalender-Abo-Link (iCal) deines Stundenplans kopieren – meist über das Teilen-/Kalender-Symbol im Stundenplan oder im Profil unter „Freigaben“. Dann am iPhone: Einstellungen → Kalender → Accounts → Account hinzufügen → Andere → Kalenderabo hinzufügen → Link einfügen. Danach hier als „Stundenplan“ markieren. (Nicht jede Schule schaltet das frei.)

            Fahrstunden & Co.: Einfach in einem Kalender auf dem iPhone eintragen (z. B. Google-Kalender, unter Einstellungen → Kalender → Accounts hinzufügen).
            """)
        }
    }

    private var notificationSection: some View {
        Section("Benachrichtigungen") {
            Toggle("Training (15 min vorher)", isOn: $model.settings.notifyTraining)
            Toggle("Lernzeit", isOn: $model.settings.notifyStudy)
            Toggle("Trinken (alle 2 h)", isOn: $model.settings.notifyWater)
            Toggle("Abendessen", isOn: $model.settings.notifyMeals)
            Toggle("Schlafenszeit", isOn: $model.settings.notifyBedtime)
        }
    }

    // MARK: Hilfen

    private func minutesStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue == 0 ? "aus" : Fmt.duration(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Verbindet Minuten seit Mitternacht mit einem Uhrzeit-Picker.
    private func time(_ keyPath: WritableKeyPath<UserSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = model.settings[keyPath: keyPath]
                return model.cal.date(bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = model.cal.dateComponents([.hour, .minute], from: date)
                model.settings[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }
}
