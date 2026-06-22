import Foundation
import SwiftUI
import SleepEngine

// Drives the Morning Loop: pull HealthKit → build profile/schedule → correlate
// last night's stages with the commanded temps → nudge tonight's params →
// persist a versioned "active schedule" and per-night logs. Schedules only get
// promoted to a new version (and notified) on meaningful drift — see driftReason.
// All on-device; nothing leaves HealthKit/local storage.
@MainActor
final class MorningLoopViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    @Published var state: LoadState = .idle
    @Published var params = TuningParams() { didSet { persistParams(); recompute() } }
    @Published var unit: TempUnit = .fahrenheit

    @Published private(set) var profile: SleepProfile?
    @Published private(set) var schedule: [ScheduleSeg] = []
    @Published private(set) var lastNightStages: [StageSample] = []
    @Published private(set) var correlations: [SleepCorrelation] = []
    @Published private(set) var program: SleepmeProgram?
    @Published private(set) var nudgeRationale: String = ""
    /// Set when a refresh promoted a new schedule version (meaningful drift),
    /// so the UI can show a "your schedule changed" banner.
    @Published var updateNotice: String?
    /// True once an active schedule version exists in the store.
    @Published private(set) var hasActiveSchedule: Bool = false

    private let health: HealthKitService
    private let store: SleepStore
    private let notifications: NotificationService
    private let paramsKey = "tuningParams.v1"

    init(store: SleepStore, health: HealthKitService? = nil, notifications: NotificationService? = nil) {
        self.store = store
        self.health = health ?? HealthKitService()
        self.notifications = notifications ?? NotificationService()
        // Seed params from (in priority) the active version, the one-time
        // UserDefaults migration, or the legacy UserDefaults slot.
        if let active = store.activeScheduleVersion() {
            params = active.params
            hasActiveSchedule = true
        } else if let migrated = store.migrateFromUserDefaultsIfNeeded() {
            params = migrated
        } else if let data = UserDefaults.standard.data(forKey: paramsKey),
                  let p = try? JSONDecoder().decode(TuningParams.self, from: data) {
            params = p
        }
    }

    // MARK: - Onboarding

    /// First-run build: take the baseline the user picked, aggregate their last
    /// ~30 nights (bad nights are dropped inside buildProfile), and save the
    /// first active schedule version. Falls back to sample data if HealthKit has
    /// nothing to read yet, so onboarding always finishes with a schedule.
    func runInitialOnboarding(baseF: Int) async {
        params.baseF = baseF
        state = .loading
        await notifications.requestAuthorization()
        await health.requestAuthorization()
        if health.authState == .authorized {
            do {
                let nights = groupNights(try await health.fetchIntervals(daysBack: 30))
                if !nights.isEmpty {
                    try buildInitialSchedule(from: nights,
                        reason: "Built from your last \(nights.count) nights of sleep")
                    state = .loaded
                    return
                }
            } catch { /* fall through to sample seed below */ }
        }
        seedFromSample(reason: "Sample schedule — sync Apple Health to personalize")
        state = .loaded
    }

    private func buildInitialSchedule(from nights: [NightStages], reason: String) throws {
        let p = try buildProfile(nights.map { $0.record })
        profile = p
        lastNightStages = nights.last?.stages ?? []
        let segs = makeSchedule(p)
        let version = store.promote(schedule: segs, profile: p, params: params, reason: reason)
        hasActiveSchedule = true
        persistNightLogs(nights, against: version)
        recompute()
    }

    // MARK: - Daily refresh

    /// One-tap morning refresh: authorize if needed, fetch, log last night against
    /// the running schedule, then promote a new version only on meaningful drift.
    func refresh() async {
        state = .loading
        updateNotice = nil
        await health.requestAuthorization()
        guard health.authState == .authorized else {
            state = .failed(authMessage(health.authState)); return
        }
        do {
            let nights = groupNights(try await health.fetchIntervals(daysBack: 30))
            guard !nights.isEmpty else {
                state = .failed("No sleep nights found in HealthKit yet. Wear your watch to bed and try tomorrow.")
                return
            }
            let p = try buildProfile(nights.map { $0.record })
            profile = p
            lastNightStages = nights.last?.stages ?? []

            // Nudge tonight's params from last night's outcome.
            applyNudge(using: nights.last?.record, baseline: p)

            // The version that ran last night (capture before any promotion now).
            let priorActive = store.activeScheduleVersion()
            persistNightLogs(nights, against: priorActive)

            // Candidate schedule for tonight (uses post-nudge params).
            let candidate = makeSchedule(p)
            if let prior = priorActive {
                if let reason = driftReason(candidateProfile: p, candidateParams: params, against: prior) {
                    store.promote(schedule: candidate, profile: p, params: params, reason: reason)
                    updateNotice = reason
                    notifications.notifyScheduleUpdated(reason: reason)
                }
            } else {
                // No active version yet (migrated user) — establish one quietly.
                store.promote(schedule: candidate, profile: p, params: params, reason: "Initial schedule")
            }
            hasActiveSchedule = true
            recompute()
            state = .loaded
        } catch {
            state = .failed((error as? SleepEngineError).map(describe) ?? error.localizedDescription)
        }
    }

    /// Called from the transcription card's Copy button: the user is applying this
    /// schedule to their bed, so make it the active version (no notification — they
    /// did it themselves). Skips if it already matches the active version.
    func saveCurrentSchedule() {
        guard let p = profile, !schedule.isEmpty else { return }
        if let active = store.activeScheduleVersion(), active.schedule == schedule { return }
        store.promote(schedule: schedule, profile: p, params: params, reason: "You applied this schedule")
        hasActiveSchedule = true
        recompute()
    }

    // MARK: - Sample data

    /// Load synthetic data so the UI is explorable without a watch. Persists the
    /// sample nights + a sample active version so History works too.
    func loadSample() {
        seedFromSample(reason: "Sample schedule")
        state = .loaded
    }

    private func seedFromSample(reason: String) {
        guard let p = try? analyze(demoCSV()) else { return }
        profile = p
        let sampleAll = makeSampleNights()
        lastNightStages = sampleAll.last?.stages ?? sampleStages(for: p)
        let segs = makeSchedule(p)
        let version = store.promote(schedule: segs, profile: p, params: params, reason: reason)
        hasActiveSchedule = true
        persistNightLogs(sampleAll, against: version)
        recompute()
    }

    // MARK: - Internals

    private func makeSchedule(_ p: SleepProfile) -> [ScheduleSeg] {
        buildSchedule(p, buildCycles(p), baseF: params.baseF, rampF: params.rampF,
                      deepDropF: params.deepDropF, gradual: params.gradual)
    }

    /// Persist each night against the schedule that was actually in effect, storing
    /// the per-stage temperature correlation so History can show how it lined up.
    private func persistNightLogs(_ nights: [NightStages], against version: ScheduleVersion?) {
        let refSchedule = version?.schedule ?? (profile.map(makeSchedule) ?? [])
        for night in nights {
            let cors = correlate(stages: night.stages, schedule: refSchedule)
            store.upsertNightLog(record: night.record, stages: night.stages,
                                 correlations: cors, scheduleVersionID: version?.id)
        }
    }

    private func applyNudge(using record: NightRecord?, baseline: SleepProfile) {
        guard let record else { return }
        let outcome = NightOutcome(deepMin: record.deep, remMin: record.rem,
                                   efficiencyPct: record.eff, awakeMin: record.awake)
        let result = nudge(current: params, last: outcome, baseline: baseline)
        nudgeRationale = result.rationale
        if result.changed { params = result.params } // persists + recomputes via didSet
    }

    private func recompute() {
        guard let p = profile else { return }
        let segs = makeSchedule(p)
        schedule = segs
        // Correlate last night against the active (running) schedule when present.
        let refSchedule = store.activeScheduleVersion()?.schedule ?? segs
        correlations = correlate(stages: lastNightStages, schedule: refSchedule)
        program = sleepmeProgram(from: segs, profile: p, rampF: params.rampF)
    }

    /// Difference in minutes between two minutes-of-day, honoring midnight wrap.
    private func circularMinuteDelta(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 1440)
        return min(d, 1440 - d)
    }

    /// Decide whether the candidate differs from the active version enough to
    /// warrant a new version + notification: onset/wake moved ≥ 30 min, or a temp
    /// setpoint moved ≥ 2 °F. Returns a human summary, or nil to hold steady.
    private func driftReason(candidateProfile: SleepProfile, candidateParams: TuningParams,
                             against prior: ScheduleVersion) -> String? {
        guard let priorProfile = prior.profile else { return nil }
        let priorParams = prior.params
        var reasons: [String] = []

        if circularMinuteDelta(candidateProfile.onsetMin, priorProfile.onsetMin) >= 30 {
            reasons.append("bedtime now \(fmtTime(Int(candidateProfile.onsetMin.rounded())))")
        }
        if circularMinuteDelta(candidateProfile.wakeMin, priorProfile.wakeMin) >= 30 {
            reasons.append("wake now \(fmtTime(Int(candidateProfile.wakeMin.rounded())))")
        }
        if abs(candidateParams.baseF - priorParams.baseF) >= 2 {
            reasons.append("comfort baseline \(candidateParams.baseF)°F")
        }
        if abs(candidateParams.deepDropF - priorParams.deepDropF) >= 2 {
            reasons.append("deep-sleep cooling −\(candidateParams.deepDropF)°F")
        }
        if abs(candidateParams.rampF - priorParams.rampF) >= 2 {
            reasons.append("wake warm-up +\(candidateParams.rampF)°F")
        }
        guard !reasons.isEmpty else { return nil }
        return "Your schedule updated — " + reasons.joined(separator: ", ") + "."
    }

    private func persistParams() {
        if let data = try? JSONEncoder().encode(params) {
            UserDefaults.standard.set(data, forKey: paramsKey)
        }
    }

    private func authMessage(_ s: HealthKitService.AuthState) -> String {
        switch s {
        case .unavailable: return "HealthKit isn't available on this device."
        case .denied: return "Sleep access was denied. Enable it in Settings → Health → Data Access."
        default: return "Couldn't get HealthKit access."
        }
    }

    private func describe(_ e: SleepEngineError) -> String {
        switch e { case .message(let m): return m }
    }

    // MARK: - Sample helpers

    /// Generate 30 nights of plausible sample data anchored to real calendar dates,
    /// so the History calendar is populated when the user taps "Try sample data".
    private func makeSampleNights() -> [NightStages] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        return (1...30).compactMap { ago -> NightStages? in
            guard let morning = cal.date(byAdding: .day, value: -ago, to: todayStart) else { return nil }
            let wake  = morning.addingTimeInterval(7 * 3600)        // 7:00 AM
            let seed  = Double(ago * 17 + 3)
            let deep  = 75 + seed.truncatingRemainder(dividingBy: 45)
            let rem   = 95 + (seed * 1.3).truncatingRemainder(dividingBy: 50)
            let light = 175 + (seed * 0.7).truncatingRemainder(dividingBy: 65)
            let asleep = deep + rem + light
            let onset = wake.addingTimeInterval(-(asleep + 25) * 60)
            let eff   = 83 + (seed * 0.3).truncatingRemainder(dividingBy: 14)
            let record = NightRecord(onset: onset, wake: wake, perf: eff, eff: eff,
                                     light: light, deep: deep, rem: rem,
                                     awake: 25, asleep: asleep, nap: false)
            var stages: [StageSample] = []
            var t = onset
            for (stage, dur): (SleepStage, Double) in [(.deep, deep), (.light, light), (.rem, rem)] {
                stages.append(StageSample(stage: stage, start: t, end: t.addingTimeInterval(dur * 60)))
                t = t.addingTimeInterval(dur * 60)
            }
            return NightStages(stages: stages, record: record)
        }.reversed()
    }

    private func sampleStages(for p: SleepProfile) -> [StageSample] {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        func at(_ minute: Double) -> Date { base.addingTimeInterval((p.onsetMin + minute) * 60) }
        var out: [StageSample] = []
        for c in buildCycles(p) {
            var t = c.start
            for (stage, dur) in [(SleepStage.deep, c.deep), (.light, c.light), (.rem, c.rem)] where dur > 1 {
                out.append(StageSample(stage: stage, start: at(t), end: at(t + dur)))
                t += dur
            }
        }
        return out
    }
}
