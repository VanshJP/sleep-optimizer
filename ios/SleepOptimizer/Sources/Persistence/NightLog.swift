import Foundation
import SwiftData
import SleepEngine

// One persisted night: what actually happened (onset/wake + stage samples) plus
// how it lined up with the schedule that was in effect — the per-stage commanded
// temperatures (correlations). This is what powers History's day detail: "here's
// how the schedule lined up with your sleep, and the temps lined up with it."
@Model
final class NightLog {
    /// Wake-day key "y-m-d" (one row per night). Unique so refresh upserts.
    @Attribute(.unique) var dayKey: String
    var wakeDate: Date
    var onset: Date
    var wake: Date
    /// Which schedule version this night was compared against.
    var scheduleVersionID: UUID?

    var recordData: Data
    var stagesData: Data
    var correlationsData: Data

    init(dayKey: String, record: NightRecord, stages: [StageSample],
         correlations: [SleepCorrelation], scheduleVersionID: UUID?) {
        self.dayKey = dayKey
        self.wakeDate = record.wake
        self.onset = record.onset
        self.wake = record.wake
        self.scheduleVersionID = scheduleVersionID
        self.recordData = SleepCodables.encode(record)
        self.stagesData = SleepCodables.encode(stages)
        self.correlationsData = SleepCodables.encode(correlations)
    }

    var record: NightRecord? { SleepCodables.decode(NightRecord.self, from: recordData) }
    var stages: [StageSample] { SleepCodables.decode([StageSample].self, from: stagesData) ?? [] }
    var correlations: [SleepCorrelation] { SleepCodables.decode([SleepCorrelation].self, from: correlationsData) ?? [] }
}
