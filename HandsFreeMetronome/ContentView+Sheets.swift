import SwiftUI
import UIKit
import AppIntents
import TipKit
import LeeoKit

/// Sheets and pages: commands, settings, instrument signal, practice mode, timer, tuner.
/// Part of `ContentView`, split by area so an edit recompiles one small file.
extension ContentView {
    // MARK: Commands sheet

    var commandsSheet: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    // The words to say — only when the app's language has its own.
                    if VoiceVocabulary.native != nil {
                        Section {
                            VoiceLanguagePicker()
                        } header: {
                            Text("Command language")
                        }
                    }
                    Section {
                        usageRow("circle.grid.3x3", "Set beats", "Tap the dots to choose the time signature.")
                        usageRow("hand.tap", "Tap tempo", "Tap the big BPM number in rhythm to set the tempo.")
                        usageRow("slider.horizontal.3", "Tempo", "Drag the tempo slider, or tap the − / + buttons.")
                        usageRow("speaker.wave.2.fill", "Volume", "Say \u{201C}\(voiceWord(.louder))\u{201D} / \u{201C}\(voiceWord(.quieter))\u{201D} / \u{201C}\(voiceWord(.mute))\u{201D}, or \u{201C}\(voiceWord(.volume60))\u{201D}.")
                        usageRow("music.note", "Subdivision", "Tap 1/4, 1/8, Trip, or 1/16. Double-tap the card to open Accents and set every click of the measure high, low, or silent.")
                        usageRow("circle.circle", "Switch view", "Tap the view icon (top-right of the beat card) — bounce → orbit → ring sweep.")
                        usageRow("target", "Timing check", "In orbit view, tap the ring while playing — every click (including subdivisions) is a target. The moving dot leaves a ghost where your tap landed, and coloured counters tally Perfect / Good / Bad until you stop.")
                        usageRow("chart.line.uptrend.xyaxis", "Practice mode", "Open it from Beat view below, or say \u{201C}\(voiceWord(.practice))\u{201D}.")
                        usageRow("play.fill", "Play", "Tap Start / Stop at the bottom.")
                        usageRow("timer", "Practice timer", "Tap Practice timer above Start, or say \u{201C}\(voiceWord(.timer5))\u{201D}. It counts down while the click plays, then stops and chimes.")
                        usageRow("mic.fill", "Voice", "Tap Listen to turn voice control on or off.")
                    } header: {
                        Text("On-screen")
                    } footer: {
                        Text("Everything here also works by voice — see the commands below.")
                    }
                    .id(helpSections[0])
                    Section("Help navigation") {
                        usageRow("questionmark.circle", "Open", "Say \u{201C}\(voiceWord(.help))\u{201D} or tap the ? button.")
                        usageRow("xmark.circle", "Close", "Say \u{201C}\(voiceWord(.close))\u{201D} / \u{201C}\(voiceWord(.done))\u{201D}, or tap Done.")
                        usageRow("hand.draw", "Scroll", "Say \u{201C}\(voiceWord(.scrollDown))\u{201D} / \u{201C}\(voiceWord(.scrollUp))\u{201D}, or swipe.")
                    }
                    Section("Playback") {
                        commandRow("\"\(voiceWord(.start))\" / \"\(voiceWord(.stop))\"", "play / pause")
                        commandRow("\"\(voiceWord(.timer5))\"", "set a practice timer")
                        commandRow("\"\(voiceWord(.timerOff))\"", "turn the timer off")
                    }
                    .id(helpSections[1])
                    Section("Tempo") {
                        commandRow("\"\(voiceWord(.faster))\" / \"\(voiceWord(.slower))\"", "±5 BPM")
                        commandRow("\"\(voiceWord(.up))\" / \"\(voiceWord(.down))\"", "±1 BPM")
                        commandRow("\"\(voiceWord(.tempo120))\"", "set value")
                        commandRow("\"\(voiceWord(.double))\" / \"\(voiceWord(.half))\"", "×2 / ÷2")
                        commandRow("\"\(voiceWord(.threeBeats))\"", "set time signature")
                    }
                    .id(helpSections[2])
                    Section("Volume") {
                        commandRow("\"\(voiceWord(.louder))\" / \"\(voiceWord(.quieter))\"", "±10%")
                        commandRow("\"\(voiceWord(.volume60))\"", "set percent")
                        commandRow("\"\(voiceWord(.mute))\"", "silence the click")
                    }
                    Section("Beat view") {
                        commandRow("\"\(voiceWord(.bounce))\" / \"\(voiceWord(.orbit))\"", "switch visualization")
                        commandRow("\"\(voiceWord(.practice))\"", "open practice mode")
                        Button {
                            openPractice()
                        } label: {
                            HStack {
                                Label("Open practice mode", systemImage: "chart.line.uptrend.xyaxis")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(cue)
                                if !pro.isPro { proLockBadge }
                            }
                        }
                        .accessibilityInputLabels(["Practice mode", "Open practice"])
                    }
                    Section("Subdivision") {
                        commandRow("\"\(voiceWord(.quarter))\"", "1/4 notes")
                        commandRow("\"\(voiceWord(.eighth))\"", "1/8 notes")
                        commandRow("\"\(voiceWord(.triplet))\"", "triplets")
                        commandRow("\"\(voiceWord(.sixteenth))\"", "1/16 notes")
                        usageRow("hand.tap", "Double-tap to open Accents",
                                 "Double-tap the subdivision card to edit the full measure — each cell cycles high → low → silent, and patterns can be saved as named presets.")
                        Button {
                            openAccents()
                        } label: {
                            HStack {
                                Label("Open accent editor", systemImage: "waveform.path")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(cue)
                                if !pro.isPro { proLockBadge }
                            }
                        }
                        .accessibilityInputLabels(["Accent editor", "Open accents", "Accents"])
                    }
                    .id(helpSections[3])
                    Section("Tuner") {
                        commandRow("\"\(voiceWord(.tune))\"", "open the tuner")
                        // The tuner has no on-screen button — VoiceOver, Switch Control and
                        // iOS Voice Control users reach it here.
                        Button {
                            openTuner()
                        } label: {
                            HStack {
                                Label("Open tuner", systemImage: "tuningfork")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(cue)
                                if !pro.isPro { proLockBadge }
                            }
                        }
                        .accessibilityInputLabels(["Tuner", "Open tuner"])
                    }
                    .id(helpSections[4])
                    Section("Scrolling") {
                        commandRow("\"\(voiceWord(.scrollDown))\" / \"\(voiceWord(.scrollUp))\"", "move this list")
                        commandRow("\"\(voiceWord(.help))\"", "list the commands you can say")
                        commandRow("\"\(voiceWord(.done))\" / \"\(voiceWord(.close))\"", "close a panel or tip")
                    }
                    .id(helpSections[5])
                }
                .onChange(of: helpIndex) { _, idx in
                    guard helpSections.indices.contains(idx) else { return }
                    withAnimation { proxy.scrollTo(helpSections[idx], anchor: .top) }
                }
            }
            .navigationTitle("Voice Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { panel = nil } label: { Label("Done", systemImage: "checkmark") }
                }
            }
        }
    }

    // MARK: Settings sheet

    /// Everything that is a setting rather than something to say: accessibility, the
    /// instrument signal, Pro (with gifts and tips) and support. Voice Commands keeps
    /// only the commands, so neither list hides the other.
    var settingsSheet: some View {
        NavigationStack {
            List {
                Section {
                    if pro.isPro {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(cue)
                                .frame(width: 22)
                            Text("Pro unlocked — thank you!")
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        Button {
                            panel = nil
                            withAnimation(.easeInOut(duration: 0.3)) { paywallFeature = .practice }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "crown.fill")
                                    .foregroundStyle(cue)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Unlock Pro")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("Practice mode · accent editor & presets · tuner")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityInputLabels(["Unlock Pro", "Pro", "Upgrade"])
                        // 새 기기 · 다시 설치한 사람이 페이월을 거치지 않고도 되찾는 길.
                        // 되찾으면 이 칸이 "Pro unlocked" 로 바뀌고, 없으면 이유가 아래에 남는다.
                        Button {
                            Task { await pro.restore() }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(cue)
                                    .frame(width: 22)
                                Text("Restore Purchases")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                                if pro.isRestoring { ProgressView() }
                            }
                        }
                        .disabled(pro.isRestoring)
                        .accessibilityHint("Restores a previous Pro purchase")
                        .accessibilityInputLabels(["Restore", "Restore purchases"])
                        if let error = pro.lastError, !pro.isRestoring {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Not My Tempo Pro")
                }
                // 개발자 응원하기(팁)는 Pro 바로 아래 제 칸에, 그 아래 선물하기.
                // 인앱 상품은 모두 설정 맨 위에 모아 둔다(심사 2.1(b): 찾을 수 있어야 한다).
                // 상품이 App Store 에서 와야 줄이 선다.
                if let tipJar = pro.tipJar {
                    Section {
                        LeeoTipJarLink<HandsFreeMetronomeSpec>(tipJar: tipJar)
                    }
                }
                // Pro 선물 보내기 · App Store 코드 넣기 (→ GiftRows)
                if let gift = pro.gift {
                    GiftRows(gift: gift, isPro: pro.isPro)
                }
                Section {
                    Toggle(isOn: $usesVoiceControl) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("I use iOS Voice Control").font(.subheadline.weight(.semibold))
                            Text("Turns off this app\u{2019}s mic so the two don\u{2019}t clash. Control it by saying \u{201C}Tap Start\u{201D}, \u{201C}Tap Faster\u{201D}, \u{201C}Tap 3 beats\u{201D}.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .tint(cue)
                    .accessibilityHint("Turns off the app's own microphone and drives controls by name")
                } header: {
                    Text("Accessibility")
                }
                // Can be switched off remotely (→ NotMyTempoFlag.instrumentSignal).
                if NoteSignalDetector.isAvailable { noteSignalSection }
                Section {
                    LeeoSupportSection<HandsFreeMetronomeSpec>()
                    // 앞으로 만들 기능 — 원본은 HandsFreeMetronomeRoadmap.swift
                    NavigationLink(LeeoRoadmapText.entry) { RoadmapScreen() }
                    Button { reopenWhatsNew() } label: {
                        Label("What\u{2019}s new", systemImage: "sparkles")
                    }
                    .accessibilityInputLabels(["What's new"])
                    Button { replayOnboarding() } label: {
                        Label("Show the introduction again", systemImage: "play.rectangle")
                    }
                    .accessibilityInputLabels(["Introduction", "Show introduction"])
                    // Other apps by the same developer.
                    LeeoFamilySettingsRow<HandsFreeMetronomeSpec>()
                } header: {
                    Text("Support")
                }
                UsageStatsSection()
                DeveloperContactSection(accent: cue)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { panel = nil } label: { Label("Done", systemImage: "checkmark") }
                }
            }
        }
    }

    // MARK: Instrument signal

    var noteSignalSection: some View {
        Section {
            Toggle(isOn: $noteSignal.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start / stop with my instrument").font(.subheadline.weight(.semibold))
                    Text(noteSignal.pattern.isEmpty
                         ? "Record a short phrase first."
                         : "Signal: \(NoteSignalDetector.phrase(noteSignal.pattern))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .tint(cue)
            .disabled(noteSignal.pattern.isEmpty || usesVoiceControl)
            if noteSignal.mode == .recording {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Listening… hold each note", systemImage: "waveform")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(cue)
                    Text(noteSignal.recorded.isEmpty
                         ? String(localized: "Play 2–5 notes, about half a second each.")
                         : NoteSignalDetector.phrase(noteSignal.recorded))
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Cancel", role: .cancel) { noteSignal.cancelRecording() }
                        Spacer()
                        Button("Save") { noteSignal.finishRecording() }
                            .disabled(noteSignal.recorded.count < NoteSignalDetector.minNotes)
                    }
                    .buttonStyle(.borderless)
                }
                .accessibilityElement(children: .contain)
            } else {
                Button {
                    if !voice.isListening { voice.toggle() }   // the signal rides on the app's mic
                    metronome.stop()   // clicks would be recorded as notes
                    noteSignal.startRecording()
                } label: {
                    Label(noteSignal.pattern.isEmpty ? "Record signal" : "Record again",
                          systemImage: "record.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(cue)
                }
                .disabled(usesVoiceControl)
                .accessibilityInputLabels(["Record signal", "Record again"])
            }
        } header: {
            Text("Instrument signal")
        } footer: {
            Text(usesVoiceControl
                 ? "Needs this app\u{2019}s mic — turn off \u{201C}I use iOS Voice Control\u{201D} to use it."
                 : "Play your phrase to start or stop the click, even mid-song. Hold each note about half a second so quick notes in your playing don\u{2019}t set it off. Works while Listen is on.")
        }
    }

    /// Small "PRO" tag shown beside launchers for still-locked features.
    var proLockBadge: some View {
        Text("PRO")
            .font(.caption2.weight(.heavy))
            .foregroundStyle(cue)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(cue.opacity(0.15)))
            .accessibilityLabel("Requires Pro")
    }

    func usageRow(_ icon: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(cue)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Practice mode (speed trainer) modal

    /// Practice mode as its own modal (opened by the "practice" command or a Help
    /// launcher) — replaces the old always-on tempo-card button.
    var trainerSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Practice mode", isOn: Binding(
                        get: { metronome.speedTrainerOn },
                        set: { metronome.setSpeedTrainer($0) }))
                        .tint(cue)
                        .accessibilityInputLabels(["Practice mode", "Practice", "Trainer"])
                    Stepper("Add \(metronome.trainerStep) BPM", value: $metronome.trainerStep, in: 1...20)
                    Stepper("Every \(metronome.trainerBars) bars", value: $metronome.trainerBars, in: 1...16)
                    Stepper("Up to \(metronome.trainerTarget) BPM", value: $metronome.trainerTarget, in: 40...260, step: 5)
                } footer: {
                    Text("Raises the tempo automatically every few bars while you play — for gradually pushing a passage faster. Stops at the target. Say \u{201C}\(voiceWord(.practice))\u{201D} anytime to open this.")
                }
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { panel = nil } label: { Label("Done", systemImage: "checkmark") }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Practice timer modal

    var timerSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Practice timer", isOn: Binding(
                        get: { metronome.practiceTimerOn },
                        set: { metronome.setPracticeTimer($0) }))
                        .tint(cue)
                        .accessibilityInputLabels(["Practice timer", "Timer"])
                    Stepper("\(metronome.practiceTimerMinutes) min", value: Binding(
                        get: { metronome.practiceTimerMinutes },
                        set: { metronome.setPracticeTimer(minutes: $0) }),
                            in: MetronomeEngine.practiceTimerRange)
                    // One row of four; two rows of two when the text is too big for that.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { quickTimerButtons([5, 10, 15, 30]) }
                        VStack(spacing: 8) {
                            HStack(spacing: 8) { quickTimerButtons([5, 10]) }
                            HStack(spacing: 8) { quickTimerButtons([15, 30]) }
                        }
                    }
                } footer: {
                    Text("Counts down while the click plays and pauses when you stop. When time is up the metronome stops and chimes. Say \u{201C}\(voiceWord(.timer5))\u{201D} or \u{201C}\(voiceWord(.timerOff))\u{201D} anytime.")
                        .font(.body)
                }
                if metronome.practiceTimerOn {
                    Section {
                        HStack {
                            Text("Time left")
                            Spacer()
                            Text(timerText(metronome.practiceTimerRemaining))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        Button("Reset timer") { metronome.resetPracticeTimer() }
                            .disabled(metronome.practiceTimerRemaining == metronome.practiceTimerMinutes * 60)
                    }
                }
            }
            .navigationTitle("Practice timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { panel = nil } label: { Label("Done", systemImage: "checkmark") }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Quick-pick minute buttons for the practice timer.
    func quickTimerButtons(_ minutes: [Int]) -> some View {
        ForEach(minutes, id: \.self) { m in
            let selected = metronome.practiceTimerOn && metronome.practiceTimerMinutes == m
            Button {
                metronome.setPracticeTimer(minutes: m)
                haptic.impactOccurred(intensity: 0.5)
            } label: {
                Text("\(m) min")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(selected ? ink(on: cue) : cue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? cue : cue.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        }
    }

    // MARK: Tuner page — slides in from the right, covering the whole screen

    /// Deliberately NOT a NavigationStack: inserted mid-animation, a nav stack
    /// paints an empty white surface until its bar resolves, so the slide-in
    /// would flash blank. A plain VStack with a hand-rolled header renders its
    /// content on the very first frame of the transition.
    var tunerScreen: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Tuner").font(.headline)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Button { closeTuner() } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.body.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel("Back to metronome")
                    .accessibilityInputLabels(["Back", "Close", "Done"])
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            VStack(spacing: 28) {
                Spacer()
                Text(tuner.noteName)
                    .font(.system(size: noteFontSize, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(inTune ? Color.green : .primary)
                    .accessibilityLabel("Note")
                    .accessibilityValue(tunerAccessibilityValue)
                centsMeter
                    .accessibilityHidden(true)   // visual meter; pitch is announced on the note above
                // Differentiate Without Color: a shape cue so "in tune" doesn't rely on green alone.
                if differentiateWithoutColor, tuner.frequency > 0 {
                    Image(systemName: inTune ? "checkmark.circle.fill"
                                             : (tuner.cents > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill"))
                        .font(.title)
                        .foregroundStyle(inTune ? Color.green : cue)
                        .accessibilityHidden(true)   // pitch already announced on the note
                }
                Text(tuner.frequency > 0 ? frequencyText(tuner.frequency) : String(localized: "Play a note…"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                referenceControl
                Spacer()
                Text("Say \u{201C}\(voiceWord(.close))\u{201D} to exit")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        // Mirror the system back-swipe: a rightward drag slides the page away.
        .gesture(DragGesture(minimumDistance: 25).onEnded { value in
            if value.translation.width > 80 { closeTuner() }
        })
    }

    /// A4 calibration: 440 Hz by default, nudged 1 Hz at a time (430–450) for
    /// orchestras at 442 or players who tune to 432.
    var referenceControl: some View {
        let range = TunerEngine.referenceRange
        return HStack(spacing: 16) {
            Button { tuner.referenceA -= 1 } label: {
                Image(systemName: "minus.circle.fill").font(.title2)
            }
            .disabled(tuner.referenceA <= range.lowerBound)
            .accessibilityHidden(true)
            Text("A4 = \(tuner.referenceA) Hz")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 120)
                .onTapGesture(count: 2) { tuner.referenceA = 440 }
            Button { tuner.referenceA += 1 } label: {
                Image(systemName: "plus.circle.fill").font(.title2)
            }
            .disabled(tuner.referenceA >= range.upperBound)
            .accessibilityHidden(true)
        }
        .tint(cue)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reference pitch")
        .accessibilityValue("A4 = \(tuner.referenceA) Hz")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: tuner.referenceA += 1
            case .decrement: tuner.referenceA -= 1
            @unknown default: break
            }
        }
    }

    /// Slide the tuner page back out to the right (the inverse of its entry).
    func closeTuner() {
        if panel == .tuner { present(nil) }
    }

    /// "440.0 Hz" / "440,0 Hz" — the decimal mark follows the user's region.
    func frequencyText(_ hz: Double) -> String {
        "\(hz.formatted(.number.precision(.fractionLength(1)).grouping(.never))) Hz"
    }

    var inTune: Bool { tuner.frequency > 0 && abs(tuner.cents) <= tuneTolerance }

    /// Spoken pitch summary for VoiceOver, replacing the visual cents meter.
    var tunerAccessibilityValue: String {
        guard tuner.frequency > 0 else { return String(localized: "No note detected, play a note") }
        if inTune { return String(localized: "\(tuner.noteName), in tune") }
        let cents = Int(tuner.cents.rounded())
        return cents > 0
            ? String(localized: "\(tuner.noteName), \(abs(cents)) cents sharp")
            : String(localized: "\(tuner.noteName), \(abs(cents)) cents flat")
    }

    var centsMeter: some View {
        let cents = max(-50, min(50, tuner.cents))
        return GeometryReader { geo in
            let w = geo.size.width
            let cy = geo.size.height / 2
            let half = w / 2 - 12                              // travel for the indicator
            let zoneHalf = CGFloat(tuneTolerance / 50) * half  // green acceptance zone
            ZStack {
                Capsule().fill(Color(.systemGray5)).frame(height: 8)
                // Acceptance zone — "in tune" band with start/end markers.
                Capsule().fill(Color.green.opacity(0.28))
                    .frame(width: zoneHalf * 2, height: 16)
                    .position(x: w / 2, y: cy)
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Rectangle().fill(Color.green)
                        .frame(width: 2.5, height: 20)
                        .position(x: w / 2 + CGFloat(side) * zoneHalf, y: cy)
                }
                // Exact-pitch hairline at the centre.
                Rectangle().fill(Color.secondary.opacity(0.45))
                    .frame(width: 1, height: 12)
                    .position(x: w / 2, y: cy)
                // Moving indicator.
                if tuner.frequency > 0 {
                    Circle().fill(inTune ? Color.green : cue)
                        .frame(width: 22, height: 22)
                        .position(x: w / 2 + CGFloat(cents / 50) * half, y: cy)
                        .animation(.easeOut(duration: 0.22), value: tuner.cents)
                }
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 36)
    }

    /// `phrase` is what the user says to the app's English recognizer, so it is
    /// shown verbatim in every language; only the effect is translated.
    func commandRow(_ phrase: String, _ effect: LocalizedStringKey) -> some View {
        HStack {
            Text(phrase).fontWeight(.medium)
            Spacer()
            Text(effect).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
