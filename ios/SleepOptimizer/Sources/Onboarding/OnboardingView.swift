import SwiftUI
import SleepEngine

// First-run flow: welcome → pick a baseline comfort temperature → aggregate the
// last ~30 nights from Apple Health and build the first schedule. Health and
// notification permissions are requested inside vm.runInitialOnboarding.
struct OnboardingView: View {
    @ObservedObject var vm: MorningLoopViewModel
    let onComplete: () -> Void

    private enum Step { case welcome, baseline, building }
    @State private var step: Step = .welcome
    @State private var baseF: Int = 77

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            switch step {
            case .welcome:  welcome
            case .baseline: baseline
            case .building: building
            }
        }
        .animation(.easeInOut, value: step)
    }

    // MARK: - Welcome

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "bed.double.circle.fill")
                .font(.system(size: 72)).foregroundStyle(Palette.iceDeep)
            Text("Sleep Optimizer")
                .font(.largeTitle.weight(.bold)).foregroundStyle(Palette.text)
            Text("We read your recent sleep from Apple Health, keep only your good nights, and build a bed-temperature schedule around them. It updates over time and tells you when something meaningful changes.")
                .font(.body).foregroundStyle(Palette.faint)
                .multilineTextAlignment(.center).padding(.horizontal, 8)
            Spacer()
            Button { step = .baseline } label: {
                Text("Get started").frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).tint(Palette.iceDeep)
        }
        .padding(28)
    }

    // MARK: - Baseline temperature

    private var baseline: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("Your comfortable baseline")
                .font(.title.weight(.bold)).foregroundStyle(Palette.text)
            Text("What bed temperature feels good to you when you first lie down? We'll cool from here during deep sleep and warm back up before you wake.")
                .font(.body).foregroundStyle(Palette.faint)

            HStack {
                Spacer()
                Text("\(baseF)°F")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ice)
                Spacer()
            }
            Slider(value: Binding(get: { Double(baseF) },
                                  set: { baseF = Int($0.rounded()) }),
                   in: 60...85, step: 1).tint(Palette.iceDeep)
            HStack {
                Text("Cooler").font(.caption); Spacer(); Text("Warmer").font(.caption)
            }.foregroundStyle(Palette.faint)

            Spacer()
            Button {
                step = .building
                Task {
                    await vm.runInitialOnboarding(baseF: baseF)
                    onComplete()
                }
            } label: {
                Text("Build my schedule").frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).tint(Palette.iceDeep)
        }
        .padding(28)
    }

    // MARK: - Building

    private var building: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView().tint(Palette.ice).scaleEffect(1.4)
            Text("Building your schedule…")
                .font(.headline).foregroundStyle(Palette.text)
            Text("Aggregating your recent nights and filtering out the rough ones.")
                .font(.subheadline).foregroundStyle(Palette.faint)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(28)
    }
}
