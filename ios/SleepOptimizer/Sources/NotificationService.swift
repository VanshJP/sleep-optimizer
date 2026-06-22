import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

// Local notifications only (no APNs, no entitlement needed). Used to tell the
// user when the schedule has meaningfully changed, so they don't have to open
// the app every day to find out nothing moved.
@MainActor
final class NotificationService {

    /// Ask once for permission. Safe to call from onboarding or lazily on refresh.
    func requestAuthorization() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        #endif
    }

    /// Fire an immediate local notification summarizing a schedule update.
    func notifyScheduleUpdated(reason: String) {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Tonight's schedule updated"
        content.body = reason
        content.sound = .default
        let request = UNNotificationRequest(identifier: "schedule-update-\(UUID().uuidString)",
                                            content: content, trigger: nil)
        center.add(request)
        #endif
    }
}
