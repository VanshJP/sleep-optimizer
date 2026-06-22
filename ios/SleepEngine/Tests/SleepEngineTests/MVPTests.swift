import XCTest
@testable import SleepEngine

// Covers the MVP-specific engine pieces: stage↔temp correlation, the nightly
// nudge controller, and the Sleep.me transcription mapping.

final class MVPTests: XCTestCase {

    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// A date at the given minute-of-day on a fixed reference day.
    private func date(minuteOfDay: Int) -> Date {
        var comp = DateComponents()
        comp.year = 2026; comp.month = 1; comp.day = 1
        comp.hour = minuteOfDay / 60; comp.minute = minuteOfDay % 60
        return utc.date(from: comp)!
    }

    /// 64°F baseline, cooling to 59°F across the deep window, easing to 62°F.
    private func schedule() -> [ScheduleSeg] {
        [
            ScheduleSeg(t: 0, temp: 64, phase: "Lights out", why: "", durMin: 0),
            ScheduleSeg(t: 60, temp: 59, phase: "Deep-sleep cooling", why: "", durMin: 0),
            ScheduleSeg(t: 240, temp: 62, phase: "Light / REM hold", why: "", durMin: 0),
        ]
    }

    // MARK: commandedTemp

    func testCommandedTempLookupAndWraparound() {
        let s = schedule()
        XCTAssertEqual(commandedTemp(atMinute: 0, schedule: s), 64)
        XCTAssertEqual(commandedTemp(atMinute: 120, schedule: s), 59)
        XCTAssertEqual(commandedTemp(atMinute: 300, schedule: s), 62)
        // Before the first event, the last setpoint carries over from "yesterday".
        XCTAssertEqual(commandedTemp(atMinute: 1430, schedule: s), 62)
    }

    // MARK: correlate

    func testCorrelateWeightsTempByStageMinutes() {
        let s = schedule()
        let stages = [
            StageSample(stage: .light, start: date(minuteOfDay: 0), end: date(minuteOfDay: 60)),
            StageSample(stage: .deep, start: date(minuteOfDay: 60), end: date(minuteOfDay: 180)),
            StageSample(stage: .rem, start: date(minuteOfDay: 240), end: date(minuteOfDay: 300)),
        ]
        let result = correlate(stages: stages, schedule: s, calendar: utc)
        let byStage = Dictionary(uniqueKeysWithValues: result.map { ($0.stage, $0) })
        XCTAssertEqual(byStage[.deep]?.minutes ?? 0, 120, accuracy: 0.001)
        // Deep happened entirely in the 59°F window.
        XCTAssertEqual(byStage[.deep]?.avgCommandedTempF ?? 0, 59, accuracy: 0.001)
        XCTAssertEqual(byStage[.light]?.avgCommandedTempF ?? 0, 64, accuracy: 0.001)
        XCTAssertEqual(byStage[.rem]?.avgCommandedTempF ?? 0, 62, accuracy: 0.001)
    }

    func testCorrelateSplitsBlockAcrossSetpoints() {
        let s = schedule()
        // A deep block straddling the 64→59 change at minute 60.
        let stages = [StageSample(stage: .deep, start: date(minuteOfDay: 0), end: date(minuteOfDay: 120))]
        let result = correlate(stages: stages, schedule: s, calendar: utc)
        let avg = result.first?.avgCommandedTempF ?? 0
        // 60 min @64 + 60 min @59 ⇒ ~61.5°F.
        XCTAssertEqual(avg, 61.5, accuracy: 0.6)
    }

    // MARK: nudge

    private func baseline() -> SleepProfile {
        SleepProfile(nRecent: 30, nGood: 20, onsetMin: 1380, wakeMin: 420,
                     deep: 90, rem: 110, light: 200, awake: 30,
                     asleep: 400, perf: 85, eff: 90)
    }

    func testNudgeComfortGuardWarmsWhenRestless() {
        let p = TuningParams(baseF: 64, deepDropF: 6, rampF: 6)
        let bad = NightOutcome(deepMin: 70, remMin: 90, efficiencyPct: 80, awakeMin: 60)
        let r = nudge(current: p, last: bad, baseline: baseline())
        XCTAssertTrue(r.changed)
        XCTAssertEqual(r.params.baseF, 65)
        XCTAssertEqual(r.params.deepDropF, 5)
    }

    func testNudgeChasesDeepWhenShort() {
        let p = TuningParams(baseF: 64, deepDropF: 5, rampF: 6)
        let shortDeep = NightOutcome(deepMin: 60, remMin: 110, efficiencyPct: 92, awakeMin: 20)
        let r = nudge(current: p, last: shortDeep, baseline: baseline())
        XCTAssertTrue(r.changed)
        XCTAssertEqual(r.params.deepDropF, 6)
        XCTAssertEqual(r.params.baseF, 64)
    }

    func testNudgeHoldsWhenOnTarget() {
        let p = TuningParams(baseF: 64, deepDropF: 5, rampF: 6)
        let good = NightOutcome(deepMin: 95, remMin: 115, efficiencyPct: 93, awakeMin: 15)
        let r = nudge(current: p, last: good, baseline: baseline())
        XCTAssertFalse(r.changed)
        XCTAssertEqual(r.params, p)
    }

    // MARK: sleepmeProgram / transcription

    func testSleepmeProgramMapsBedWakeAndWarmAwake() throws {
        let profile = try analyze(demoCSV())
        let cycles = buildCycles(profile)
        let segs = buildSchedule(profile, cycles, baseF: 64, rampF: 6, deepDropF: 6)
        let program = sleepmeProgram(from: segs, profile: profile, rampF: 6)
        XCTAssertTrue(program.warmAwake, "Positive rampF maps onto Warm Awake")
        XCTAssertEqual(program.bedMinute % 5, 0, "Times snap to 5-min increments")
        XCTAssertEqual(program.wakeMinute % 5, 0)
        for a in program.adjustments { XCTAssertEqual(a.minuteOfDay % 5, 0) }
        // Adjustments are strictly increasing in time and never repeat a temp.
        for i in 1..<max(1, program.adjustments.count) {
            XCTAssertNotEqual(program.adjustments[i].tempF, program.adjustments[i - 1].tempF)
        }
    }

    func testTranscriptionLinesRenderBedAndWake() {
        let program = SleepmeProgram(bedMinute: 1380, bedTempF: 64, wakeMinute: 420,
                                     wakeTempF: 70,
                                     adjustments: [SleepmeAdjustment(minuteOfDay: 60, tempF: 59, label: "Deep-sleep cooling")],
                                     warmAwake: true)
        let lines = transcriptionLines(program, unit: .fahrenheit)
        XCTAssertTrue(lines.first?.contains("Bed Time") ?? false)
        XCTAssertTrue(lines.contains { $0.contains("Deep-sleep cooling") })
        XCTAssertTrue(lines.contains { $0.contains("Wake Time") })
        XCTAssertTrue(lines.last?.contains("Warm Awake: ON") ?? false)
    }
}
