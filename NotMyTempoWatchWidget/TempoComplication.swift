//
//  TempoComplication.swift
//  NotMyTempoWatchWidget
//
//  손목을 들 때마다 보는 값 하나: 마지막 템포. 누르면 워치 앱이 열리며 그 템포로 바로 진동을 시작한다.
//

import WidgetKit
import SwiftUI

struct TempoEntry: TimelineEntry {
    let date: Date
    let bpm: Int
    let beats: Int
}

struct TempoProvider: TimelineProvider {
    func placeholder(in context: Context) -> TempoEntry { TempoEntry(date: .now, bpm: 100, beats: 4) }

    func getSnapshot(in context: Context, completion: @escaping (TempoEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TempoEntry>) -> Void) {
        // 템포는 워치 앱이 멈출 때 다시 그리게 한다 — 그 밖에는 바뀌지 않는다.
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> TempoEntry { TempoEntry(date: .now, bpm: WristTempo.bpm, beats: WristTempo.beats) }
}

struct TempoComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TempoEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: -2) {
                    Image(systemName: "metronome.fill").font(.caption2).widgetAccentable()
                    Text("\(entry.bpm)")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                }
            case .accessoryCorner:
                Image(systemName: "metronome.fill")
                    .font(.title3)
                    .widgetAccentable()
                    .widgetLabel { Text("\(entry.bpm) BPM") }
            case .accessoryInline:
                Label { Text("\(entry.bpm) BPM") } icon: { Image(systemName: "metronome.fill") }
            default:
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Not My Tempo").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Text("\(entry.bpm) BPM")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .widgetAccentable()
                        Text("Tap to start on your wrist").font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "play.fill").font(.title3).widgetAccentable()
                }
            }
        }
        .widgetURL(WristTempo.startURL)
    }
}

@main
struct TempoComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LastTempo", provider: TempoProvider()) { entry in
            TempoComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Last Tempo")
        .description("Shows your last tempo. Tap to start the wrist taps.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}
