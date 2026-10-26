import SwiftUI

extension BlockKind {
    var symbol: String {
        switch self {
        case .sleep: return "moon.zzz.fill"
        case .school: return "graduationcap.fill"
        case .event: return "calendar"
        case .training: return "figure.run"
        case .study: return "book.fill"
        case .meal: return "fork.knife"
        case .anime: return "tv.fill"
        case .windDown: return "moon.stars.fill"
        case .free: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .sleep: return .indigo
        case .school: return .blue
        case .event: return .teal
        case .training: return .orange
        case .study: return .mint
        case .meal: return .brown
        case .anime: return .pink
        case .windDown: return .purple
        case .free: return .gray
        }
    }
}

/// Einheitliche Karte als Hintergrund.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct SportIcon: View {
    let sport: Sport
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: sport.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(sport.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

struct SessionRow: View {
    @EnvironmentObject private var model: AppModel
    let session: TrainingSession
    var showDay = false

    var body: some View {
        let done = model.isDone(session)
        HStack(spacing: 12) {
            SportIcon(sport: session.sport, size: 36)
                .opacity(session.sport == .rest ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 2) {
                if showDay {
                    Text(Fmt.shortDay(session.day))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(session.title)
                    .font(.subheadline.weight(session.isKey ? .bold : .medium))
                    .strikethrough(done, color: .secondary)
                    .foregroundStyle(session.sport == .rest ? Color.secondary : Color.primary)
                if session.minutes > 0 {
                    Text(Fmt.duration(session.minutes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }
        }
        .contentShape(Rectangle())
    }
}

struct SessionDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let session: TrainingSession

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        SportIcon(sport: session.sport, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title).font(.title3.bold())
                            Text(Fmt.longDay(session.day)).foregroundStyle(.secondary)
                            if session.minutes > 0 {
                                Text(Fmt.duration(session.minutes)).font(.headline).monospacedDigit()
                            }
                        }
                    }

                    Text(session.details)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    if let activity = model.matchedActivity(for: session) {
                        Card {
                            Label("Erledigt laut \(activity.appName)", systemImage: "checkmark.seal.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            ActivityLine(activity: activity)
                        }
                    }

                    if session.isTraining {
                        Button {
                            model.toggleDone(session)
                        } label: {
                            Label(model.completed.contains(session.id) ? "Als offen markieren" : "Als erledigt markieren",
                                  systemImage: model.completed.contains(session.id) ? "arrow.uturn.backward" : "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ActivityLine: View {
    let activity: ActivityRecord

    var body: some View {
        HStack(spacing: 12) {
            SportIcon(sport: activity.sport, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name).font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Text(Fmt.time(activity.start))
                    Text("·")
                    Text(Fmt.duration(activity.minutes))
                    if let km = activity.distanceKm {
                        Text("·")
                        Text(Fmt.km(km))
                    }
                    if let hr = activity.avgHeartRate {
                        Text("·")
                        Text("\(hr) bpm")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer()
            Text(activity.appName)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
        }
    }
}
