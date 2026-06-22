import Foundation

// The closed-loop "nudge": adjust tonight's tuning by at most one small step
// based on last night's outcome, so the schedule tracks the user's sleep
// without lurching. Conservative by design — night-to-night architecture is
// noisy, so we move slowly and never by more than 1 °F per parameter per night.

/// The three knobs that shape a schedule, plus the gradual-transition toggle.
public struct TuningParams: Equatable, Sendable, Codable {
    public var baseF: Int
    public var deepDropF: Int
    public var rampF: Int
    public var gradual: Bool

    public init(baseF: Int = 64, deepDropF: Int = 5, rampF: Int = 6, gradual: Bool = false) {
        self.baseF = baseF; self.deepDropF = deepDropF; self.rampF = rampF; self.gradual = gradual
    }
}

/// What actually happened last night (from HealthKit), used to grade the schedule.
public struct NightOutcome: Equatable, Sendable {
    public var deepMin: Double
    public var remMin: Double
    public var efficiencyPct: Double
    public var awakeMin: Double

    public init(deepMin: Double, remMin: Double, efficiencyPct: Double, awakeMin: Double) {
        self.deepMin = deepMin; self.remMin = remMin
        self.efficiencyPct = efficiencyPct; self.awakeMin = awakeMin
    }
}

public struct NudgeResult: Equatable, Sendable {
    public var params: TuningParams
    public var changed: Bool
    public var rationale: String
}

private func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { max(lo, min(hi, v)) }

/// Decide tonight's params from last night's outcome against the user's good-night
/// baseline. Comfort/efficiency is the first guard: a cold bed that fragments
/// sleep is worse than a slightly warm one, so we back off before chasing deep.
public func nudge(current: TuningParams, last: NightOutcome, baseline: SleepProfile) -> NudgeResult {
    let deepTarget = baseline.deep
    let lowEfficiency = last.efficiencyPct < 85
    let restless = last.awakeMin > max(45, baseline.awake * 1.3)

    // 1) Comfort guard — too much wake / low efficiency: ease the cold and warm
    //    the baseline by 1 °F.
    if lowEfficiency && restless && current.deepDropF > 0 {
        var p = current
        p.deepDropF = clamp(p.deepDropF - 1, 0, 15)
        p.baseF = clamp(p.baseF + 1, 55, 95)
        return NudgeResult(params: p, changed: true,
            rationale: "Efficiency was \(Int(last.efficiencyPct.rounded()))% with \(Int(last.awakeMin.rounded())) min awake — the bed may be running too cold. Easing the deep-sleep drop to \(p.deepDropF)°F and nudging the baseline up to \(p.baseF)°F.")
    }

    // 2) Deep is short while sleep was otherwise solid: chase more slow-wave by
    //    cooling the early-night window 1 °F harder.
    if !lowEfficiency && last.deepMin < deepTarget * 0.9 && current.deepDropF < 15 {
        var p = current
        p.deepDropF = clamp(p.deepDropF + 1, 0, 15)
        return NudgeResult(params: p, changed: true,
            rationale: "Deep sleep was \(Int(last.deepMin.rounded())) min vs your \(Int(deepTarget.rounded())) min baseline. Cooling the deep-sleep window a touch more (drop now \(p.deepDropF)°F) to chase slow-wave sleep.")
    }

    // 3) Deep is strong and efficiency is good — hold steady.
    return NudgeResult(params: current, changed: false,
        rationale: "Last night tracked your baseline (deep \(Int(last.deepMin.rounded())) min, efficiency \(Int(last.efficiencyPct.rounded()))%). Holding tonight's schedule steady.")
}
