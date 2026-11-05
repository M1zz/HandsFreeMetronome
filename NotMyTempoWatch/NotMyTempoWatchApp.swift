//
//  NotMyTempoWatchApp.swift
//  NotMyTempoWatch
//
//  손목 위 한 화면: 큰 템포 숫자 · 마디의 박 · [시작/멈춤].
//  Digital Crown 으로 템포를 바꾸고, 박 줄을 누르면 마디의 박 수가 바뀐다.
//  소리 없이 진동만 낸다 — 드럼 · 합주 · 밤 연습처럼 클릭 소리를 낼 수 없거나 들리지 않을 때.
//  폰 없이 혼자 돈다(템포는 워치가 기억한다).
//

import SwiftUI
import WatchKit

@main
struct NotMyTempoWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WristMetronomeView(metronome: .shared)
                // 컴플리케이션을 누르면 바로 시작
                .onOpenURL { url in
                    if url == WristTempo.startURL { WristMetronome.shared.start() }
                }
        }
    }
}

struct WristMetronomeView: View {
    @ObservedObject var metronome: WristMetronome
    @State private var crown: Double = Double(WristTempo.bpm)

    var body: some View {
        VStack(spacing: 4) {
            beatRow
            Spacer(minLength: 0)
            tempo
            Spacer(minLength: 0)
            startButton
        }
        .padding(.horizontal, 6)
        // 템포 숫자가 Crown 을 받는다. 연주 중에는 Crown 의 딸깍 진동을 끈다 — 박 진동과 섞이지 않게.
        .focusable()
        .digitalCrownRotation($crown, from: Double(WristTempo.range.lowerBound),
                              through: Double(WristTempo.range.upperBound), by: 1,
                              sensitivity: .medium, isContinuous: false,
                              isHapticFeedbackEnabled: !metronome.isPlaying)
        .onChange(of: crown) { _, value in metronome.bpm = Int(value.rounded()) }
        .onAppear {
            crown = Double(metronome.bpm)
            #if DEBUG
            WristDemo.apply(to: metronome)
            crown = Double(metronome.bpm)
            #endif
        }
    }

    /// 마디의 박: 1박은 빨강, 나머지 청록. 지금 울린 박이 커진다. 누르면 박 수가 1→8 로 돈다.
    private var beatRow: some View {
        HStack(spacing: metronome.beats > 6 ? 3 : 5) {
            ForEach(0..<metronome.beats, id: \.self) { i in
                let lit = metronome.currentBeat == i
                Circle()
                    .fill((i == 0 && metronome.beats > 1 ? Color.beatRed : Color.cue).opacity(lit ? 1 : 0.5))
                    .frame(width: 15, height: 15)
                    .scaleEffect(lit ? 1.35 : 1)
                    .animation(.easeOut(duration: 0.08), value: lit)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24)
        .contentShape(Rectangle())
        .onTapGesture {
            metronome.beats = metronome.beats % WristTempo.beatsRange.upperBound + 1
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(metronome.beats) beats per bar"))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Changes the number of beats"))
    }

    private var tempo: some View {
        VStack(spacing: 0) {
            Text("\(metronome.bpm)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(metronome.currentBeat == 0 && metronome.beats > 1 ? Color.beatRed : .primary)
            // 손목 진동이 따라올 수 있는 끝에 닿으면 정직하게 말한다.
            (metronome.bpm >= WristTempo.range.upperBound
                ? Text("Wrist taps go up to \(WristTempo.range.upperBound) BPM") : Text("BPM"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Tempo"))
        .accessibilityValue(Text("\(metronome.bpm) BPM"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: crown = min(crown + 1, Double(WristTempo.range.upperBound))
            case .decrement: crown = max(crown - 1, Double(WristTempo.range.lowerBound))
            @unknown default: break
            }
        }
    }

    @ViewBuilder private var startButton: some View {
        let button = Button {
            metronome.toggle()
        } label: {
            Label(metronome.isPlaying ? "Stop" : "Start",
                  systemImage: metronome.isPlaying ? "stop.fill" : "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(metronome.isPlaying ? .red : .cue)
        .foregroundStyle(metronome.isPlaying ? Color.white : Color.black)

        if #available(watchOS 11.0, *) {
            button.handGestureShortcut(.primaryAction)   // 두 번 두드리기로 시작 · 멈춤
        } else {
            button
        }
    }
}
