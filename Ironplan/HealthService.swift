import Foundation
import HealthKit

/// Apple Health: liest Workouts (auch die von Suunto, Garmin, Apple Watch …),
/// den Schlaf der letzten Nacht und schreibt getrunkenes Wasser.
final class HealthService {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { types.insert(hr) }
        return types
    }

    private var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = []
        if let water = HKObjectType.quantityType(forIdentifier: .dietaryWater) { types.insert(water) }
        return types
    }

    /// Fragt nach Zugriff. Gibt eine Fehlermeldung zurück, falls es nicht geklappt hat.
    func requestAuthorization() async -> String? {
        guard isAvailable else { return "Apple Health ist auf diesem Gerät nicht verfügbar." }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            return nil
        } catch {
            return "Apple Health konnte nicht verbunden werden: \(error.localizedDescription)"
        }
    }

    func workouts(since start: Date) async -> [ActivityRecord] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKSample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                      limit: 300, sortDescriptors: [sort]) { _, results, _ in
                continuation.resume(returning: results ?? [])
            }
            store.execute(query)
        }

        return samples.compactMap { $0 as? HKWorkout }.map { w in
            let km = w.totalDistance?.doubleValue(for: .meterUnit(with: .kilo))
            return ActivityRecord(
                id: "hk-\(w.uuid.uuidString)",
                source: .health,
                appName: w.sourceRevision.source.name,
                sport: Self.sport(for: w.workoutActivityType),
                name: Self.name(for: w.workoutActivityType),
                start: w.startDate,
                minutes: Int((w.duration / 60).rounded()),
                distanceKm: (km ?? 0) > 0 ? km : nil,
                avgHeartRate: nil)
        }
    }

    /// Geschlafene Minuten in der Nacht vor `day` (18 Uhr Vortag bis 14 Uhr).
    func sleepMinutes(endingOn day: Date, cal: Calendar) async -> Int? {
        guard isAvailable, let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let dayStart = cal.startOfDay(for: day)
        guard let from = cal.date(byAdding: .hour, value: -6, to: dayStart),
              let to = cal.date(byAdding: .hour, value: 14, to: dayStart) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])

        let samples: [HKSample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, results, _ in
                continuation.resume(returning: results ?? [])
            }
            store.execute(query)
        }

        let notAsleep: Set<Int> = [HKCategoryValueSleepAnalysis.inBed.rawValue,
                                   HKCategoryValueSleepAnalysis.awake.rawValue]
        let ranges = samples
            .compactMap { $0 as? HKCategorySample }
            .filter { !notAsleep.contains($0.value) }
            .map { ($0.startDate, $0.endDate) }
            .sorted { $0.0 < $1.0 }
        guard !ranges.isEmpty else { return nil }

        // Überlappungen (z. B. Uhr + iPhone) zusammenführen
        var total: TimeInterval = 0
        var current = ranges[0]
        for r in ranges.dropFirst() {
            if r.0 <= current.1 {
                current.1 = max(current.1, r.1)
            } else {
                total += current.1.timeIntervalSince(current.0)
                current = r
            }
        }
        total += current.1.timeIntervalSince(current.0)
        return Int(total / 60)
    }

    func logWater(ml: Int) {
        guard isAvailable, ml > 0, let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else { return }
        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: Double(ml))
        let now = Date()
        let sample = HKQuantitySample(type: type, quantity: quantity, start: now, end: now)
        store.save(sample) { _, _ in }
    }

    // MARK: Zuordnung

    static func sport(for type: HKWorkoutActivityType) -> Sport {
        switch type {
        case .swimming: return .swim
        case .cycling, .handCycling: return .bike
        case .running: return .run
        case .swimBikeRun: return .brick
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining, .crossTraining:
            return .strength
        default: return .other
        }
    }

    static func name(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .swimming: return "Schwimmen"
        case .cycling: return "Radfahren"
        case .running: return "Laufen"
        case .swimBikeRun: return "Triathlon"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Krafttraining"
        case .coreTraining: return "Core-Training"
        case .walking: return "Gehen"
        case .hiking: return "Wandern"
        case .yoga: return "Yoga"
        default: return "Workout"
        }
    }
}
