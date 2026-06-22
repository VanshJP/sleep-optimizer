import Foundation
import SwiftData
import SleepEngine

// Thin façade over the SwiftData ModelContext. Owns the "active schedule +
// version history" and the per-night logs. Kept @MainActor so it shares the
// main ModelContext with SwiftUI; the dataset is tiny (~30 nights) so we fetch
// and filter in Swift rather than leaning on complex predicates.
@MainActor
final class SleepStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Wake-day key, matching HistoryView's calendar key format.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    // MARK: - Schedule versions

    func activeScheduleVersion() -> ScheduleVersion? {
        let all = (try? context.fetch(FetchDescriptor<ScheduleVersion>())) ?? []
        return all.filter { $0.isActive }.max { $0.createdAt < $1.createdAt }
    }

    func allScheduleVersions() -> [ScheduleVersion] {
        let all = (try? context.fetch(FetchDescriptor<ScheduleVersion>())) ?? []
        return all.sorted { $0.createdAt > $1.createdAt }
    }

    /// Insert a new active version and deactivate any previously-active ones.
    @discardableResult
    func promote(schedule: [ScheduleSeg], profile: SleepProfile, params: TuningParams,
                 reason: String?) -> ScheduleVersion {
        for v in allScheduleVersions() where v.isActive { v.isActive = false }
        let version = ScheduleVersion(isActive: true, schedule: schedule, profile: profile,
                                      params: params, promotionReason: reason)
        context.insert(version)
        try? context.save()
        return version
    }

    // MARK: - Night logs

    func allNightLogs() -> [NightLog] {
        let all = (try? context.fetch(FetchDescriptor<NightLog>())) ?? []
        return all.sorted { $0.wakeDate < $1.wakeDate }
    }

    func nightLog(forDayKey key: String) -> NightLog? {
        let descriptor = FetchDescriptor<NightLog>(predicate: #Predicate { $0.dayKey == key })
        return (try? context.fetch(descriptor))?.first
    }

    /// Insert-or-update a night by its wake-day key.
    func upsertNightLog(record: NightRecord, stages: [StageSample],
                        correlations: [SleepCorrelation], scheduleVersionID: UUID?) {
        let key = Self.dayKey(for: record.wake)
        if let existing = nightLog(forDayKey: key) {
            context.delete(existing)
        }
        context.insert(NightLog(dayKey: key, record: record, stages: stages,
                                correlations: correlations, scheduleVersionID: scheduleVersionID))
        try? context.save()
    }

    // MARK: - Migration from the pre-SwiftData UserDefaults slots

    /// One-time bridge from the old `tuningParams.v1` / `savedSchedule.v1` keys.
    /// We keep reading (not deleting) those keys for one release so a downgrade
    /// doesn't lose anything. Returns the migrated params if any were found.
    func migrateFromUserDefaultsIfNeeded() -> TuningParams? {
        let migratedFlag = "swiftDataMigrated.v1"
        guard !UserDefaults.standard.bool(forKey: migratedFlag) else { return nil }
        defer { UserDefaults.standard.set(true, forKey: migratedFlag) }

        var params: TuningParams?
        if let data = UserDefaults.standard.data(forKey: "tuningParams.v1") {
            params = SleepCodables.decode(TuningParams.self, from: data)
        }
        // The old saved schedule had no stored profile, so we can't form a full
        // ScheduleVersion here; the first onboarding/refresh creates version 1.
        // We only carry the tuning params forward.
        return params
    }
}
