import SwiftUI
import Charts

/// How a timed run went: the tempo over time, the top speed, where the climb got
/// stuck, and where to start next time — with Save, for the runs worth keeping.
/// Used as the sheet when the timer ends and as a saved run in `PracticeLogView`.
struct PracticeReportView: View {
    let session: PracticeSession
    @ObservedObject var log: PracticeLog = .shared
    /// "Set this tempo" — the owner applies it.
    let onUseTempo: (Int) -> Void

    private let cue = Color.cue
    /// Chart value names — read by VoiceOver's audio graph, the same in every language.
    private enum Axis { static let time = "min", bpm = "BPM" }
    private var report: PracticeReport { session.report }

    var body: some View {
        List {
            Section {
                chart
                    .frame(height: 200)
                    .padding(.vertical, 8)
            } header: {
                Text(session.date.formatted(date: .abbreviated, time: .shortened)
                     + " · " + duration(session.seconds))
            }
            Section {
                row("Tempo", value: "\(report.startBPM) → \(report.endBPM) BPM")
                row("Top speed", value: "\(report.peakBPM) BPM",
                    detail: String(localized: "Held for \(duration(report.peakSeconds))"))
                flow
            }
            Section {
                row("Next time", value: String(localized: "Start at \(report.nextStart) BPM"),
                    detail: adviceText)
                Button {
                    onUseTempo(report.nextStart)
                } label: {
                    Label("Set this tempo", systemImage: "metronome")
                }
                .tint(cue)
            }
        }
        // Save stays in reach at the bottom, however long the report runs.
        .safeAreaInset(edge: .bottom) { saveButton }
    }

    private var saveButton: some View {
        let saved = log.isSaved(session)
        return Button {
            log.save(session)
        } label: {
            Label(saved ? "Saved" : "Save", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                .font(.headline)
                .foregroundStyle(saved ? Color.secondary : Color.onCue)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(saved ? Color(.tertiarySystemFill) : cue))
        }
        .buttonStyle(.plain)
        .disabled(saved)
        .accessibilityInputLabels(["Save"])
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Chart

    private var chart: some View {
        let lowest = report.holds.map(\.bpm).min() ?? report.startBPM
        return Chart {
            // Where the climb got stuck: a soft band behind the line.
            ForEach(report.walls) { wall in
                RectangleMark(xStart: .value(Axis.time, wall.hold.start / 60),
                              xEnd: .value(Axis.time, (wall.hold.start + wall.hold.seconds) / 60))
                    .foregroundStyle(Color.orange.opacity(0.18))
            }
            ForEach(Array(session.points.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value(Axis.time, p.second / 60), y: .value(Axis.bpm, p.bpm))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(cue)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            RuleMark(y: .value(Axis.bpm, report.peakBPM))
                .foregroundStyle(cue.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartXScale(domain: 0...max(session.seconds / 60, 1))
        .chartYScale(domain: max(0, lowest - 10)...(report.peakBPM + 10))
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minutes = value.as(Double.self) { Text(verbatim: "\(Int(minutes))′") }
                }
            }
        }
        .accessibilityLabel(Text(verbatim: "\(report.startBPM) → \(report.endBPM) BPM"))
    }

    // MARK: Rows

    @ViewBuilder
    private var flow: some View {
        if report.walls.isEmpty {
            row("Flow", value: report.peakBPM > report.startBPM
                ? String(localized: "Rose evenly") : String(localized: "Stayed at one tempo"))
        } else {
            row("Flow", value: report.walls.prefix(3).map(wallText).joined(separator: "\n"))
        }
    }

    private func wallText(_ wall: PracticeReport.Wall) -> String {
        switch wall.kind {
        case .stuck: return String(localized: "Stuck at \(wall.hold.bpm) BPM for \(duration(wall.hold.seconds))")
        case .backedOff: return String(localized: "Backed off from \(wall.hold.bpm) BPM")
        }
    }

    private var adviceText: String {
        switch report.advice {
        case .warmUpToWall: return String(localized: "A little below where it got hard, so you reach it warmed up.")
        case .halfway: return String(localized: "Halfway up today’s climb: start warm, finish faster.")
        case .stepUp: return String(localized: "One step faster than today.")
        }
    }

    private func row(_ title: LocalizedStringKey, value: String, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).font(.body.weight(.semibold)).monospacedDigit()
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func duration(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded())
            .formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }
}

/// The runs the player saved, newest first; swipe to delete.
struct PracticeLogView: View {
    @ObservedObject var log: PracticeLog = .shared
    let onUseTempo: (Int) -> Void

    var body: some View {
        List {
            if log.sessions.isEmpty {
                Text("No saved practice yet. When the timer ends, tap Save.")
                    .foregroundStyle(.secondary)
            }
            ForEach(log.sessions) { session in
                NavigationLink {
                    PracticeReportView(session: session, onUseTempo: onUseTempo)
                        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
                } label: {
                    let r = session.report
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.date.formatted(date: .abbreviated, time: .shortened))
                        Text(verbatim: "\(r.startBPM) → \(r.peakBPM) BPM")
                            .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .onDelete { log.delete(at: $0) }
        }
        .navigationTitle("Saved practice")
    }
}
