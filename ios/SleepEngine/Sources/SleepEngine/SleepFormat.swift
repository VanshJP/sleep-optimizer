import Foundation

// Formatting + sample-data helpers. Ported from lib/sleep.ts (`fmtTime`,
// `fmtDur`, `cvt`, `demoCSV`).

public func fmtTime(_ minutes: Double) -> String {
    var m = minutes.truncatingRemainder(dividingBy: 1440)
    m = (m + 1440).truncatingRemainder(dividingBy: 1440)
    var h = Int(floor(m / 60))
    let mm = String(format: "%02d", Int((m.truncatingRemainder(dividingBy: 60)).rounded()))
    let ap = h >= 12 ? "PM" : "AM"
    h = h % 12 == 0 ? 12 : h % 12
    return "\(h):\(mm) \(ap)"
}

public func fmtTime(_ minutes: Int) -> String { fmtTime(Double(minutes)) }

public func fmtDur(_ minutes: Int) -> String {
    "\(minutes / 60)h \(String(format: "%02d", Int((Double(minutes).truncatingRemainder(dividingBy: 60)).rounded())))m"
}

public func cvt(_ f: Int, _ u: TempUnit) -> String {
    u == .celsius ? "\(Int(((Double(f) - 32) / 1.8).rounded()))°C" : "\(f)°F"
}

/// Synthetic WHOOP-style CSV for previews/sample data. Mirrors `demoCSV()`.
public func demoCSV(now: Date = Date()) -> String {
    var csv = "Cycle start time,Cycle end time,Cycle timezone,Sleep onset,Wake onset,Sleep performance %,Respiratory rate (rpm),Asleep duration (min),In bed duration (min),Light sleep duration (min),Deep (SWS) duration (min),REM duration (min),Awake duration (min),Sleep need (min),Sleep debt (min),Sleep efficiency %,Sleep consistency %,Nap\n"
    func pad(_ n: Int) -> String { String(format: "%02d", n) }
    for i in 0..<45 {
        let d = now.addingTimeInterval(-Double(i) * 86400)
        let comp = engineCalendar.dateComponents([.year, .month, .day], from: d)
        let ds = "\(comp.year ?? 2026)-\(pad(comp.month ?? 1))-\(pad(comp.day ?? 1))"
        let onH = 23 + (i % 3 == 0 ? 1 : 0), onM = 10 + (i * 17) % 40
        let deep = 85 + (i * 13) % 30, rem = 110 + (i * 7) % 40, light = 200 + (i * 11) % 50
        let perf = 75 + (i * 5) % 25, eff = 82 + (i * 3) % 14
        csv += "\(ds) \(pad(onH % 24)):\(pad(onM)):00,,UTC-04:00,\(ds) \(pad(onH % 24)):\(pad(onM)):00,\(ds) \(pad(7 + i % 2)):\(pad((i * 23) % 60)):00,\(perf),16.2,\(deep + rem + light),\(deep + rem + light + 45),\(light),\(deep),\(rem),45,560,40,\(eff),70,false\n"
    }
    return csv
}
