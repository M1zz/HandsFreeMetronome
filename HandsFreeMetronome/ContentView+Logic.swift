import SwiftUI
import UIKit
import AppIntents
import TipKit
import LeeoKit

/// Small shared pieces and the behaviour behind the screen.
/// Part of `ContentView`, split by area so an edit recompiles one small file.
extension ContentView {
    // MARK: Small pieces

    func stepButton(systemName: String, delta: Int) -> some View {
        Button {
            metronome.nudge(delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: stepIconSize))
                .foregroundStyle(cue)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta < 0 ? "Decrease tempo" : "Increase tempo")
        .accessibilityInputLabels(delta < 0
            ? ["Decrease tempo", "Slower", "Minus"]
            : ["Increase tempo", "Faster", "Plus"])
    }

    var card: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
    }

    var bpmBinding: Binding<Double> {
        // Int(Double) traps on NaN/infinity, so gate the conversion and go
        // through setTempo, which clamps to the supported BPM range.
        // Each BPM step ticks under the finger; round tens land a firmer bump,
        // so the slider can be set by feel without looking.
        Binding(get: { Double(metronome.bpm) },
                set: {
                    guard $0.isFinite else { return }
                    let old = metronome.bpm
                    metronome.setTempo(Int($0))
                    let new = metronome.bpm
                    guard new != old else { return }
                    if new % 10 == 0 {
                        haptic.impactOccurred(intensity: 0.8)
                    } else {
                        sliderHaptic.selectionChanged()
                    }
                })
    }

    /// Tap-tempo: tapping the big BPM number in rhythm sets the tempo from the
    /// average gap between taps. A long pause (>2s) starts a fresh measurement.
    /// Uses the monotonic uptime clock so it's immune to wall-clock changes.
    func tapTempo() {
        let now = ProcessInfo.processInfo.systemUptime
        if let last = tapTimes.last, now - last > 2.0 { tapTimes.removeAll() }
        tapTimes.append(now)
        if tapTimes.count > 6 { tapTimes.removeFirst(tapTimes.count - 6) }
        haptic.impactOccurred(intensity: 0.5)
        guard tapTimes.count >= 2 else { return }
        let gaps = zip(tapTimes.dropFirst(), tapTimes).map { $0 - $1 }
        let avg = gaps.reduce(0, +) / Double(gaps.count)
        let bpm = 60.0 / max(avg, 0.001)          // ≥1 ms gap — Int() must never see inf/NaN
        guard bpm.isFinite else { return }
        metronome.setTempo(Int(bpm.rounded()))
    }

    // MARK: Logic

    var micMessage: String {
        switch voice.status {
        case .idle: return String(localized: "Tap Listen to control by voice")
        case .listening:
            return voice.lastHeard.isEmpty
                ? String(localized: "Say \"start\", \"faster\", or \"help\"")
                : String(localized: "Heard: \(voice.lastHeard)")
        case .denied: return String(localized: "Mic/Speech blocked — enable in Settings")
        case .unavailable: return String(localized: "Speech recognition unavailable here")
        }
    }

    func wireUp() {
        metronome.onBeat = { beat in pulseBeat(beat) }
        voice.onCommand = { handle($0) }
        voice.onAudioBuffer = { buffer in
            tuner.process(buffer)
            noteSignal.process(buffer)
        }
        noteSignal.onTrigger = {
            handle(metronome.isPlaying ? .stop : .start)
            voice.keepAlive()   // playing the signal counts as activity for auto-mute
        }
        haptic.prepare()
    }

    #if DEBUG
    func prepareScreenshot(_ scene: String) {
        Tips.hideAllTipsForTesting()
        hintDismissed = true
        metronome.setBeatsPerMeasure(4)
        metronome.setTempo(120)
        metronome.setSubdivision(1)
        tempoAsNumber = false
        vizModeRaw = BeatVizMode.bounce.rawValue
        switch scene {
        case "orbit": vizModeRaw = BeatVizMode.orbit.rawValue
        case "count": vizModeRaw = BeatVizMode.sweep.rawValue
        case "accents": metronome.setSubdivision(4)
        case "main":
            metronome.setTempo(132)
            metronome.setSubdivision(2)
        case "number":
            metronome.setTempo(88)
            metronome.setSubdivision(4)
            tempoAsNumber = true
        default: break
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            switch scene {
            case "playing", "orbit", "count": metronome.start()
            case "timer": metronome.setPracticeTimer(minutes: 15); metronome.start()
            case "voice": showHelp()
            case "commands": showCommands = true
            case "settings": showSettings = true
            case "paywall": paywallFeature = .tuner
            case "accents":
                metronome.setLevelsForScreenshot([2, 1, 2, 1,  2, 0, 1, 1,  2, 1, 2, 1,  2, 0, 1, 2])
                // Show saved presets, not the empty state — genre names read the
                // same in every store language.
                if metronome.accentPresets.isEmpty {
                    metronome.saveAccentPreset(named: "Bossa Nova")
                    metronome.saveAccentPreset(named: "Samba")
                }
                showAccents = true
            default: break
            }
        }
    }
    #endif

    func openTuner() {
        guard requirePro(.tuner) else { return }
        metronome.stop()        // clicks would corrupt pitch detection
        if !voice.isListening { voice.toggle() }   // the tuner hears through the app's mic
        showCommands = false
        showSettings = false
        showAccents = false
        tuner.start()
        withAnimation(tunerPageAnimation) { showTuner = true }
        TunerTip().invalidate(reason: .actionPerformed)
    }

    /// The freemium gate. Pro features funnel through here from every entry
    /// point — buttons, voice commands, double-taps, VoiceOver actions — so the
    /// check lives in exactly one place. Locked → swap whatever was opening for
    /// the paywall, led by the feature that was just reached for.
    func requirePro(_ feature: ProFeature) -> Bool {
        if pro.allows(feature) { return true }
        closePanels()
        withAnimation(.easeInOut(duration: 0.3)) { paywallFeature = feature }
        return false
    }

    /// "close" also dismisses the tip on screen — a hands-free app can't make you
    /// reach for a tip's ✕. Only one popover shows at a time and the tour is set to
    /// show the next stop immediately, so closing one used to pop the next right
    /// back up in the same spot (it looked like "close" did nothing). Now the tip
    /// that's up is retired for good, and the rest wait until the next launch.
    func dismissVisibleTips() {
        // The tour's current stop wins the screen when it's eligible; otherwise
        // it's one of the standalone first-run tips. Retire just that one, so a
        // tip that was only queued is never lost unseen.
        let candidates: [any Tip] = [featureTips.currentTip, MicListeningTip(), VoiceControlTip(), HelpVoiceTip()]
            .compactMap { $0 }
        candidates.first { $0.shouldDisplay }?.invalidate(reason: .tipClosed)
        AppTips.snoozed = true
    }

    func closePanels() {
        showCommands = false
        showSettings = false
        closeTuner()            // slides the page out; onChange stops the engine
        showTrainer = false
        showTimer = false
        showAccents = false
        // "close" backs out of the paywall and the What's-new card too
        withAnimation(.easeInOut(duration: 0.3)) { paywallFeature = nil }
        if showWhatsNew { closeWhatsNew() }
        if showHelpMarks { dismissHelpMarks() }
    }

    func restartMuteCountdown() {
        guard voice.isListening else { return }
        muteProgress = 1
        DispatchQueue.main.async {
            guard voice.isListening else { return }
            withAnimation(.linear(duration: voice.autoMuteAfter)) { muteProgress = 0 }
        }
    }

    /// Flash the just-recognized command on the Mute button, then settle back.
    func flashCommandBriefly() {
        flashToken += 1
        let token = flashToken
        withAnimation(.easeOut(duration: 0.15)) { flashingCommand = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard flashToken == token else { return }   // a newer command took over
            withAnimation(.easeInOut(duration: 0.25)) { flashingCommand = false }
        }
    }

    func handle(_ cmd: VoiceController.Command) {
        lastCommandText = commandLabel(cmd)
        flashCommandBriefly()         // show it on the Mute button for a moment
        // "help" just opens the overlay — no confirmation chime (it was stacking up).
        if cmd != .help { FeedbackSound.shared.play() }
        switch cmd {
        case .start: metronome.start()
        case .stop: metronome.stop()
        case .faster: metronome.nudge(5)
        case .slower: metronome.nudge(-5)
        case .up: metronome.nudge(1)
        case .down: metronome.nudge(-1)   // never closes panels (was too easy to trigger by noise)
        case .double: metronome.doubleTempo()
        case .half: metronome.halfTempo()
        case .setTempo(let v): metronome.setTempo(v)
        case .setSubdivision(let v): metronome.setSubdivision(v)
        case .setBeats(let n): metronome.setBeatsPerMeasure(n)
        case .volumeUp: metronome.setVolume(metronome.volume + 0.1)
        case .volumeDown: metronome.setVolume(metronome.volume - 0.1)
        case .mute: metronome.setVolume(0)
        case .setVolume(let p): metronome.setVolume(Float(p) / 100)
        case .toggleView:
            vizModeRaw = vizMode.next.rawValue
            VizModeTip().invalidate(reason: .actionPerformed)
        case .bounceView:
            vizModeRaw = BeatVizMode.bounce.rawValue
            VizModeTip().invalidate(reason: .actionPerformed)
        case .orbitView:
            vizModeRaw = BeatVizMode.orbit.rawValue
            VizModeTip().invalidate(reason: .actionPerformed)
        case .help: showHelp()
        case .tuner: openTuner()
        case .dismiss:
            dismissVisibleTips()
            closePanels()
        case .scrollUp: helpIndex = max(0, helpIndex - 1)
        case .scrollDown: helpIndex = min(helpSections.count - 1, helpIndex + 1)
        case .practice: openPractice()
        case .timer: openTimer()
        case .setTimer(let m): metronome.setPracticeTimer(minutes: m)
        case .timerOff: metronome.setPracticeTimer(false)
        }
    }

    /// The practice timer is part of the free core — no Pro gate.
    func openTimer() {
        showCommands = false
        showSettings = false
        withAnimation(tunerPageAnimation) { showTuner = false }
        showTrainer = false
        showAccents = false
        showTimer = true
    }

    func openPractice() {
        guard requirePro(.practice) else { return }
        showCommands = false
        showSettings = false
        withAnimation(tunerPageAnimation) { showTuner = false }
        showAccents = false
        showTimer = false
        showTrainer = true
        PracticeTip().invalidate(reason: .actionPerformed)
    }

    func openAccents() {
        guard requirePro(.accents) else { return }
        showCommands = false
        showSettings = false
        withAnimation(tunerPageAnimation) { showTuner = false }
        showTrainer = false
        showTimer = false
        showAccents = true
        AccentGridTip().invalidate(reason: .actionPerformed)
    }

    /// "help" pops up the list of commands you can say right now.
    func showHelp() {
        withAnimation(tunerPageAnimation) { showTuner = false }
        showTrainer = false
        showTimer = false
        withAnimation(.easeOut(duration: 0.2)) { showHelpMarks = true }
        HelpVoiceTip().invalidate(reason: .actionPerformed)
    }

    func dismissHelpMarks() {
        withAnimation(.easeInOut(duration: 0.2)) { showHelpMarks = false }
    }

    func commandLabel(_ cmd: VoiceController.Command) -> String {
        switch cmd {
        case .start: return String(localized: "▶ Start")
        case .stop: return String(localized: "■ Stop")
        case .faster: return String(localized: "Faster +5")
        case .slower: return String(localized: "Slower −5")
        case .up: return String(localized: "Up +1")
        case .down: return String(localized: "Down −1")
        case .double: return String(localized: "Double ×2")
        case .half: return String(localized: "Half ÷2")
        case .setTempo(let v): return String(localized: "Tempo \(v)")
        case .setSubdivision(let v): return MetronomeEngine.subdivisionName(for: v)
        case .setBeats(let n): return String(localized: "\(n) beats")
        case .volumeUp: return String(localized: "Volume up")
        case .volumeDown: return String(localized: "Volume down")
        case .mute: return String(localized: "Mute")
        case .setVolume(let p): return String(localized: "Volume \(p)%")
        case .toggleView: return String(localized: "Switch view")
        case .bounceView: return String(localized: "Bounce view")
        case .orbitView: return String(localized: "Orbit view")
        case .help: return String(localized: "Help")
        case .tuner: return String(localized: "Tuner")
        case .dismiss: return String(localized: "Close")
        case .scrollUp: return String(localized: "Scroll up")
        case .scrollDown: return String(localized: "Scroll down")
        case .practice: return String(localized: "Practice")
        case .timer: return String(localized: "Timer")
        case .setTimer(let m): return String(localized: "Timer \(m) min")
        case .timerOff: return String(localized: "Timer off")
        }
    }

    func pulseBeat(_ beat: Int) {
        currentBeat = beat
        beatAnchor = Date()          // anchor the smooth viz interpolation to this beat
        haptic.impactOccurred(intensity: beat == 0 ? 1.0 : 0.6)
        // Reduce Motion: skip the bounce AND the flash — the lit dot still marks the beat.
        guard !reduceMotion else { return }
        #if DEBUG
        // A screenshot must not freeze the beat flash mid-fade (the whole page turns pink).
        if ProcessInfo.processInfo.arguments.contains("-shot") { return }
        #endif
        flashIsDownbeat = beat == 0
        flashOpacity = beat == 0 ? 0.18 : 0.08     // downbeat pops, the rest whisper
        withAnimation(.easeOut(duration: 0.30)) { flashOpacity = 0 }
        withAnimation(.easeOut(duration: 0.06)) { beatScale = 1.1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            withAnimation(.easeIn(duration: 0.1)) { beatScale = 1.0 }
        }
    }
}
