import SwiftUI
import SwiftData
import SleepEngine

// MARK: - Chilipad value model
//
// Aggregates the per-night logs into a "what is the Chilipad doing for my sleep"
// story: how many nights it actually ran, and whether the nights it ran cooler
// during deep sleep earned more restorative (deep + REM) sleep.
private struct ChilipadValue {
    var nights: Int = 0
    var cooledNights: Int = 0
    var avgRestorative: Double = 0
    var bestRestorative: Double = 0
    var avgDeepTemp: Double?
    /// Avg restorative on the cooler-running half of nights vs the warmer half.
    var coolerRestorative: Double?
    var warmerRestorative: Double?

    var coverage: Double { nights > 0 ? Double(cooledNights) / Double(nights) : 0 }
    /// Restorative minutes gained on cooler-running nights (may be negative).
    var coolingDelta: Double? {
        guard let c = coolerRestorative, let w = warmerRestorative else { return nil }
        return c - w
    }

    static func from(_ logs: [NightLog]) -> ChilipadValue {
        var v = ChilipadValue()
        v.nights = logs.count
        guard !logs.isEmpty else { return v }

        let restoratives = logs.compactMap { $0.record.map { $0.deep + $0.rem } }
        v.avgRestorative = restoratives.isEmpty ? 0 : restoratives.reduce(0, +) / Double(restoratives.count)
        v.bestRestorative = restoratives.max() ?? 0

        // Nights where a schedule was actually commanding a temperature.
        let deepTempByLog: [(rest: Double, deepTemp: Double)] = logs.compactMap { log in
            guard let r = log.record else { return nil }
            guard let dt = log.correlations.first(where: { $0.stage == .deep })?.avgCommandedTempF
            else { return nil }
            return (r.deep + r.rem, dt)
        }
        v.cooledNights = logs.filter { l in l.correlations.contains { $0.avgCommandedTempF != nil } }.count
        if !deepTempByLog.isEmpty {
            v.avgDeepTemp = deepTempByLog.map(\.deepTemp).reduce(0, +) / Double(deepTempByLog.count)
        }

        // Split into cooler-running vs warmer-running halves by deep-sleep temp.
        if deepTempByLog.count >= 4 {
            let sorted = deepTempByLog.sorted { $0.deepTemp < $1.deepTemp }
            let half = sorted.count / 2
            let cooler = sorted.prefix(half)
            let warmer = sorted.suffix(sorted.count - half)
            v.coolerRestorative = cooler.map(\.rest).reduce(0, +) / Double(cooler.count)
            v.warmerRestorative = warmer.map(\.rest).reduce(0, +) / Double(warmer.count)
        }
        return v
    }
}

// MARK: - Day cell

private struct DayCell: View {
    let date: Date; let record: NightRecord?; let usedChilipad: Bool
    let isSelected: Bool; let isToday: Bool
    private var rst: Double { (record?.deep ?? 0) + (record?.rem ?? 0) }
    private func hm(_ m: Double) -> String { "\(Int(m)/60):\(String(format:"%02d",Int(m)%60))" }
    private var bg: Color {
        guard record != nil else { return .clear }
        return rst >= 120 ? Palette.iceDeep.opacity(0.30)
             : rst >=  75 ? Palette.iceDeep.opacity(0.15)
             : Palette.ember.opacity(0.18)
    }
    var body: some View {
        VStack(spacing: 1) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Palette.ice
                                 : record != nil ? Palette.text
                                 : Palette.faint.opacity(0.45))
            if let r = record {
                Text(hm(r.asleep))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.faint)
                // Restorative total, with a tiny snowflake when the Chilipad ran.
                HStack(spacing: 2) {
                    if usedChilipad {
                        Image(systemName: "snowflake").font(.system(size: 6)).foregroundStyle(Palette.ice)
                    }
                    Text(hm(rst))
                        .font(.system(size: 9, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Palette.ice)
                }
            } else { Spacer() }
        }
        .frame(maxWidth: .infinity).frame(height: 58)
        .background(isSelected ? Palette.iceDeep.opacity(0.38) : bg,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(isToday ? Palette.ice.opacity(0.55) : .clear, lineWidth: 1))
    }
}

