import SwiftUI
import SleepEngine

/// The night, drawn as two stacked, time-aligned layers:
///
///   1. A **hypnogram** — last night's measured stages as rounded blocks in four
///      depth lanes (Awake · REM · Light · Deep), with thin risers connecting the
///      transitions, the way Apple Health / Oura draw a night.
///   2. A **temperature ribbon** — the commanded Chilipad setpoints over the same
///      clock window, as a stepped curve with a cool gradient fill, so you can see
///      exactly which temperature you were holding during deep sleep.
///
/// Both share one x (time) domain and a shared hour axis underneath so nothing
/// can mis-align. Drawn with `Canvas` for full control over the styling.
struct SleepTimelineView: View {
    let profile: SleepProfile
    let schedule: [ScheduleSeg]
    let stages: [StageSample]

    // Layout constants
    private let gutter: CGFloat = 42          // left label column
    private let hypHeight: CGFloat = 132
    private let ribbonHeight: CGFloat = 78
    private let axisHeight: CGFloat = 16

    private let cal = Calendar.current

    // MARK: - Derived data

    private struct TempPoint { let date: Date; let tempF: Int }

    private var stageAnchor: Date { stages.map(\.start).min() ?? Date() }

    /// Convert a schedule segment's minute-of-day into a real Date on this night.
    private func segDate(_ minuteOfDay: Int) -> Date {
        let h = cal.component(.hour, from: stageAnchor)
        let m = cal.component(.minute, from: stageAnchor)
        let anchorMod = h * 60 + m
        var delta = Double(minuteOfDay - anchorMod)
        if delta < 0 { delta += 1440 }
        if delta > 18 * 60 { delta -= 1440 }
        return stageAnchor.addingTimeInterval(delta * 60)
    }

    private var tempPoints: [TempPoint] {
        schedule.compactMap { seg in
            seg.temp.map { TempPoint(date: segDate(seg.t), tempF: $0) }
        }.sorted { $0.date < $1.date }
    }

    /// Shared clock-time window for both layers.
    private var domain: (start: Date, end: Date) {
        var lo = stages.map(\.start).min() ?? Date()
        var hi = stages.map(\.end).max() ?? lo.addingTimeInterval(8 * 3600)
        if let t0 = tempPoints.first?.date { lo = min(lo, t0) }
        if let t1 = tempPoints.last?.date { hi = max(hi, t1) }
        return (lo.addingTimeInterval(-6 * 60), hi.addingTimeInterval(6 * 60))
    }

    private func fx(_ date: Date, _ plotW: CGFloat) -> CGFloat {
        let (s, e) = domain
        let span = e.timeIntervalSince(s)
        guard span > 0 else { return gutter }
        return gutter + CGFloat(date.timeIntervalSince(s) / span) * plotW
    }

