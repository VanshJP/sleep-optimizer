import Foundation
import SleepEngine
#if canImport(HealthKit)
import HealthKit
#endif

// Thin HealthKit adapter: requests read access to sleepAnalysis and converts
// HKCategorySample → the engine's HealthKit-free StageInterval. All grouping and
// profiling lives in SleepEngine so it stays unit-testable on macOS.
@MainActor
final class HealthKitService: ObservableObject {
    enum AuthState: Equatable { case unknown, unavailable, authorized, denied }
    @Published var authState: AuthState = .unknown

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }
    #endif

    func requestAuthorization() async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { authState = .unavailable; return }
        do {
            try await store.requestAuthorization(toShare: [], read: [sleepType])
            authState = .authorized
        } catch {
            authState = .denied
        }
        #else
        authState = .unavailable
        #endif
    }

    /// Fetch the last `daysBack` days of sleep stage blocks as StageIntervals.
    func fetchIntervals(daysBack: Int = 30) async throws -> [StageInterval] {
        #if canImport(HealthKit)
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: sleepType, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        return samples.compactMap(Self.interval(from:))
        #else
        return []
        #endif
    }

    #if canImport(HealthKit)
    /// Map a HealthKit sleep sample to a stage interval. `inBed` becomes a
    /// stage-less marker used only for the efficiency denominator.
    static func interval(from s: HKCategorySample) -> StageInterval? {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: s.value) else { return nil }
        let stage: SleepStage?
        switch value {
        case .inBed: stage = nil
        case .awake: stage = .awake
        case .asleepDeep: stage = .deep
        case .asleepREM: stage = .rem
        case .asleepCore: stage = .light
        case .asleepUnspecified: stage = .light
        @unknown default: stage = .light
        }
        return StageInterval(stage: stage, start: s.startDate, end: s.endDate)
    }
    #endif
}
