import SwiftUI

/// Aktivitäten-Hub: alles, was du wirklich gemacht hast – aus Apple Health (inkl. Suunto) und Strava.
struct HubView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showStravaHelp = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let message = model.syncMessage {
                        Card {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                    }

                    if let week = model.currentWeek { weekCard(week) }
                    connections
                    activityList
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Aktivitäten")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isSyncing {
                        ProgressView()
                    } else {
                        Button {
                            Task { await model.syncActivities() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable { await model.syncActivities() }
            .sheet(isPresented: $showStravaHelp) { StravaSetupView().environmentObject(model) }
        }
    }

    // MARK: Woche: Plan vs. Ist

    private func weekCard(_ week: TrainingWeek) -> some View {
        let summary = model.weekSummary(week)
        let planned = summary.reduce(0) { $0 + $1.planned }
        let done = summary.reduce(0) { $0 + $1.done }
        return Card {
            HStack {
                Label("Diese Woche", systemImage: "chart.bar.fill").font(.headline)
                Spacer()
                Text("\(Fmt.duration(done)) / \(Fmt.duration(planned))")
                    .font(.subheadline.bold())
                    .monospacedDigit()
            }
            ForEach(summary, id: \.sport) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: item.sport.symbol).foregroundStyle(item.sport.color)
                        Text(item.sport.label).font(.subheadline)
                        Spacer()
                        Text("\(Fmt.duration(item.done)) / \(Fmt.duration(item.planned))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    ProgressView(value: Double(min(item.done, max(item.planned, 1))),
                                 total: Double(max(item.planned, 1)))
                        .tint(item.sport.color)
                }
            }
        }
    }

    // MARK: Verbindungen

    private var connections: some View {
        Card {
            Label("Verbindungen", systemImage: "link").font(.headline)

            ConnectionRow(
                title: "Apple Health",
                subtitle: model.settings.healthEnabled ? "Workouts, Schlaf und Wasser" : "Workouts, Schlaf und Wasser lesen",
                symbol: "heart.fill", color: .red,
                connected: model.settings.healthEnabled,
                connect: { Task { await model.connectHealth() } },
                disconnect: { model.disconnectHealth() })

            Divider()

            ConnectionRow(
                title: "Strava",
                subtitle: model.strava.isConnected
                    ? "Verbunden\(model.strava.token?.athleteName.map { " als \($0)" } ?? "")"
                    : "Eigene API-App nötig – tippe auf „Einrichten“",
                symbol: "figure.run.circle.fill", color: .orange,
                connected: model.strava.isConnected,
                connect: {
                    if model.settings.stravaClientID.isEmpty || model.settings.stravaClientSecret.isEmpty {
                        showStravaHelp = true
                    } else {
                        Task { await model.connectStrava() }
                    }
                },
                disconnect: { model.disconnectStrava() },
                connectLabel: model.settings.stravaClientID.isEmpty ? "Einrichten" : "Verbinden")

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "applewatch.side.right")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suunto").font(.subheadline.weight(.semibold))
                    Text("Läuft über Apple Health: In der Suunto-App die Verbindung zu Apple Health einschalten. Alternativ Suunto → Strava.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Liste

    private var activityList: some View {
        let grouped = Dictionary(grouping: model.activities) { model.cal.startOfDay(for: $0.start) }
        let days = grouped.keys.sorted(by: >).prefix(30)
        return Card {
            Label("Letzte Aktivitäten", systemImage: "list.bullet").font(.headline)
            if days.isEmpty {
                Text("Noch nichts da. Verbinde Apple Health oder Strava – dann erscheinen deine Workouts hier und werden automatisch mit dem Plan abgeglichen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(days), id: \.self) { day in
                VStack(alignment: .leading, spacing: 8) {
                    Text(Fmt.longDay(day))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(grouped[day] ?? []) { ActivityLine(activity: $0) }
                }
                .padding(.top, 4)
            }
        }
    }
}

private struct ConnectionRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let connected: Bool
    let connect: () -> Void
    let disconnect: () -> Void
    var connectLabel = "Verbinden"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if connected {
                Menu {
                    Button("Trennen", role: .destructive, action: disconnect)
                } label: {
                    Label("Verbunden", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            } else {
                Button(connectLabel, action: connect)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }
}

/// Schritt-für-Schritt-Anleitung, um Strava einmalig einzurichten.
struct StravaSetupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("So geht's (einmalig, 3 Minuten)") {
                    Text("1. Im Browser strava.com/settings/api öffnen und anmelden.")
                    Text("2. Eine Anwendung erstellen: Name z. B. „Ironplan“, Kategorie egal, Website z. B. http://localhost.")
                    Text("3. Bei „Authorization Callback Domain“ genau localhost eintragen.")
                    Text("4. Client-ID und Client-Secret unten einfügen, dann „Verbinden“.")
                }
                Section {
                    TextField("Client-ID", text: $model.settings.stravaClientID)
                        .keyboardType(.numberPad)
                    SecureField("Client-Secret", text: $model.settings.stravaClientSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Zugangsdaten")
                } footer: {
                    Text("Das Secret bleibt nur auf deinem iPhone.")
                }
                Section {
                    Button("Mit Strava verbinden") {
                        dismiss()
                        Task { await model.connectStrava() }
                    }
                    .disabled(model.settings.stravaClientID.isEmpty || model.settings.stravaClientSecret.isEmpty)
                }
            }
            .navigationTitle("Strava einrichten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
    }
}
