import Foundation

// Schedule generation. Ported from lib/sleep.ts (`buildSchedule`). Evidence base
// and citations are preserved in the per-segment `why` text shown to the user.

/// Build a night-long temperature schedule from the profile and cycles.
/// `gradual` smooths every transition into ~2–3 °F steps ~30 min apart.
public func buildSchedule(_ p: SleepProfile, _ cycles: [Cycle], baseF: Int,
                          rampF: Int, deepDropF: Int, gradual: Bool = false) -> [ScheduleSeg] {
    let onset = p.onsetMin
    func at(_ m: Double) -> Int {
        let r = ((onset + m).truncatingRemainder(dividingBy: 1440) + 1440).truncatingRemainder(dividingBy: 1440)
        return Int(r.rounded())
    }
    let totalEnd = cycles[cycles.count - 1].end
    var segs: [ScheduleSeg] = []

    let remDropF = max(1, Int((Double(deepDropF) * 0.7).rounded()))
    let maxDeep = max(cycles.map { $0.deep }.max() ?? 1, 1)

    segs.append(ScheduleSeg(t: at(-30), temp: baseF, phase: "Pre-bed cool-down", why: "Get into an already-cool bed. Cooling the body helps core temperature fall, and that fall is the strongest physiological cue for sleep onset — distal cooling shortens how long it takes to drop off.", durMin: 0))
    segs.append(ScheduleSeg(t: at(0), temp: baseF, phase: "Lights out", why: "Your comfort baseline as you lie down. Every other setpoint is computed relative to this number.", durMin: 0))

    // Drive cooling from each of the user's cycles. A cycle's drop scales with how
    // much deep sleep it holds, floored at the REM-cool setting so the bed only
    // ever eases from coldest (deep-heavy early cycles) up to cool, never warming
    // back up mid-night.
    var prevTemp = baseF
    for (i, c) in cycles.enumerated() {
        let drop = max(remDropF, Int((Double(deepDropF) * (c.deep / maxDeep)).rounded()))
        let temp = baseF - drop
        if temp == prevTemp { continue }
        let startM = i == 0 ? 20.0 : c.start.rounded()
        let isColdest = drop >= deepDropF
        let nextM = i < cycles.count - 1 ? cycles[i + 1].start.rounded() : totalEnd - 35
        let available = max(10.0, nextM - startM)

        let phase: String, why: String
        if isColdest {
            phase = "Deep-sleep cooling"
            why = "Coldest setting of the night. Cycle \(i + 1) carries the most deep (slow-wave) sleep of your night — about \(Int(c.deep.rounded())) min — so the bed runs coldest right here. A 72-person randomized trial (Herberger 2024) found enhanced cooling in the deep-sleep window added slow-wave sleep and lowered resting heart rate."
        } else {
            let remLeft = Int(cycles[i...].reduce(0.0) { $0 + $1.rem }.rounded())
            phase = "Light / REM hold"
            why = "Your deep sleep is fading and the night shifts toward lighter stages and your REM-heavy final cycles (about \(remLeft) REM min still ahead). The bed eases up by \(deepDropF - drop)°F, then holds cool — your body barely thermoregulates in REM, and a 2025 sleep-lab trial (Kim 2025) that kept the bed cool through REM measured more REM and faster REM onset."
        }

        let tempDelta = abs(temp - prevTemp)
        if gradual && tempDelta >= 2 {
            let stepDur = max(10.0, min(30.0, (available / (Double(rampStepCount(Double(tempDelta))) + 0.5)).rounded(.down)))
            let midPhase = isColdest ? "Gradual deep-sleep cooling" : "Gradual REM transition"
            makeRamp(prevTemp, temp, startM, stepDur, at, midPhase, phase, why, temp < prevTemp)
                .forEach { segs.append($0) }
        } else {
            segs.append(ScheduleSeg(t: at(startM), temp: temp, phase: phase, why: why, durMin: 0))
        }
        prevTemp = temp
    }

    // Wake-up warm-up: climb from the overnight cool hold up toward (and past) the
    // comfort baseline so the alarm lands on an already-surfacing body.
    if rampF > 0 {
        let warmTarget = baseF + rampF
        let rise = Double(warmTarget - prevTemp)
        if gradual && rise >= 2 {
            let nUp = rampStepCount(rise)
            let lastMin = totalEnd - 10
            let maxSpan = max(Double(nUp - 1), lastMin - (totalEnd * 0.5).rounded())
            let stepDur = nUp > 1 ? max(8.0, min(30.0, (maxSpan / Double(nUp - 1)).rounded(.down))) : 30.0
            let warmStart = lastMin - Double(nUp - 1) * stepDur
            let finalWhy = "Reaches \(warmTarget)°F about 10 minutes before your usual wake time. Core temperature naturally climbs as you surface; arriving here gradually (the same ~+3°C pre-wake warming used in the 2025 trial) lets the alarm catch a body already on its way up instead of dragging you out of deep sleep."
            makeRamp(prevTemp, warmTarget, warmStart, stepDur, at, "Gradual wake warm-up", "Wake warm-up", finalWhy, false)
                .forEach { segs.append($0) }
        } else {
            segs.append(ScheduleSeg(t: at(totalEnd - 35), temp: baseF, phase: "Ease off cooling", why: "About 35 minutes before your usual wake time the cooling lifts back to your \(baseF)°F baseline — a first gentle step so the warm-up isn't one abrupt jump.", durMin: 0))
            segs.append(ScheduleSeg(t: at(totalEnd - 15), temp: baseF + rampF, phase: "Wake warm-up", why: "A short final warm to \(baseF + rampF)°F. Core temperature naturally climbs just before you wake; matching that rise (the same ~+3°C pre-wake move used in the 2025 trial) lets the alarm catch a body already surfacing instead of dragging you out of deep sleep.", durMin: 0))
        }
    }
    let offT = Int((p.wakeMin + 15).truncatingRemainder(dividingBy: 1440))
    segs.append(ScheduleSeg(t: offT, temp: nil, phase: "Off", why: "Shut off shortly after your typical wake time so you're not heating or cooling an empty bed.", durMin: 0))

    for i in 0..<(segs.count - 1) {
        segs[i].durMin = (((segs[i + 1].t - segs[i].t) % 1440) + 1440) % 1440
    }
    return segs
}
