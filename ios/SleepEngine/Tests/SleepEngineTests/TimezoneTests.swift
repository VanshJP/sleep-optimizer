import XCTest
@testable import SleepEngine

// Regression guard for the "predicted bedtime is ~4 hours late" bug.
//
// HealthKit onset/wake are real `Date` instants. `buildProfile` must read their
// clock-times in the user's local timezone, not UTC. Reading an 11pm EST bedtime
// in UTC yields 04:00 — which is exactly the off-by-the-UTC-offset shift users saw.
final class TimezoneTests: XCTestCase {

    private func cal(_ tz: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tz)!
        return c
    }

    /// Five good nights: onset 23:00, wake 07:00, as instants in `calendar`'s zone.
    private func nights(in calendar: Calendar) -> [NightRecord] {
        (0..<5).map { day in
            func at(_ dayOffset: Int, _ hour: Int) -> Date {
                var c = DateComponents()
                c.year = 2026; c.month = 1; c.day = 6 + dayOffset
                c.hour = hour; c.minute = 0
                return calendar.date(from: c)!
            }
            return NightRecord(onset: at(day, 23), wake: at(day + 1, 7),
                               perf: 90, eff: 90, light: 230, deep: 90, rem: 100,
                               awake: 20, asleep: 420, nap: false)
        }
    }

    func testHealthKitInstantsReadInLocalTimezone() throws {
        let ny = cal("America/New_York") // EST (UTC-5) in January
        let profile = try buildProfile(nights(in: ny), calendar: ny)
        // 23:00 → 1380 min-of-day, 07:00 → 420 min-of-day.
        XCTAssertEqual(profile.onsetMin, 1380, accuracy: 1, "onset should be 11pm local, not the 4am UTC reading")
        XCTAssertEqual(profile.wakeMin, 420, accuracy: 1, "wake should be 7am local")
    }

    func testReadingLocalInstantsInUTCReproducesTheBug() throws {
        // Build the *same* real instants (11pm EST), but read them in UTC (the old
        // behavior). 23:00 EST == 04:00 UTC, so onset collapses to ~240 (4am).
        let ny = cal("America/New_York")
        let buggy = try buildProfile(nights(in: ny), calendar: cal("UTC"))
        XCTAssertEqual(buggy.onsetMin, 240, accuracy: 1, "documents the pre-fix UTC shift")
    }

    func testCSVStyleUTCDatesRoundTrip() throws {
        // The CSV path constructs dates in UTC (via parseDT/engineCalendar) and must
        // read them back in UTC too — this must stay correct after the fix.
        let utc = cal("UTC")
        let profile = try buildProfile(nights(in: utc), calendar: utc)
        XCTAssertEqual(profile.onsetMin, 1380, accuracy: 1)
        XCTAssertEqual(profile.wakeMin, 420, accuracy: 1)
    }
}