    private var coolest: TempPoint? { tempPoints.min { $0.tempF < $1.tempF } }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let plotW = geo.size.width - gutter
            VStack(spacing: 8) {
                hypnogram(plotW: plotW)
                    .frame(height: hypHeight)
                ribbon(plotW: plotW)
                    .frame(height: ribbonHeight)
                axis(plotW: plotW)
                    .frame(height: axisHeight)
            }
        }
        .frame(height: hypHeight + ribbonHeight + axisHeight + 16)
    }

    // MARK: - Hypnogram

    private func hypnogram(plotW: CGFloat) -> some View {
        Canvas { ctx, size in
            let laneCount = 4
            let laneH = size.height / CGFloat(laneCount)
            func laneCenter(_ lane: Int) -> CGFloat { laneH * (CGFloat(lane) + 0.5) }

            // Lane guides + labels.
            let labels = ["Awake", "REM", "Light", "Deep"]
            let labelColors: [Color] = [Palette.awake, Palette.rem, Palette.light, Palette.deep]
            for lane in 0..<laneCount {
                let y = laneCenter(lane)
                var guide = Path()
                guide.move(to: CGPoint(x: gutter, y: y))
                guide.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(guide, with: .color(Palette.faint.opacity(0.10)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

                let text = ctx.resolve(Text(labels[lane])
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(labelColors[lane].opacity(0.85)))
                ctx.draw(text, at: CGPoint(x: 4, y: y), anchor: .leading)
            }

            let sorted = stages.sorted { $0.start < $1.start }
            guard !sorted.isEmpty else {
                let text = ctx.resolve(Text("No stage data")
                    .font(.system(size: 11)).foregroundColor(Palette.faint))
                ctx.draw(text, at: CGPoint(x: gutter + plotW / 2, y: size.height / 2))
                return
            }

            let barH = laneH * 0.46

            // Thin risers between consecutive stage blocks.
            for i in 0..<(sorted.count - 1) {
                let a = sorted[i], b = sorted[i + 1]
                let x = fx(b.start, plotW)
                let y0 = laneCenter(a.stage.depthLane)
                let y1 = laneCenter(b.stage.depthLane)
                var riser = Path()
                riser.move(to: CGPoint(x: x, y: y0))
                riser.addLine(to: CGPoint(x: x, y: y1))
                ctx.stroke(riser, with: .color(Palette.text.opacity(0.22)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }

            // Stage blocks.
            for s in sorted {
                let x0 = fx(s.start, plotW)
                let x1 = fx(s.end, plotW)
                let w = max(barH, x1 - x0)
                let y = laneCenter(s.stage.depthLane) - barH / 2
                let rect = CGRect(x: x0, y: y, width: w, height: barH)
                let path = Path(roundedRect: rect, cornerRadius: barH / 2)
                ctx.fill(path, with: .linearGradient(
                    Gradient(colors: [s.stage.color, s.stage.color.opacity(0.72)]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.minX, y: rect.maxY)))
                // Top highlight.
                let hi = Path(roundedRect: CGRect(x: x0, y: y, width: w, height: barH * 0.42),
                              cornerRadius: barH / 2)
                ctx.fill(hi, with: .color(.white.opacity(0.12)))
            }
        }
    }

    // MARK: - Temperature ribbon

    private func ribbon(plotW: CGFloat) -> some View {
        Canvas { ctx, size in
            let pts = tempPoints
            guard pts.count >= 1 else {
                let text = ctx.resolve(Text("No schedule applied this night")
                    .font(.system(size: 11)).foregroundColor(Palette.faint))
                ctx.draw(text, at: CGPoint(x: gutter + plotW / 2, y: size.height / 2))
                return
            }

            let temps = pts.map { Double($0.tempF) }
            let lo = (temps.min() ?? 60) - 1.5
            let hi = (temps.max() ?? 75) + 1.5
            let top: CGFloat = 14, bottom = size.height - 4
            func y(_ t: Double) -> CGFloat {
                guard hi > lo else { return (top + bottom) / 2 }
                return bottom - CGFloat((t - lo) / (hi - lo)) * (bottom - top)
            }

            // Build a step-end path across the night.
            var line = Path()
            var first = true
            var lastY: CGFloat = 0
            for p in pts {
                let px = fx(p.date, plotW)
                let py = y(Double(p.tempF))
                if first {
                    line.move(to: CGPoint(x: px, y: py)); first = false
                } else {
                    line.addLine(to: CGPoint(x: px, y: lastY))
                    line.addLine(to: CGPoint(x: px, y: py))
                }
                lastY = py
            }
            // Carry the last setpoint out to the edge.
            line.addLine(to: CGPoint(x: gutter + plotW, y: lastY))

            // Gradient area fill under the line.
            var area = line
            area.addLine(to: CGPoint(x: gutter + plotW, y: bottom))
            area.addLine(to: CGPoint(x: fx(pts[0].date, plotW), y: bottom))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [Palette.iceDeep.opacity(0.42), Palette.iceDeep.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))

            ctx.stroke(line, with: .color(Palette.ice),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            // Setpoint dots.
            for p in pts {
                let c = CGPoint(x: fx(p.date, plotW), y: y(Double(p.tempF)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)),
                         with: .color(Palette.ice))
            }

            // Label the coolest setpoint — the heart of the deep-sleep cooldown.
            if let cool = coolest {
                let c = CGPoint(x: fx(cool.date, plotW), y: y(Double(cool.tempF)))
                let text = ctx.resolve(Text("\(cool.tempF)°")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Palette.ice))
                ctx.draw(text, at: CGPoint(x: c.x, y: c.y + 13), anchor: .center)
            }
        }
    }

    // MARK: - Shared hour axis

    private func axis(plotW: CGFloat) -> some View {
        Canvas { ctx, size in
            let (s, e) = domain
            var t = cal.nextDate(after: s, matching: DateComponents(minute: 0),
                                 matchingPolicy: .nextTime) ?? s
            let stepHours = e.timeIntervalSince(s) > 6 * 3600 ? 2 : 1
            while t <= e {
                let x = fx(t, plotW)
                let h = cal.component(.hour, from: t)
                let ap = h < 12 ? "a" : "p"
                let hh = h % 12 == 0 ? 12 : h % 12
                let text = ctx.resolve(Text("\(hh)\(ap)")
                    .font(.system(size: 9)).foregroundColor(Palette.faint))
                ctx.draw(text, at: CGPoint(x: x, y: size.height / 2), anchor: .center)
                t = cal.date(byAdding: .hour, value: stepHours, to: t) ?? e.addingTimeInterval(1)
            }
        }
    }
}
