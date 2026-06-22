import Foundation

// Cycle distribution and the gradual-ramp builder. Ported from lib/sleep.ts
// (`buildCycles`, `RAMP_STEP_F`, `rampStepCount`, `makeRamp`).

/// Distribute stage totals across ~90-min cycles: slow-wave sleep decays cycle
/// over cycle, REM grows toward morning.
public func buildCycles(_ p: SleepProfile) -> [Cycle] {
    let n = max(3, min(6, Int((p.asleep / 90).rounded())))
    var dw: [Double] = [], rw: [Double] = []
    for i in 0..<n { dw.append(pow(0.55, Double(i))); rw.append(pow(1.55, Double(i))) }
    let ds = dw.reduce(0, +), rs = rw.reduce(0, +)
    let cyc = p.asleep / Double(n)
    var out: [Cycle] = []
    var t = 0.0
    for i in 0..<n {
        let d = p.deep * dw[i] / ds, r = p.rem * rw[i] / rs
        out.append(Cycle(start: t, end: t + cyc, deep: d, rem: r, light: max(0, cyc - d - r)))
        t += cyc
    }
    return out
}

/// Target step magnitude for a gradual ramp (°F).
let RAMP_STEP_F = 2.5
/// Number of ~2–3 °F steps needed to cover a change of `delta` °F.
func rampStepCount(_ delta: Double) -> Int { max(1, Int((abs(delta) / RAMP_STEP_F).rounded())) }

/// Build intermediate setpoints that ramp gradually from one temperature to
/// another in ~2–3 °F steps spaced roughly half an hour apart.
func makeRamp(_ fromTemp: Int, _ toTemp: Int, _ startMin: Double, _ stepDur: Double,
              _ at: (Double) -> Int, _ midPhase: String, _ finalPhase: String,
              _ finalWhy: String, _ cooling: Bool) -> [ScheduleSeg] {
    let delta = Double(toTemp - fromTemp)
    let nSteps = rampStepCount(delta)
    if nSteps <= 1 {
        return [ScheduleSeg(t: at(startMin), temp: toTemp, phase: finalPhase, why: finalWhy, durMin: 0)]
    }
    var result: [ScheduleSeg] = []
    var prev = Double(fromTemp)
    for i in 1...nSteps {
        let offsetMin = startMin + Double(i - 1) * stepDur
        let temp = Int((Double(fromTemp) + (Double(i) / Double(nSteps)) * delta).rounded())
        let isLast = i == nSteps
        let mag = Int(abs(Double(temp) - prev))
        let dir = cooling ? "down" : "up"
        let fall = cooling ? "fall" : "rise"
        let vaso = cooling ? "vasodilation" : "vasoconstriction"
        let frag = cooling ? "the descent into slow-wave sleep" : "lighter morning sleep"
        let why = isLast ? finalWhy :
            "Gradual \(cooling ? "cooling" : "warming") — step \(i) of \(nSteps): " +
            "\(dir) to \(temp)°F (a \(mag)°F move), holding ~\(Int(stepDur.rounded())) min " +
            "before the next nudge. Shifting the bed in small 2–3°F steps about half an hour apart " +
            "tracks the natural circadian \(fall) of core body temperature — driven " +
            "by distal \(vaso) (Kräuchi 2000) — instead of forcing " +
            "it with one large jump, and stays gentle enough to avoid the \"thermal shock\" that can " +
            "trigger micro-arousals and fragment \(frag)."
        result.append(ScheduleSeg(t: at(offsetMin), temp: temp,
                                  phase: isLast ? finalPhase : midPhase, why: why,
                                  durMin: 0, isRampStep: !isLast))
        prev = Double(temp)
    }
    return result
}