// MARK: - History view

struct HistoryView: View {
    @Query(sort: \NightLog.wakeDate) private var logs: [NightLog]
    @Query private var versions: [ScheduleVersion]
    @State private var displayMonth = Date()
    @State private var selectedDate: Date? = nil
    @State private var unit: TempUnit = .fahrenheit
    private let cal = Calendar.current

    private var byDate: [String: NightLog] {
        Dictionary(logs.map { ($0.dayKey, $0) }, uniquingKeysWith: { _, b in b })
    }
    private var versionsByID: [UUID: ScheduleVersion] {
        Dictionary(versions.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
    }
    private func key(_ d: Date) -> String { SleepStore.dayKey(for: d, calendar: cal) }
    private func logFor(_ d: Date) -> NightLog? { byDate[key(d)] }
    private func usedChilipad(_ log: NightLog?) -> Bool {
        log?.correlations.contains { $0.avgCommandedTempF != nil } ?? false
    }
    private var avgRestorative: Double {
        let r = logs.compactMap { $0.record.map { $0.deep + $0.rem } }
        return r.isEmpty ? 0 : r.reduce(0, +) / Double(r.count)
    }

    private var gridDays: [Date?] {
        let start = cal.date(from: cal.dateComponents([.year, .month], from: displayMonth))!
        let count = cal.range(of: .day, in: .month, for: start)!.count
        let lead  = cal.component(.weekday, from: start) - 1
        var days: [Date?] = Array(repeating: nil, count: lead)
        for i in 0..<count { days.append(cal.date(byAdding: .day, value: i, to: start)) }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metric.gap) {
                    if logs.isEmpty { emptyState }
                    else {
                        valueCard
                        calendarCard
                        if let d = selectedDate, let log = logFor(d) { detailCard(log, date: d) }
                        else { tapHint }
                    }
                }.padding(Metric.gap)
            }
            .background(Palette.screen.ignoresSafeArea())
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            if selectedDate == nil, let latest = logs.last?.wakeDate {
                selectedDate = latest
                displayMonth = latest
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 44)).foregroundStyle(Palette.iceDeep)
            Text("No sleep history yet").font(.headline).foregroundStyle(Palette.text)
            Text("Sync with Apple Health on the Tonight tab to populate your calendar.")
                .font(.subheadline).foregroundStyle(Palette.faint).multilineTextAlignment(.center)
        }
        .padding(32).card()
    }

    private var tapHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap.fill").foregroundStyle(Palette.ice)
            Text("Tap any night to see its sleep stages, the Chilipad schedule that ran, and the temperatures you held at each stage.")
                .font(.footnote).foregroundStyle(Palette.faint)
        }
        .card()
    }

    // MARK: - Chilipad payoff card

    @ViewBuilder
    private var valueCard: some View {
        let v = ChilipadValue.from(logs)
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Chilipad Payoff", systemImage: "snowflake")

            // Headline insight.
            if let delta = v.coolingDelta, delta >= 5 {
                headline("+\(Int(delta.rounded())) min",
                         "more restorative sleep on the nights your bed ran cooler during deep sleep.",
                         Palette.mint)
            } else if let delta = v.coolingDelta, delta <= -5 {
                headline("Still tuning",
                         "cooler nights haven't out-performed warmer ones yet — the schedule keeps adapting.",
                         Palette.amber)
            } else {
                headline(fmtDur(Int(v.avgRestorative.rounded())),
                         "average restorative sleep across the \(v.nights) nights you've tracked.",
                         Palette.ice)
            }

            // Cooler vs warmer comparison bars.
            if let cooler = v.coolerRestorative, let warmer = v.warmerRestorative {
                let maxV = max(cooler, warmer, 1)
                VStack(spacing: 8) {
                    compareBar("Cooler nights", cooler, maxV, Palette.iceDeep)
                    compareBar("Warmer nights", warmer, maxV, Palette.ember)
                }
                Text("Restorative sleep (deep + REM), split by how cool the bed ran during deep sleep.")
                    .font(.caption2).foregroundStyle(Palette.faint)
            }

            // Supporting chips.
            HStack(spacing: 10) {
                MetricChip(value: "\(v.nights)", label: "Nights tracked", accent: Palette.text)
                MetricChip(value: "\(Int((v.coverage * 100).rounded()))%",
                           label: "Schedule active", accent: Palette.ice)
                MetricChip(value: fmtDur(Int(v.bestRestorative.rounded())),
                           label: "Best night", accent: Palette.mint)
            }
        }
        .card()
    }

    private func headline(_ big: String, _ caption: String, _ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(big).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(accent)
            Text(caption).font(.subheadline).foregroundStyle(Palette.faint)
        }
    }

    private func compareBar(_ label: String, _ value: Double, _ maxV: Double, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.caption).foregroundStyle(Palette.text).frame(width: 92, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.bg2)
                    Capsule().fill(color.opacity(0.85))
                        .frame(width: max(8, g.size.width * CGFloat(value / maxV)))
                }
            }.frame(height: 16)
            Text(fmtDur(Int(value.rounded())))
                .font(.system(.caption, design: .monospaced)).foregroundStyle(Palette.faint)
                .frame(width: 56, alignment: .trailing)
        }
    }

    // MARK: - Calendar card

    private var calendarCard: some View {
        VStack(spacing: 10) {
            HStack {
                Button { step(-1) } label: { Image(systemName: "chevron.left").font(.body.weight(.semibold)) }
                Spacer()
                Text(displayMonth, format: .dateTime.month(.wide).year())
                    .font(.headline).foregroundStyle(Palette.text)
                Spacer()
                Button { step(1) } label: { Image(systemName: "chevron.right").font(.body.weight(.semibold)) }
            }.foregroundStyle(Palette.ice)
            HStack(spacing: 0) {
                ForEach(Array("SMTWTFS".enumerated()), id: \.offset) { _, c in
                    Text(String(c)).font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.faint).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                    if let d = day {
                        DayCell(date: d, record: logFor(d)?.record, usedChilipad: usedChilipad(logFor(d)),
                                isSelected: selectedDate.map { cal.isDate($0, inSameDayAs: d) } ?? false,
                                isToday: cal.isDateInToday(d))
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    selectedDate = logFor(d) != nil ? d : nil
                                }
                            }
                    } else { Color.clear.frame(height: 58) }
                }
            }
            HStack(spacing: 12) {
                legendDot(Palette.iceDeep.opacity(0.35), "Great")
                legendDot(Palette.iceDeep.opacity(0.18), "OK")
                legendDot(Palette.ember.opacity(0.22), "Low")
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "snowflake").font(.system(size: 8)).foregroundStyle(Palette.ice)
                    Text("Chilipad ran")
                }
            }.font(.caption2).foregroundStyle(Palette.faint)
        }
        .card()
    }

    private func legendDot(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10); Text(label) }
    }
    private func step(_ d: Int) {
        if let m = cal.date(byAdding: .month, value: d, to: displayMonth) { displayMonth = m }
    }

    // MARK: - Day detail panel

    @ViewBuilder
    private func detailCard(_ log: NightLog, date: Date) -> some View {
        if let r = log.record {
            let rst = r.deep + r.rem
            let used = usedChilipad(log)
            let deepTemp = log.correlations.first(where: { $0.stage == .deep })?.avgCommandedTempF
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.headline.weight(.semibold)).foregroundStyle(Palette.text)
                    Spacer()
                    deltaTag(rst - avgRestorative)
                }

                // Did the Chilipad actually run this night?
                chilipadStatus(used: used, deepTemp: deepTemp)

                HStack(spacing: 0) {
                    statCol("Total Sleep",  fmtDur(Int(r.asleep.rounded())), Palette.text)
                    Rectangle().fill(Palette.hairline).frame(width: 1, height: 48)
                    statCol("Restorative",  fmtDur(Int(rst.rounded())),       Palette.ice)
                    Rectangle().fill(Palette.hairline).frame(width: 1, height: 48)
                    statCol("Efficiency",   "\(Int(r.eff.rounded()))%",        Palette.amber)
                }

                stageBar(r)

                HStack(spacing: 12) {
                    ForEach(SleepStage.allCases, id: \.rawValue) { s in
                        HStack(spacing: 4) {
                            Circle().fill(s.color).frame(width: 7, height: 7)
                            Text(s.label).font(.caption2).foregroundStyle(Palette.faint)
                        }
                    }
                    Spacer()
                }

                // How the schedule lined up: hypnogram + commanded temp ribbon.
                if !log.stages.isEmpty,
                   let vid = log.scheduleVersionID, let v = versionsByID[vid], let prof = v.profile {
                    Divider().overlay(Palette.hairline)
                    Text("Your night vs. the schedule")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                    SleepTimelineView(profile: prof, schedule: v.schedule, stages: log.stages)
                }

                // Temperatures lined up with each stage.
                if !log.correlations.isEmpty {
                    Divider().overlay(Palette.hairline)
                    Text("Temperature held at each stage")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                    ForEach(log.correlations) { c in
                        HStack {
                            Circle().fill(c.stage.color).frame(width: 9, height: 9)
                            Text(c.stage.label).font(.subheadline).foregroundStyle(Palette.text)
                            Spacer()
                            Text(fmtDur(Int(c.minutes.rounded())))
                                .font(.system(.caption, design: .monospaced)).foregroundStyle(Palette.faint)
                            if let t = c.avgCommandedTempF {
                                Text("@ \(cvt(Int(t.rounded()), unit))")
                                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(Palette.ice)
                            } else {
                                Text("—").font(.caption).foregroundStyle(Palette.faint)
                            }
                        }
                    }
                }
            }
            .card()
        }
    }

    /// "+22 min vs. your average" style tag comparing this night to the baseline.
    @ViewBuilder
    private func deltaTag(_ delta: Double) -> some View {
        let up = delta >= 0
        HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right").font(.caption2.weight(.bold))
            Text("\(up ? "+" : "−")\(Int(abs(delta).rounded()))m vs avg")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(up ? Palette.mint : Palette.amber)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background((up ? Palette.mint : Palette.amber).opacity(0.12),
                    in: Capsule())
    }

    private func chilipadStatus(used: Bool, deepTemp: Double?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: used ? "snowflake" : "moon.zzz")
                .foregroundStyle(used ? Palette.ice : Palette.faint)
            if used, let t = deepTemp {
                Text("Chilipad active — held \(cvt(Int(t.rounded()), unit)) through deep sleep")
                    .font(.caption.weight(.medium)).foregroundStyle(Palette.text)
            } else if used {
                Text("Chilipad active this night").font(.caption.weight(.medium)).foregroundStyle(Palette.text)
            } else {
                Text("No schedule applied — natural sleep, no cooling")
                    .font(.caption).foregroundStyle(Palette.faint)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background((used ? Palette.iceDeep : Palette.faint).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: Metric.pillRadius, style: .continuous))
    }

    private func statCol(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Palette.faint)
        }.frame(maxWidth: .infinity)
    }

    private func stageBar(_ r: NightRecord) -> some View {
        let total = max(r.deep + r.rem + r.light + r.awake, 1)
        return GeometryReader { g in
            HStack(spacing: 2) {
                if r.deep  > 0 { bar(.deep,  r.deep,  total, g.size.width) }
                if r.rem   > 0 { bar(.rem,   r.rem,   total, g.size.width) }
                if r.light > 0 { bar(.light, r.light, total, g.size.width) }
                if r.awake > 0 { bar(.awake, r.awake, total, g.size.width) }
            }
        }.frame(height: 10)
    }

    private func bar(_ stage: SleepStage, _ mins: Double, _ total: Double, _ width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(stage.color)
            .frame(width: max(3, width * mins / total))
    }
}
