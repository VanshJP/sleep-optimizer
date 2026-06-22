import XCTest
@testable import SleepEngine

// Validates the HealthKit-free night grouping (groupNights) used by the app's
// HealthKitService.

final class IngestTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    /// Date `dayOffset` days from a fixed reference at the given hour/minute.
    private func d(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 1; c.day = 1 + dayOffset
        c.hour = hour; c.minute = minute
        return cal.date(from: c)!
    }

    func testGroupSplitsNightsOnLargeGap() {
        // Night 1: 23:00 day0 → 06:00 day1. Night 2: 23:00 day1 → 06:00 day2.
        let intervals = [
            StageInterval(stage: .light, start: d(0, 23), end: d(1, 0)),
            StageInterval(stage: .deep, start: d(1, 0), end: d(1, 2)),
            StageInterval(stage: .rem, start: d(1, 2), end: d(1, 6)),
            StageInterval(stage: .light, start: d(1, 23), end: d(2, 1)),
            StageInterval(stage: .deep, start: d(2, 1), end: d(2, 3)),
            StageInterval(stage: .rem, start: d(2, 3), end: d(2, 6)),
        ]
        let nights = groupNights(intervals)
        XCTAssertEqual(nights.count, 2)
        XCTAssertEqual(nights[0].record.deep, 120, accuracy: 0.001)
        XCTAssertEqual(nights[0].record.rem, 240, accuracy: 0.001)
        XCTAssertEqual(nights[0].stages.count, 3)
    }

    func testEfficiencyUsesInBedDenominator() {
        // 7 h asleep within an 8 h in-bed window ⇒ ~87.5% efficiency.
        let intervals = [
            StageInterval(stage: nil, start: d(0, 23), end: d(1, 7)),       // in bed 8h
            StageInterval(stage: .light, start: d(0, 23, 30), end: d(1, 2)),
            StageInterval(stage: .deep, start: d(1, 2), end: d(1, 4)),
            StageInterval(stage: .rem, start: d(1, 4), end: d(1, 6, 30)),
            StageInterval(stage: .awake, start: d(1, 6, 30), end: d(1, 7)),
        ]
        let nights = groupNights(intervals)
        XCTAssertEqual(nights.count, 1)
        let r = nights[0].record
        XCTAssertEqual(r.asleep, 420, accuracy: 1.0)
        XCTAssertEqual(r.eff, 87.5, accuracy: 1.0)
        XCTAssertEqual(r.perf, r.eff, accuracy: 0.001, "perf proxies efficiency for HealthKit")
        // In-bed markers are not emitted as correlation samples.
        XCTAssertFalse(nights[0].stages.contains { $0.stage == .awake } == false)
    }

    func testEmptyAndStagelessInputs() {
        XCTAssertTrue(groupNights([]).isEmpty)
        let onlyInBed = [StageInterval(stage: nil, start: d(0, 23), end: d(1, 7))]
        XCTAssertTrue(groupNights(onlyInBed).isEmpty, "A night with no stage data is dropped")
    }
}
