import Foundation

/// Median sleep profile built from the user's recent good nights. Mirrors the
/// `SleepProfile` interface in lib/sleep.ts. All durations are minutes; onset
/// and wake are minutes-of-day.
public struct SleepProfile: Equatable, Sendable, Codable {
    public var nRecent: Int
    public var nGood: Int
    public var onsetMin: Double
    public var wakeMin: Double
    public var deep: Double
    public var rem: Double
    public var light: Double
    public var awake: Double
    public var asleep: Double
    public var perf: Double
    public var eff: Double

    public init(nRecent: Int, nGood: Int, onsetMin: Double, wakeMin: Double,
                deep: Double, rem: Double, light: Double, awake: Double,
                asleep: Double, perf: Double, eff: Double) {
        self.nRecent = nRecent; self.nGood = nGood
        self.onsetMin = onsetMin; self.wakeMin = wakeMin
        self.deep = deep; self.rem = rem; self.light = light; self.awake = awake
        self.asleep = asleep; self.perf = perf; self.eff = eff
    }
}

/// One ~90-minute sleep cycle with its stage minutes. `start`/`end` are minutes
/// after onset. Mirrors `Cycle` in lib/sleep.ts.
public struct Cycle: Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var deep: Double
    public var rem: Double
    public var light: Double

    public init(start: Double, end: Double, deep: Double, rem: Double, light: Double) {
        self.start = start; self.end = end
        self.deep = deep; self.rem = rem; self.light = light
    }
}

/// A single setpoint in the generated schedule. Mirrors `ScheduleSeg` in
/// lib/sleep.ts. `temp == nil` means the dock is off. `t` is minutes-of-day.
public struct ScheduleSeg: Equatable, Sendable, Identifiable, Codable {
    public var t: Int
    public var temp: Int?
    public var phase: String
    public var why: String
    public var durMin: Int
    /// True for intermediate steps in a gradual ramp — drawn as a diagonal slope
    /// rather than a discrete step-hold.
    public var isRampStep: Bool

    public var id: String { "\(t)-\(phase)-\(temp.map(String.init) ?? "off")" }

    public init(t: Int, temp: Int?, phase: String, why: String,
                durMin: Int, isRampStep: Bool = false) {
        self.t = t; self.temp = temp; self.phase = phase
        self.why = why; self.durMin = durMin; self.isRampStep = isRampStep
    }
}

/// One night of stage totals — the unit `analyze` filters and medians over.
/// Produced either by parsing a WHOOP CSV or by aggregating HealthKit samples,
/// so both ingestion paths feed the same profile builder.
public struct NightRecord: Equatable, Sendable, Codable {
    public var onset: Date
    public var wake: Date
    public var perf: Double
    public var eff: Double
    public var light: Double
    public var deep: Double
    public var rem: Double
    public var awake: Double
    public var asleep: Double
    public var nap: Bool

    public init(onset: Date, wake: Date, perf: Double, eff: Double,
                light: Double, deep: Double, rem: Double, awake: Double,
                asleep: Double, nap: Bool) {
        self.onset = onset; self.wake = wake; self.perf = perf; self.eff = eff
        self.light = light; self.deep = deep; self.rem = rem
        self.awake = awake; self.asleep = asleep; self.nap = nap
    }
}

/// Temperature unit for display/conversion.
public enum TempUnit: String, Sendable, Codable { case fahrenheit = "F", celsius = "C" }

/// Sleep stages we correlate against commanded temperatures.
public enum SleepStage: String, Sendable, CaseIterable, Codable {
    case deep, rem, light, awake
}

public enum SleepEngineError: Error, Equatable, Sendable {
    case message(String)
}
