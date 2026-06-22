import SwiftUI
import SleepEngine

struct MorningLoopView: View {
    @ObservedObject var vm: MorningLoopViewModel

    var body: some View {
        TabView {
            tonightTab
                .tabItem { Label("Tonight", systemImage: "moon.stars.fill") }
            HistoryView()
                .tabItem { Label("History", systemImage: "calendar") }
            settingsTab
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .preferredColorScheme(.dark)
        .tint(Palette.ice)
    }

    // MARK: - Tonight tab

    private var tonightTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch vm.state {
                    case .idle:             idleCard
                    case .loading:          loadingCard
                    case .failed(let msg):  errorCard(msg)
                    case .loaded:           loadedContent
                    }
                }
                .padding(16)
            }
            .background(Palette.screen.ignoresSafeArea())
            .navigationTitle("Sleep Optimizer")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if case .loaded = vm.state {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Task { await vm.refresh() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }

    private var idleCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 52)).foregroundStyle(Palette.iceDeep)
                .frame(maxWidth: .infinity).padding(.top, 16)
            Text("Good morning.")
                .font(.title2.weight(.semibold)).foregroundStyle(Palette.text)
            Text("Sync last night's sleep from Apple Health to review your stages and get tonight's updated Chilipad schedule.")
                .font(.subheadline).foregroundStyle(Palette.faint)
                .multilineTextAlignment(.center)
            Button { Task { await vm.refresh() } } label: {
                Label("Sync with Apple Health", systemImage: "heart.text.square.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).tint(Palette.iceDeep)
            Button("Try sample data") { vm.loadSample() }
                .font(.subheadline).foregroundStyle(Palette.faint)
        }
        .padding(24).frame(maxWidth: .infinity)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Palette.ice)
            Text("Reading Apple Health…").font(.subheadline).foregroundStyle(Palette.faint)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Palette.amber).font(.title2)
            Text(msg).font(.subheadline).foregroundStyle(Palette.text).multilineTextAlignment(.center)
            Button("Use sample data instead") { vm.loadSample() }.tint(Palette.ice)
        }
        .padding(24).frame(maxWidth: .infinity)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var loadedContent: some View {
        if let p = vm.profile {

            // ── Schedule-updated banner ────────────────────────────────────
            if let notice = vm.updateNotice {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bell.badge.fill").foregroundStyle(Palette.ice)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Schedule updated").font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.ice)
                        Text(notice).font(.footnote).foregroundStyle(Palette.text)
                    }
                    Spacer(minLength: 0)
                    Button { vm.updateNotice = nil } label: {
                        Image(systemName: "xmark").font(.caption).foregroundStyle(Palette.faint)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.iceDeep.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
            }

            // ── Timeline card ──────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Last Night", systemImage: "moon.zzz.fill")

                Text("Top: your sleep stages as they happened. Bottom: the Chilipad temperature holding underneath them. Tap Copy below to apply tonight's schedule.")
                    .font(.caption).foregroundStyle(Palette.faint)

                SleepTimelineView(profile: p, schedule: vm.schedule, stages: vm.lastNightStages)

                // Stage legend
                HStack(spacing: 12) {
                    ForEach(SleepStage.allCases, id: \.rawValue) { stage in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(stage.color.opacity(0.7)).frame(width: 12, height: 9)
                            Text(stage.label).font(.caption2).foregroundStyle(Palette.faint)
                        }
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Rectangle().fill(Palette.ice).frame(width: 14, height: 2)
                        Text("Temp").font(.caption2).foregroundStyle(Palette.faint)
                    }
                }
            }
            .card()

            // ── Stage breakdown ─────────────────────────────────────────────
            if !vm.correlations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Stage Breakdown", systemImage: "waveform.path.ecg")
                    ForEach(vm.correlations) { c in
                        HStack {
                            Circle().fill(c.stage.color).frame(width: 9, height: 9)
                            Text(c.stage.label).font(.subheadline).foregroundStyle(Palette.text)
                            Spacer()
                            Text(fmtDur(Int(c.minutes.rounded())))
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(Palette.faint)
                            if let t = c.avgCommandedTempF {
                                Text("@ \(cvt(Int(t.rounded()), vm.unit))")
                                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(t <= Double(vm.params.baseF) ? Palette.ice : Palette.amber)
                            }
                        }
                    }
                }
                .card()
            }

            // ── Nudge rationale ─────────────────────────────────────────────
            if !vm.nudgeRationale.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(Palette.amber)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tonight's adjustment")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Palette.amber)
                        Text(vm.nudgeRationale).font(.footnote).foregroundStyle(Palette.text)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }

            // ── Tonight's schedule card ─────────────────────────────────────
            if let program = vm.program {
                TranscriptionCardView(program: program, unit: vm.unit) {
                    vm.saveCurrentSchedule()
                }
            }
        }
    }

    // MARK: - Settings tab

    private var settingsTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Units").font(.headline).foregroundStyle(Palette.text)
                        Picker("Temperature", selection: $vm.unit) {
                            Text("°F").tag(TempUnit.fahrenheit)
                            Text("°C").tag(TempUnit.celsius)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Temperature Profile").font(.headline).foregroundStyle(Palette.text)
                        settingsSlider("Comfort baseline",   value: $vm.params.baseF,
                                       range: 55...85, label: cvt(vm.params.baseF, vm.unit))
                        settingsSlider("Deep-sleep cool drop", value: $vm.params.deepDropF,
                                       range: 0...15,  label: "−\(vm.params.deepDropF)°F")
                        settingsSlider("Wake warm-up",       value: $vm.params.rampF,
                                       range: 0...12,  label: "+\(vm.params.rampF)°F")
                        Toggle("Gradual ramps", isOn: $vm.params.gradual)
                            .tint(Palette.iceDeep).foregroundStyle(Palette.text)
                    }
                    .padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(16)
            }
            .background(Palette.screen.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func settingsSlider(_ title: String, value: Binding<Int>,
                                range: ClosedRange<Int>, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).foregroundStyle(Palette.text)
                Spacer()
                Text(label).font(.system(.subheadline, design: .monospaced)).foregroundStyle(Palette.ice)
            }
            Slider(value: Binding(get: { Double(value.wrappedValue) },
                                  set: { value.wrappedValue = Int($0.rounded()) }),
                   in: Double(range.lowerBound)...Double(range.upperBound),
                   step: 1).tint(Palette.iceDeep)
        }
    }
}
