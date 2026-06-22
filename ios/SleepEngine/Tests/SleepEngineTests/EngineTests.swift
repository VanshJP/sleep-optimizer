import XCTest
@testable import SleepEngine

// Validates the Swift port against the behaviour of lib/sleep.ts. Uses the
// synthetic demoCSV() so the analysis path runs end-to-end without fixtures.

final class EngineTests: XCTestCase {

    private func sampleProfile() throws -> SleepProfile {
        try analyze(demoCSV())
    }

    // MARK: analyze / buildProfile

    func testAnalyzeProducesUsableProfile() throws {
        let p = try sampleProfile()
        XCTAssertGreaterThanOrEqual(p.nGood, 3)
        XCTAssertGreaterThan(p.asleep, 120)
        XCTAssertGreaterThan(p.deep, 0)
        XCTAssertGreaterThan(p.rem, 0)
        XCTAssertTrue((0..<1440).contains(Int(p.onsetMin)))
        XCTAssertTrue((0..<1440).contains(Int(p.wakeMin)))
    }

    func testAnalyzeRejectsGarbage() {
        XCTAssertThrowsError(try analyze("not,a,whoop,file\n1,2,3,4"))
    }

    func testAnalyzeRejectsEmpty() {
        XCTAssertThrowsError(try analyze(""))
    }

    // MARK: buildCycles

    func testBuildCyclesCountAndConservation() throws {
        let p = try sampleProfile()
        let cycles = buildCycles(p)
        XCTAssertTrue((3...6).contains(cycles.count))
        // Stage minutes are redistributed but totals are preserved.
        let deepSum = cycles.reduce(0) { $0 + $1.deep }
        let remSum = cycles.reduce(0) { $0 + $1.rem }
        XCTAssertEqual(deepSum, p.deep, accuracy: 0.5)
        XCTAssertEqual(remSum, p.rem, accuracy: 0.5)
        // Deep decays cycle over cycle; REM grows toward morning.
        XCTAssertGreaterThan(cycles.first!.deep, cycles.last!.deep)
        XCTAssertLessThan(cycles.first!.rem, cycles.last!.rem)
        // Cycles tile contiguously from 0.
        XCTAssertEqual(cycles.first!.start, 0, accuracy: 0.001)
        for i in 1..<cycles.count {
            XCTAssertEqual(cycles[i].start, cycles[i - 1].end, accuracy: 0.001)
        }
    }

    // MARK: buildSchedule

    func testBuildScheduleShape() throws {
        let p = try sampleProfile()
        let cycles = buildCycles(p)
        let segs = buildSchedule(p, cycles, baseF: 64, rampF: 6, deepDropF: 5)
        XCTAssertFalse(segs.isEmpty)
        XCTAssertEqual(segs.first?.phase, "Pre-bed cool-down")
        XCTAssertEqual(segs.last?.phase, "Off")
        XCTAssertNil(segs.last?.temp, "Final segment turns the dock off")
        // All non-off setpoints sit at or below the comfort baseline overnight,
        // and never exceed base + ramp at the warm-up.
        for s in segs.dropLast() {
            if let t = s.temp { XCTAssertLessThanOrEqual(t, 64 + 6) }
        }
        // Coldest setpoint reflects the deep-sleep drop.
        let coldest = segs.compactMap { $0.temp }.min()
        XCTAssertEqual(coldest, 64 - 5)
        // Durations are non-negative and wrap correctly.
        for s in segs.dropLast() { XCTAssertGreaterThanOrEqual(s.durMin, 0) }
    }

    func testGradualScheduleAddsRampSteps() throws {
        let p = try sampleProfile()
        let cycles = buildCycles(p)
        let plain = buildSchedule(p, cycles, baseF: 64, rampF: 8, deepDropF: 8, gradual: false)
        let ramped = buildSchedule(p, cycles, baseF: 64, rampF: 8, deepDropF: 8, gradual: true)
        XCTAssertGreaterThan(ramped.count, plain.count)
        XCTAssertTrue(ramped.contains { $0.isRampStep })
        // No single gradual step jumps more than the ramp target plus rounding.
        let temps = ramped.compactMap { $0.temp }
        for i in 1..<temps.count {
            XCTAssertLessThanOrEqual(abs(temps[i] - temps[i - 1]), 4)
        }
    }

    // MARK: formatting

    func testFormatHelpers() {
        XCTAssertEqual(fmtTime(0), "12:00 AM")
        XCTAssertEqual(fmtTime(13 * 60 + 5), "1:05 PM")
        XCTAssertEqual(fmtTime(1440 + 90), "1:30 AM") // wraps past midnight
        XCTAssertEqual(fmtDur(0), "0h 00m")
        XCTAssertEqual(fmtDur(125), "2h 05m")
        XCTAssertEqual(cvt(64, .fahrenheit), "64°F")
        XCTAssertEqual(cvt(64, .celsius), "18°C")
    }
}
