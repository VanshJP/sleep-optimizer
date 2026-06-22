import SwiftUI
import SleepEngine
#if canImport(UIKit)
import UIKit
#endif

// The copy-ready checklist the user types into the Sleep.me / Chilipad app:
// Bed Time, N Adjustments, Wake Time, and the Warm Awake toggle — all snapped to
// the app's 5-minute dial.
struct TranscriptionCardView: View {
    let program: SleepmeProgram
    let unit: TempUnit
    var onCopy: (() -> Void)? = nil
    @State private var copied = false

    private var lines: [String] { transcriptionLines(program, unit: unit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tonight's schedule")
                    .font(.headline).foregroundStyle(Palette.text)
                Spacer()
                Button(action: copy) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(Palette.ice)
            }

            row("Bed Time", fmtTime(program.bedMinute), cvt(program.bedTempF, unit), Palette.ice)
            ForEach(program.adjustments) { a in
                row("Adjustment", fmtTime(a.minuteOfDay), cvt(a.tempF, unit), Palette.iceDeep,
                    note: a.label)
            }
            row("Wake Time", fmtTime(program.wakeMinute), cvt(program.wakeTempF, unit), Palette.amber)

            HStack {
                Image(systemName: program.warmAwake ? "sun.max.fill" : "moon.fill")
                    .foregroundStyle(program.warmAwake ? Palette.amber : Palette.faint)
                Text("Warm Awake: \(program.warmAwake ? "ON" : "OFF")")
                    .font(.subheadline).foregroundStyle(Palette.faint)
            }
            .padding(.top, 2)

            Text("Enter these into the Chilipad app's schedule editor, then leave it. The app re-tunes from tomorrow's sleep.")
                .font(.caption).foregroundStyle(Palette.faint)
        }
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ kind: String, _ time: String, _ temp: String,
                     _ accent: Color, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                if let note { Text(note).font(.caption2).foregroundStyle(Palette.faint) }
            }
            Spacer()
            Text(time).font(.system(.body, design: .monospaced)).foregroundStyle(Palette.text)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(Palette.faint)
            Text(temp).font(.system(.body, design: .monospaced).weight(.bold))
                .foregroundStyle(accent)
        }
    }

    private func copy() {
        #if canImport(UIKit)
        UIPasteboard.general.string = lines.joined(separator: "\n")
        #endif
        onCopy?()
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}
