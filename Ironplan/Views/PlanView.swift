import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selected: TrainingSession?
    @State private var didScroll = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if let week = model.currentWeek {
                        Section {
                            Text(week.phase.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } header: {
                            Text("Aktuelle Phase: \(week.phase.label)")
                        }
                    }

                    ForEach(model.weeks) { week in
                        Section {
                            ForEach(week.sessions) { session in
                                SessionRow(session: session, showDay: true)
                                    .onTapGesture { selected = session }
                            }
                        } header: {
                            WeekHeader(week: week, isCurrent: week.id == model.currentWeek?.id) {
                                model.toggleExamWeek(week.start)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .onAppear {
                    guard !didScroll, let id = model.currentWeek?.sessions.first?.id else { return }
                    didScroll = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }
            .navigationTitle("Trainingsplan")
            .sheet(item: $selected) { session in
                SessionDetailView(session: session)
                    .environmentObject(model)
            }
        }
    }
}

private struct WeekHeader: View {
    let week: TrainingWeek
    let isCurrent: Bool
    let toggleExam: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Woche \(week.index + 1)").bold()
                    if isCurrent {
                        Text("JETZT")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                Text("\(Fmt.shortDay(week.start)) · \(week.phase.label) · \(Fmt.duration(week.totalMinutes))"
                     + (week.isRecovery ? " · Erholung" : ""))
                    .font(.caption)
            }
            Spacer()
            Button(action: toggleExam) {
                Label(week.isExam ? "Prüfungswoche" : "Prüfungen?",
                      systemImage: week.isExam ? "checkmark.circle.fill" : "graduationcap")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .tint(week.isExam ? Color.blue : Color.secondary)
        }
        .textCase(nil)
    }
}
