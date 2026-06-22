import Foundation

// Folds the engine's fine-grained schedule into exactly what the Sleep.me /
// Chilipad scheduler accepts: a Bed Time temp, a Wake Time temp, N "Add
// Adjustment" events, and the Warm Awake toggle. Times snap to 5-minute
// increments (the app's dial granularity), and the engine's pre-wake warm ramp
// is mapped onto Warm Awake instead of emitted as manual adjustments.

public struct SleepmeAdjustment: Equatable, Sendable, Identifiable, Codable {
    public var minuteOfDay: Int
    public var tempF: Int
    public var label: String
    public var id: String { "\(minuteOfDay)-\(tempF)" }
    public init(minuteOfDay: Int, tempF: Int, label: String) {
        self.minuteOfDay = minuteOfDay; self.tempF = tempF; self.label = label
    }
}

public struct SleepmeProgram: Equatable, Sendable, Codable {
    public var bedMinute: Int
    public var bedTempF: Int
    public var wakeMinute: Int
    public var wakeTempF: Int
    public var adjustments: [SleepmeAdjustment]
    public var warmAwake: Bool
}

func round5(_ minute: Int) -> Int {
    let r = (Int((Double(minute) / 5).rounded()) * 5) % 1440
    return (r + 1440) % 1440
}

private let preBedPhases: Set<String> = ["Pre-bed cool-down", "Lights out", "Off"]
private let wakeWarmPhases: Set<String> = ["Ease off cooling", "Wake warm-up", "Gradual wake warm-up"]

/// Convert a full schedule into a Sleep.me-shaped program.
public func sleepmeProgram(from segs: [ScheduleSeg], profile: SleepProfile, rampF: Int) -> SleepmeProgram {
    let bed = segs.first { $0.phase == "Lights out" } ?? segs.first { $0.temp != nil }!
    let bedTemp = bed.temp ?? profile_baseGuess(segs)
    let warmAwake = rampF > 0

    var adjustments: [SleepmeAdjustment] = []
    var lastTemp = bedTemp
    for s in segs {
        guard let temp = s.temp else { continue }
        if preBedPhases.contains(s.phase) { continue }
        if warmAwake && wakeWarmPhases.contains(s.phase) { continue }
        if temp == lastTemp { continue }
        let minute = round5(s.t)
        // Collapse onto the same 5-min slot: replace if it lands on the prior one.
        if let last = adjustments.last, last.minuteOfDay == minute {
            adjustments[adjustments.count - 1] = SleepmeAdjustment(minuteOfDay: minute, tempF: temp, label: s.phase)
        } else {
            adjustments.append(SleepmeAdjustment(minuteOfDay: minute, tempF: temp, label: s.phase))
        }
        lastTemp = temp
    }

    let wakeMinute = round5(Int(profile.wakeMin.rounded()))
    let wakeTemp = warmAwake ? bedTemp + rampF : lastTemp
    return SleepmeProgram(bedMinute: round5(bed.t), bedTempF: bedTemp,
                          wakeMinute: wakeMinute, wakeTempF: wakeTemp,
                          adjustments: adjustments, warmAwake: warmAwake)
}

private func profile_baseGuess(_ segs: [ScheduleSeg]) -> Int {
    segs.compactMap { $0.temp }.max() ?? 64
}

/// Human-readable transcription lines for the copy-as-text card.
public func transcriptionLines(_ program: SleepmeProgram, unit: TempUnit) -> [String] {
    var lines: [String] = []
    lines.append("Bed Time   \(fmtTime(program.bedMinute))   →  \(cvt(program.bedTempF, unit))")
    for a in program.adjustments {
        lines.append("Adjustment \(fmtTime(a.minuteOfDay))   →  \(cvt(a.tempF, unit))   (\(a.label))")
    }
    lines.append("Wake Time   \(fmtTime(program.wakeMinute))   →  \(cvt(program.wakeTempF, unit))")
    lines.append("Warm Awake: \(program.warmAwake ? "ON" : "OFF")")
    return lines
}
