import Foundation

// CSV parsing, WHOOP export analysis, and the shared profile builder. Ported
// from lib/sleep.ts (`parseCSV`, `parseDT`, `median`, `analyze`).

/// Fixed UTC Gregorian calendar used by the CSV path. `parseDT` *constructs*
/// dates from this calendar, so the CSV path must also *read* clock-times back
/// with it (round-trip). The HealthKit path is different: its dates are real
/// `Date` instants, so it must read clock-times in the user's local timezone —
/// see the `calendar` parameter threaded through `buildProfile`/`minuteOfDay`.
let engineCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

func parseCSV(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var cur = ""
    var q = false
    let chars = Array(text)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        if q {
            if c == "\"" {
                if i + 1 < chars.count && chars[i + 1] == "\"" { cur += "\""; i += 1 }
                else { q = false }
            } else { cur.append(c) }
        } else if c == "\"" { q = true }
        else if c == "," { row.append(cur); cur = "" }
        else if c == "\n" || c == "\r" {
            if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
            row.append(cur); cur = ""
            if row.contains(where: { $0 != "" }) { rows.append(row) }
            row = []
        } else { cur.append(c) }
        i += 1
    }
    if cur != "" || !row.isEmpty {
        row.append(cur)
        if row.contains(where: { $0 != "" }) { rows.append(row) }
    }
    return rows
}

func parseDT(_ s: String) -> Date? {
    // Matches "YYYY-MM-DD[ T]HH:MM:SS" prefix.
    let pattern = "^([0-9]{4})-([0-9]{2})-([0-9]{2})[ T]([0-9]{2}):([0-9]{2}):([0-9]{2})"
    guard let re = try? NSRegularExpression(pattern: pattern),
          let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
    else { return nil }
    func g(_ i: Int) -> Int { Int((s as NSString).substring(with: m.range(at: i))) ?? 0 }
    var comp = DateComponents()
    comp.year = g(1); comp.month = g(2); comp.day = g(3)
    comp.hour = g(4); comp.minute = g(5); comp.second = g(6)
    return engineCalendar.date(from: comp)
}

func median(_ a: [Double]) -> Double {
    let s = a.sorted()
    let m = s.count >> 1
    return s.count % 2 != 0 ? s[m] : (s[m - 1] + s[m]) / 2
}

func minuteOfDay(_ date: Date, _ calendar: Calendar = .current) -> Double {
    let c = calendar.dateComponents([.hour, .minute], from: date)
    return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
}

/// Parse a WHOOP sleeps.csv into nightly records, then build a profile.
public func analyze(_ text: String) throws -> SleepProfile {
    let rows = parseCSV(text)
    if rows.count < 2 {
        throw SleepEngineError.message("No data rows found — paste the whole file including the header line.")
    }
    let head = rows[0].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    func col(_ frag: String) -> Int { head.firstIndex(where: { $0.contains(frag) }) ?? -1 }
    let ci = (onset: col("sleep onset"), wake: col("wake onset"), perf: col("performance"),
              eff: col("efficiency"), light: col("light sleep"), deep: col("deep"),
              rem: col("rem"), awake: col("awake duration"), asleep: col("asleep duration"), nap: col("nap"))
    if ci.onset < 0 || ci.deep < 0 || ci.rem < 0 {
        throw SleepEngineError.message("This doesn't look like a WHOOP sleeps.csv — missing expected columns (Sleep onset / Deep / REM).")
    }
    func num(_ r: [String], _ i: Int) -> Double {
        guard i >= 0, i < r.count else { return .nan }
        return Double(r[i].trimmingCharacters(in: .whitespaces)) ?? .nan
    }
    let nights: [NightRecord] = rows.dropFirst().compactMap { r in
        guard let onset = ci.onset >= 0 && ci.onset < r.count ? parseDT(r[ci.onset]) : nil,
              let wake = ci.wake >= 0 && ci.wake < r.count ? parseDT(r[ci.wake]) : nil
        else { return nil }
        let nap = ci.nap >= 0 && ci.nap < r.count && r[ci.nap].trimmingCharacters(in: .whitespaces) == "true"
        let asleep = num(r, ci.asleep), deep = num(r, ci.deep)
        guard !nap, asleep > 120, deep.isFinite else { return nil }
        return NightRecord(onset: onset, wake: wake, perf: num(r, ci.perf), eff: num(r, ci.eff),
                           light: num(r, ci.light), deep: deep, rem: num(r, ci.rem),
                           awake: num(r, ci.awake), asleep: asleep, nap: nap)
    }
    if nights.isEmpty { throw SleepEngineError.message("No valid full-night records found.") }
    // CSV dates are constructed in UTC by `parseDT`, so read clock-times back in
    // UTC too. (The HealthKit path uses the default `.current` calendar.)
    return try buildProfile(nights, calendar: engineCalendar)
}

/// Recent-window + good-night selection + medians. Shared by the CSV path and
/// the HealthKit ingester. `calendar` selects the timezone used to extract the
/// onset/wake clock-times: the HealthKit path passes `.current` (its dates are
/// real instants), the CSV path passes `engineCalendar` (UTC, to round-trip the
/// dates `parseDT` builds). Getting this wrong shifts the whole schedule by the
/// device's UTC offset — the "predicted bedtime is 4 hours late" bug.
public func buildProfile(_ input: [NightRecord], calendar: Calendar = .current) throws -> SleepProfile {
    let nights = input.filter { !$0.nap && $0.asleep > 120 && $0.deep.isFinite }
        .sorted { $0.onset < $1.onset }
    if nights.isEmpty { throw SleepEngineError.message("No valid full-night records found.") }

    let latest = nights[nights.count - 1].onset
    let cutoff = latest.addingTimeInterval(-60 * 86400)
    let recent = nights.filter { $0.onset >= cutoff }

    var good = recent.filter { $0.perf >= 80 && $0.eff >= 85 }
    if good.count < 10 {
        good = recent.sorted { ($0.perf + $0.eff) > ($1.perf + $1.eff) }
            .prefix(max(5, recent.count >> 1)).map { $0 }
    }
    if good.count < 3 {
        throw SleepEngineError.message("Not enough recent nights to build a reliable profile (need at least 3).")
    }

    let om = good.map { n -> Double in let m = minuteOfDay(n.onset, calendar); return m > 720 ? m : m + 1440 }
    let wm = good.map { minuteOfDay($0.wake, calendar) }
    return SleepProfile(
        nRecent: recent.count, nGood: good.count,
        onsetMin: median(om).truncatingRemainder(dividingBy: 1440), wakeMin: median(wm),
        deep: median(good.map { $0.deep }), rem: median(good.map { $0.rem }),
        light: median(good.map { $0.light }), awake: median(good.map { $0.awake }),
        asleep: median(good.map { $0.asleep }),
        perf: median(good.map { $0.perf }), eff: median(good.map { $0.eff }))
}
