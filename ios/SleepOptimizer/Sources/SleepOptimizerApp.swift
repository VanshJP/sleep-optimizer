import SwiftUI
import SwiftData

@main
struct SleepOptimizerApp: App {
    /// One shared SwiftData container for the versioned schedules + night logs.
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: ScheduleVersion.self, NightLog.self)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: SleepStore(context: container.mainContext))
        }
        .modelContainer(container)
    }
}

/// Routes between first-run onboarding and the main app. The view model is owned
/// here so the schedule built during onboarding is already loaded when the
/// Tonight tab appears.
struct RootView: View {
    @StateObject private var vm: MorningLoopViewModel
    @AppStorage("hasOnboarded.v1") private var hasOnboarded = false

    init(store: SleepStore) {
        _vm = StateObject(wrappedValue: MorningLoopViewModel(store: store))
    }

    var body: some View {
        Group {
            if hasOnboarded {
                MorningLoopView(vm: vm)
            } else {
                OnboardingView(vm: vm) { hasOnboarded = true }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Palette.ice)
    }
}
