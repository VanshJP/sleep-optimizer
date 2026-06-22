import Foundation

// Pure (HealthKit-free) grouping of stage intervals into nights, so the
// ingestion logic is unit-testable on macOS. The app's HealthKitService only
// converts HKCategorySample → StageInterval and hands the array here.

/// One contiguous HealthKit block. `stage == nil` marks an "in bed" interval
/// (time in bed without a finer stage), used only to compute efficiency.
public struct StageInterval: Equatable, Sendable {
    public var stage: SleepStage?
    public var start: Date
    public var end: Date
    public init(stage: SleepStage?, start: Date, end: Date) {
        self.stage = stage; self.start = start; self.end = end
    }
    public var minutes: Double { max(0, end.timeIntervalSince(start) / 60) }
}

/// A grouped night: the per-stage samples (for correlation) plus the aggregated
/// NightRecord (for the profile builder). HealthKit has no "performance" score,
/// so `perf` is set equal to efficiency as a reasonable proxy.
public struct NightStages: Equatable, Sendable {
    public var stages: [StageSample]
    public var record: NightRecord
    public init(stages: [StageSample], record: NightRecord) {
        self.stages = stages; self.record = record
    }
}

/// Cluster intervals into nights, splitting whenever the gap between one block's
/// end and the next block's start exceeds `gapThresholdMin` (default 3 h — long
/// enough to keep a single night together, short enough to separate naps).
public func groupNights(_ intervals: [StageInterval], gapThresholdMin: Double = 180,
                        calendar: Calendar = .current) -> [NightStages] {
    let sorted = intervals.sorted { $0.start < $1.start }
    guard !sorted.isEmpty else { return [] }

    var clusters: [[StageInterval]] = []
    var current: [StageInterval] = [sorted[0]]
    var clusterEnd = sorted[0].end
    for iv in sorted.dropFirst() {
        if iv.start.timeIntervalSince(clusterEnd) / 60 > gapThresholdMin {
            clusters.append(current); current = []
        }
        current.append(iv)
        clusterEnd = max(clusterEnd, iv.end)
    }
    if !current.isEmpty { clusters.append(current) }

    return clusters.compactMap { night(from: $0) }
}

private func night(from cluster: [StageInterval]) -> NightStages? {
    let stageBlocks = cluster.filter { $0.stage != nil }
    guard !stageBlocks.isEmpty else { return nil }

    var mins: [SleepStage: Double] = [:]
    var samples: [StageSample] = []
    for b in stageBlocks {
        guard let st = b.stage else { continue }
        mins[st, default: 0] += b.minutes
        samples.append(StageSample(stage: st, start: b.start, end: b.end))
    }

    let deep = mins[.deep] ?? 0, rem = mins[.rem] ?? 0
    let light = mins[.light] ?? 0, awake = mins[.awake] ?? 0
    let asleep = deep + rem + light

    let asleepBlocks = stageBlocks.filter { $0.stage != .awake }
    let onset = asleepBlocks.map { $0.start }.min() ?? cluster[0].start
    let wake = asleepBlocks.map { $0.end }.max() ?? cluster[cluster.count - 1].end

    // Prefer explicit in-bed coverage for the denominator; fall back to the span.
    let inBedMin = cluster.filter { $0.stage == nil }.reduce(0) { $0 + $1.minutes }
    let denom = max(inBedMin, asleep + awake)
    let eff = denom > 0 ? min(100, asleep / denom * 100) : 0

    let record = NightRecord(onset: onset, wake: wake, perf: eff, eff: eff,
                             light: light, deep: deep, rem: rem, awake: awake,
                             asleep: asleep, nap: false)
    return NightStages(stages: samples.sorted { $0.start < $1.start }, record: record)
}

/// Convenience: group, then build a profile from the resulting nights. Mirrors
/// the CSV path's `analyze` so both feed `buildSchedule` identically.
public func profile(fromIntervals intervals: [StageInterval],
                    gapThresholdMin: Double = 180,
                    calendar: Calendar = .current) throws -> SleepProfile {
    let nights = groupNights(intervals, gapThresholdMin: gapThresholdMin, calendar: calendar)
    if nights.isEmpty { throw SleepEngineError.message("No nights found in HealthKit data.") }
    return try buildProfile(nights.map { $0.record }, calendar: calendar)
}
