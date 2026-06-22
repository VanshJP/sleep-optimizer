import Foundation

// Maps last night's actual sleep stages onto the temperatures that were
// *commanded* during those windows — the core "what temp was I at during deep
// sleep?" question the MVP answers.

/// A measured stage block from HealthKit (or a manual entry).
public struct StageSample: Equatable, Sendable, Identifiable, Codable {
    public var stage: SleepStage
    public var start: Date
    public var end: Date
    public var id: String { "\(stage.rawValue)-\(start.timeIntervalSince1970)" }

    public init(stage: SleepStage, start: Date, end: Date) {
        self.stage = stage; self.start = start; self.end = end
    }
    public var minutes: Double { max(0, end.timeIntervalSince(start) / 60) }
}

/// Per-stage rollup: how long the stage lasted and the minutes-weighted average
/// commanded bed temperature while it was happening.
public struct SleepCorrelation: Equatable, Sendable, Identifiable, Codable {
    public var stage: SleepStage
    public var minutes: Double
    public var avgCommandedTempF: Double?
    public var id: String { stage.rawValue }

    public init(stage: SleepStage, minutes: Double, avgCommandedTempF: Double?) {
        self.stage = stage; self.minutes = minutes; self.avgCommandedTempF = avgCommandedTempF
    }
}

/// The temperature in effect at a given minute-of-day under a schedule, honoring
/// midnight wraparound (the last setpoint of the night carries into the small
/// hours until the first morning event).
public func commandedTemp(atMinute minute: Int, schedule: [ScheduleSeg]) -> Int? {
    guard !schedule.isEmpty else { return nil }
    let sorted = schedule.sorted { $0.t < $1.t }
    var active = sorted[sorted.count - 1]
    for s in sorted {
        if s.t <= minute { active = s } else { break }
    }
    return active.temp
}

func minuteOfDayLocal(_ date: Date, calendar: Calendar) -> Int {
    let c = calendar.dateComponents([.hour, .minute], from: date)
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}

/// Correlate stage samples with the commanded schedule. Integrates each sample
/// minute-by-minute so blocks that straddle a setpoint change are split
/// proportionally. `calendar` defaults to the user's current timezone.
public func correlate(stages: [StageSample], schedule: [ScheduleSeg],
                      calendar: Calendar = .current) -> [SleepCorrelation] {
    var minutesByStage: [SleepStage: Double] = [:]
    var tempMinutesByStage: [SleepStage: Double] = [:]
    var tempWeightByStage: [SleepStage: Double] = [:]

    for sample in stages {
        let total = Int(sample.minutes.rounded())
        guard total > 0 else { continue }
        let startMin = minuteOfDayLocal(sample.start, calendar: calendar)
        minutesByStage[sample.stage, default: 0] += sample.minutes
        for k in 0..<total {
            let mod = (startMin + k) % 1440
            if let t = commandedTemp(atMinute: mod, schedule: schedule) {
                tempMinutesByStage[sample.stage, default: 0] += Double(t)
                tempWeightByStage[sample.stage, default: 0] += 1
            }
        }
    }

    return SleepStage.allCases.compactMap { stage in
        guard let mins = minutesByStage[stage], mins > 0 else { return nil }
        let weight = tempWeightByStage[stage] ?? 0
        let avg = weight > 0 ? (tempMinutesByStage[stage] ?? 0) / weight : nil
        return SleepCorrelation(stage: stage, minutes: mins, avgCommandedTempF: avg)
    }
}
