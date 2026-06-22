import Foundation
import SwiftData
import SleepEngine

// A persisted, versioned snapshot of an "active sleep schedule." Each time the
// algorithm produces a meaningfully different schedule (see drift detection), a
// new version is inserted and the previous one is deactivated — giving a full
// history the user can look back through. The engine value types are stored as
// JSON blobs (see SleepCodables) so the engine stays free of SwiftData.
@Model
final class ScheduleVersion {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var isActive: Bool
    /// Human-readable reason this version was promoted (drift summary / "first
    /// schedule from onboarding"). Shown in History and the update notification.
    var promotionReason: String?

    // Engine snapshots, stored as JSON blobs.
    var scheduleData: Data
    var profileData: Data
    var paramsData: Data

    init(id: UUID = UUID(), createdAt: Date = Date(), isActive: Bool,
         schedule: [ScheduleSeg], profile: SleepProfile, params: TuningParams,
         promotionReason: String?) {
        self.id = id
        self.createdAt = createdAt
        self.isActive = isActive
        self.promotionReason = promotionReason
        self.scheduleData = SleepCodables.encode(schedule)
        self.profileData = SleepCodables.encode(profile)
        self.paramsData = SleepCodables.encode(params)
    }

    // Decoded accessors (not persisted).
    var schedule: [ScheduleSeg] { SleepCodables.decode([ScheduleSeg].self, from: scheduleData) ?? [] }
    var profile: SleepProfile? { SleepCodables.decode(SleepProfile.self, from: profileData) }
    var params: TuningParams { SleepCodables.decode(TuningParams.self, from: paramsData) ?? TuningParams() }
}
