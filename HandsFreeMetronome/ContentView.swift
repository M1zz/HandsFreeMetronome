import SwiftUI
import UIKit
import TipKit

struct ContentView: View {
    @StateObject private var metronome = MetronomeEngine()
    @StateObject private var voice = VoiceController()
    @StateObject private var detector = TempoDetector()
    @StateObject private var tuner = TunerEngine()

    @State private var beatScale: CGFloat = 1.0
    @State private var currentBeat = -1   // which beat (0-based) is sounding now
    @State private var showCommands = false
    @State private var showTuner = false
    @State private var hintDismissed = false   // hide "tap dots" after first tap/start
    @State private var didAutoStart = false    // auto-enable listening once on launch
    @State private var muteProgress: CGFloat = 1   // Listen-button countdown ring (1→0)
    @State private var lastCommandText = ""     // last recognized voice command
    @State private var helpIndex = 0            // voice-driven scroll position in Help
    private let helpSections = ["howto", "playback", "tempo", "subdivision", "tuner", "scrolling"]

    // Spoken once, the first time a VoiceOver user opens the app.
    @AppStorage("didIntroduceVoiceOver") private var didIntroduceVoiceOver = false

    // The user relies on iOS system Voice Control. There is no public API to detect
    // this, so it is a user-declared setting (toggled in the Voice Commands sheet).
    // When on, we keep our OWN mic off to avoid two speech recognizers fighting over
    // the input — the user drives every control by its name ("Tap Start", "Tap Faster").
    @AppStorage("usesVoiceControl") private var usesVoiceControl = false

    // Landscape on iPhone reports a compact height → switch to a two-column layout.
    @Environment(\.verticalSizeClass) private var vSizeClass
    // Accessibility preferences we honour throughout the UI.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    // Assistive Access (iOS 18+): when the app runs inside the simplified system
    // experience for people with cognitive disabilities, we show a distilled UI.
    @Environment(\.accessibilityAssistiveAccessEnabled) private var assistiveAccess

    // Dynamic Type: scale the big fixed-size displays with the user's text setting.
    @ScaledMetric(relativeTo: .largeTitle) private var bpmFontSize: CGFloat = 52
    @ScaledMetric(relativeTo: .largeTitle) private var noteFontSize: CGFloat = 96
    @ScaledMetric(relativeTo: .title) private var stepIconSize: CGFloat = 30

    private let brass = Color(red: 0.80, green: 0.62, blue: 0.24)
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let maxBeats = 8
    private let tuneTolerance: Double = 10   // ± cents counted as "in tune"

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if assistiveAccess {
                assistiveAccessLayout
            } else if vSizeClass == .compact {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
        // Support Dynamic Type, but cap growth so the single-screen layout holds.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .fullScreenCover(isPresented: $showCommands) { commandsSheet }
        .sheet(isPresented: $showTuner, onDismiss: { tuner.stop() }) { tunerSheet }
        .onChange(of: detector.state) { newState in
            if case .result(let bpm) = newState { metronome.setTempo(bpm) }
        }
        .onChange(of: metronome.isPlaying) { playing in
            if playing { withAnimation(.easeInOut(duration: 0.4)) { hintDismissed = true } }
        }
        .onChange(of: voice.activityToken) { _ in restartMuteCountdown() }
        .onChange(of: voice.isListening) { listening in
            if !listening { muteProgress = 1 }
        }
        .onAppear {
            wireUp()
            syncTipState()
            // Listen by default — UNLESS the user relies on iOS Voice Control, in
            // which case our own mic would fight the system recognizer. They drive
            // the app by control name ("Tap Start") instead.
            if !didAutoStart {
                didAutoStart = true
                if !usesVoiceControl && !voice.isListening { voice.toggle() }
            }
        }
        // Turning Voice Control mode on/off flips whether we hold the mic.
        .onChange(of: usesVoiceControl) { on in
            AppTips.usesVoiceControl = on
            if on {
                voice.stop()                     // release the mic for the system recognizer
            } else if !voice.isListening {
                voice.toggle()                   // resume our own listening
            }
        }
        // Let the "tap dots" hint fade away on its own if the user never touches it.
        .task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !hintDismissed {
                withAnimation(.easeInOut(duration: 0.8)) { hintDismissed = true }
            }
        }
        // First time a VoiceOver user opens the app, spell out how it works.
        // Delayed so it follows VoiceOver's own initial reading of the screen.
        .task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            introduceVoiceOverIfNeeded()
        }
        // Also cover the case where VoiceOver is switched on right after launch.
        .onReceive(NotificationCenter.default.publisher(
            for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            syncTipState()
            introduceVoiceOverIfNeeded()
        }
    }

    /// Feed the current accessibility + mode state into TipKit's rule parameters so
    /// the right first-run tip (mic vs. Voice Control) is eligible.
    private func syncTipState() {
        AppTips.usesVoiceControl = usesVoiceControl
        AppTips.voiceOverRunning = UIAccessibility.isVoiceOverRunning
    }

    /// One-time spoken orientation for VoiceOver users: this is a voice-driven
    /// metronome whose mic is already listening, plus the key commands and the
    /// reassurance that every control also works with VoiceOver gestures.
    private func introduceVoiceOverIfNeeded() {
        guard UIAccessibility.isVoiceOverRunning, !didIntroduceVoiceOver else { return }
        didIntroduceVoiceOver = true
        // In Voice Control mode our own mic is off, so orient the user toward the
        // "Tap …" command names rather than the app's spoken words.
        let text = usesVoiceControl ? """
        Not My Tempo, a hands-free metronome and tuner. \
        The app's own microphone is off so it doesn't clash with Voice Control. \
        Say Tap Start or Tap Stop to play, Tap Faster or Tap Slower to change the tempo, \
        or Tap Tuner to check pitch. Every control also works with VoiceOver gestures.
        """ : """
        Not My Tempo, a hands-free metronome and tuner. \
        The microphone is already listening, so you can control it by voice. \
        Say start or stop to play, faster or slower to change the tempo, \
        tune to open the tuner, or help to hear every command. \
        Every control also works with VoiceOver gestures.
        """
        // High priority so VoiceOver doesn't drop it while reading the screen.
        let announcement = NSAttributedString(
            string: text,
            attributes: [.accessibilitySpeechAnnouncementPriority: UIAccessibilityPriority.high]
        )
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    // MARK: Layouts

    /// Portrait: a single vertical stack, transport pinned to the bottom.
    private var portraitLayout: some View {
        VStack(spacing: 10) {
            beatDots                 // tap to set time signature; dots bounce on the beat
            tempoCard
            subdivisionCard
            voiceCard
            Spacer(minLength: 0)
            transportBar
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Landscape (compact height): two columns so everything stays on one screen.
    /// Left holds the beats + tempo; right holds subdivision, voice status, transport.
    private var landscapeLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 10) {
                beatDots             // tap to set time signature; dots bounce on the beat
                tempoCard
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 10) {
                subdivisionCard
                voiceCard
                Spacer(minLength: 0)
                transportBar
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Assistive Access: distilled to the essentials — see the tempo, change it,
    /// and start or stop. Apple's guidance is to reduce complexity and use large,
    /// clear controls; standard SwiftUI buttons here automatically pick up
    /// Assistive Access's prominent styling. Voice control still runs in the
    /// background, so the whole app remains hands-free in this mode too.
    private var assistiveAccessLayout: some View {
        VStack(spacing: 22) {
            beatDots                     // shared beat indicator — already accessible

            VStack(spacing: 2) {
                Text("\(metronome.bpm)")
                    .font(.system(size: bpmFontSize * 1.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(beatScale > 1.0 ? brass : Color.primary)
                    .accessibilityLabel("Tempo")
                    .accessibilityValue("\(metronome.bpm) beats per minute")
                Text("BPM")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 14) {
                aaButton("Slower", icon: "minus", tint: brass) { metronome.nudge(-5) }
                aaButton("Faster", icon: "plus", tint: brass) { metronome.nudge(5) }
            }

            aaButton(metronome.isPlaying ? "Stop" : "Start",
                     icon: metronome.isPlaying ? "stop.fill" : "play.fill",
                     tint: metronome.isPlaying ? .red : brass) { metronome.toggle() }

            Spacer(minLength: 0)
        }
        .padding(20)
    }

    /// A large, full-width button for the Assistive Access layout.
    private func aaButton(_ title: String, icon: String, tint: Color,
                          action: @escaping () -> Void) -> some View {
        Button {
            action()
            haptic.impactOccurred(intensity: 0.6)
        } label: {
            Label(title, systemImage: icon)
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(tint)
        .accessibilityLabel(title == "Start" ? "Start metronome"
                            : title == "Stop" ? "Stop metronome" : title)
    }

    // MARK: Beat dots — tap to set the time signature; light up on each beat

    private var beatDots: some View {
        let beats = metronome.beatsPerMeasure
        let playing = metronome.isPlaying
        // While playing, collapse to just the active beats; when stopped, show the
        // full set of slots so the time signature can be edited again.
        let shown = playing ? beats : maxBeats
        let rows = dotRows(total: shown)
        return VStack(spacing: 12) {       // the dots themselves — centered in the card
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 12) {
                    ForEach(rows[r], id: \.self) { i in
                        beatDot(i, active: i < beats)
                    }
                }
            }
        }
        .frame(height: 80)                 // fixed area (with headroom for the bounce)
        .animation(.easeInOut(duration: 0.25), value: shown)  // dots stay vertically centered
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(card)
        // Hint sits at the bottom edge as an overlay so it never nudges the dots
        // off the card's vertical centre.
        .overlay(alignment: .bottom) {
            Text("\(beats)/4  ·  tap dots to set beats")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(!hintDismissed && !playing ? 1 : 0)
                .accessibilityHidden(hintDismissed || playing)   // don't read the invisible hint
                .padding(.bottom, 6)
        }
    }

    /// One row up to 6 dots; 7+ split into two balanced rows (8 → 4 + 4).
    private func dotRows(total: Int) -> [[Int]] {
        let all = Array(0..<total)
        guard total > 6 else { return [all] }
        let first = (total + 1) / 2
        return [Array(all[0..<first]), Array(all[first...])]
    }

    private func beatDot(_ i: Int, active: Bool) -> some View {
        let sounding = isActive(i)
        // While playing, the resting dots sit low and the sounding one rises to the
        // top — so the wave swings through the full height (top ↔ bottom), not just
        // upward. Idle (or Reduce Motion): centred, no motion.
        let lift: CGFloat = (reduceMotion || !metronome.isPlaying) ? 0 : (sounding ? -20 : 20)
        return Circle()
            .fill(active ? dotFill(i) : Color.clear)
            .overlay(Circle().strokeBorder(active ? .clear : Color(.systemGray3), lineWidth: 1.5))
            .frame(width: 24, height: 24)
            // As the beat advances the crest travels across the row → stadium wave (파도타기).
            .offset(y: lift)
            .scaleEffect(sounding && !reduceMotion ? 1.3 : 1.0)   // Reduce Motion: no grow, brightness still marks the beat
            .shadow(color: sounding ? dotFill(i).opacity(0.6) : .clear, radius: sounding ? 9 : 0)
            // Linear over exactly one beat → constant speed, no spring accel/bounce.
            // Each beat one dot rises while its predecessor falls, so the crest
            // glides across at a steady pace (a constant-velocity 파도타기).
            .animation(.linear(duration: 60.0 / Double(metronome.bpm)), value: currentBeat)
            .animation(.easeOut(duration: 0.2), value: metronome.beatsPerMeasure)
            .animation(.easeInOut(duration: 0.25), value: metronome.isPlaying)  // settle on start/stop
            .contentShape(Circle())
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            .onTapGesture {
                metronome.setBeatsPerMeasure(i + 1)
                haptic.impactOccurred(intensity: 0.5)
                withAnimation(.easeInOut(duration: 0.4)) { hintDismissed = true }
            }
            // Voice Control: say "Tap N beats" to set the time signature.
            .accessibilityLabel("\(i + 1) \(i == 0 ? "beat" : "beats")")
            .accessibilityInputLabels(["\(i + 1) beats", "Beat \(i + 1)", "\(i + 1)"])
            // VoiceOver: announce as a button, mark the current time signature selected.
            .accessibilityAddTraits(i + 1 == metronome.beatsPerMeasure ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint("Sets \(i + 1)/4 time")
    }

    private func isActive(_ i: Int) -> Bool { metronome.isPlaying && i == currentBeat }

    /// Fill for an active beat: the currently sounding one is bright
    /// (downbeat red, others brass); the rest are a dim brass.
    private func dotFill(_ i: Int) -> Color {
        guard isActive(i) else { return brass.opacity(0.35) }
        return i == 0 ? .red : brass
    }

    // MARK: Tempo

    private var tempoCard: some View {
        VStack(spacing: 10) {
            Text("\(metronome.bpm)")
                .font(.system(size: bpmFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(beatScale > 1.0 ? brass : Color.primary)
                .scaleEffect(beatScale)
                .accessibilityLabel("Tempo")
                .accessibilityValue("\(metronome.bpm) beats per minute")
            Text(tempoSubtitle)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(detector.isRunning || metronome.speedTrainerOn ? brass : .secondary)
            HStack(spacing: 16) {
                stepButton(systemName: "minus.circle.fill", delta: -1)
                Slider(value: bpmBinding, in: 30...260, step: 1)
                    .tint(brass)
                    .accessibilityLabel("Tempo")
                    .accessibilityValue("\(metronome.bpm) BPM")
                    .accessibilityInputLabels(["Tempo", "Tempo slider", "BPM"])
                stepButton(systemName: "plus.circle.fill", delta: 1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(card)
        .overlay(alignment: .topTrailing) { detectButton.padding(12) }
        .overlay(alignment: .topLeading) { trainerButton.padding(12) }
    }

    /// Toggle the speed trainer (auto tempo climb). Configured in the Help sheet.
    private var trainerButton: some View {
        Button {
            metronome.toggleSpeedTrainer()
            haptic.impactOccurred(intensity: 0.5)
        } label: {
            Image(systemName: metronome.speedTrainerOn
                  ? "chart.line.uptrend.xyaxis.circle.fill"
                  : "chart.line.uptrend.xyaxis.circle")
                .font(.title3)
                .foregroundStyle(metronome.speedTrainerOn ? brass : .secondary)
        }
        .accessibilityLabel(metronome.speedTrainerOn ? "Stop speed trainer" : "Start speed trainer")
        .accessibilityInputLabels(["Speed trainer", "Trainer"])
    }

    private var detectButton: some View {
        Button {
            toggleDetect()
        } label: {
            Image(systemName: detector.isRunning ? "stop.circle.fill" : "waveform.badge.magnifyingglass")
                .font(.title3)
                .foregroundStyle(detector.isRunning ? .red : brass)
        }
        .accessibilityLabel(detector.isRunning ? "Stop tempo detection" : "Detect tempo from music")
        .accessibilityInputLabels(detector.isRunning
            ? ["Stop detection", "Stop detecting"]
            : ["Detect tempo", "Detect", "Detect tempo from music"])
    }

    private var tempoSubtitle: String {
        // Trainer status takes over the subtitle when it's running (and we're not
        // mid tempo-detection).
        if metronome.speedTrainerOn, case .idle = detector.state {
            return "Speed trainer · +\(metronome.trainerStep) every \(metronome.trainerBars) bars → \(metronome.trainerTarget)"
        }
        switch detector.state {
        case .listening: return "Listening to music… \(Int(detector.progress * 100))%"
        case .result(let b): return "Detected \(b) BPM"
        case .failed: return "Couldn't detect — try again"
        case .denied: return "Mic blocked — enable in Settings"
        case .idle: return "\(MetronomeEngine.tempoName(for: metronome.bpm)) · BPM"
        }
    }

    // MARK: Subdivision — tap a ring that shows how the beat is divided

    private var subdivisionCard: some View {
        let options: [(seg: Int, value: Int, label: String, voice: String)] =
            [(1, 1, "1/4", "Quarter"), (2, 2, "1/8", "Eighth"),
             (3, 3, "Trip", "Triplet"), (4, 4, "1/16", "Sixteenth")]
        return HStack(spacing: 8) {
            ForEach(options, id: \.value) { opt in
                let selected = metronome.subdivision == opt.value
                Button {
                    metronome.setSubdivision(opt.value)
                    haptic.impactOccurred(intensity: 0.5)
                } label: {
                    VStack(spacing: 6) {
                        SegmentedRing(segments: opt.seg,
                                      color: selected ? brass : Color(.systemGray3))
                            .frame(width: 34, height: 34)
                        Text(opt.label)
                            .font(.caption2.weight(selected ? .bold : .regular))
                            .foregroundStyle(selected ? Color.primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(selected ? brass.opacity(0.14) : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(opt.voice) notes")
                .accessibilityInputLabels(["\(opt.voice) notes", opt.voice, opt.label])
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(card)
    }

    // MARK: Voice status + help

    private var voiceCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(voice.isListening ? "Listening" : "Voice control off")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(voice.isListening ? brass : .primary)
                if voice.isListening {
                    // Always-on live feedback (waveform reacts to your voice) +
                    // the command that was recognized.
                    HStack(spacing: 12) {
                        voiceWaveform.frame(width: 64, height: 20)
                        Text(lastCommandText.isEmpty ? "Say a command…" : lastCommandText)
                            .font(.subheadline.weight(lastCommandText.isEmpty ? .regular : .semibold))
                            .foregroundStyle(lastCommandText.isEmpty ? .secondary : brass)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                } else {
                    Text(micMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Button {
                showHelp()
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Voice commands")
            .accessibilityInputLabels(["Voice commands", "Help", "Commands"])
            .popoverTip(HelpVoiceTip())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private var voiceWaveform: some View {
        let level = CGFloat(voice.audioLevel)
        let factors: [CGFloat] = [0.45, 0.8, 1.0, 0.6, 0.95, 0.55, 0.85]
        return HStack(alignment: .center, spacing: 4) {
            ForEach(factors.indices, id: \.self) { i in
                Capsule()
                    .fill(brass)
                    .frame(width: 4, height: max(4, 4 + level * 26 * factors[i]))
            }
        }
        .animation(.easeOut(duration: 0.08), value: voice.audioLevel)
        .accessibilityHidden(true)   // purely decorative level meter
    }

    // MARK: Transport

    private var transportBar: some View {
        HStack(spacing: 12) {
            Button { voice.toggle() } label: {
                transportLabel(voice.isListening ? "Mute" : "Listen",
                               icon: voice.isListening ? "mic.fill" : "mic",
                               color: voice.isListening ? brass : .secondary,
                               filled: false)
                    .overlay {
                        // Border countdown: drains toward the auto-mute moment.
                        if voice.isListening {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .trim(from: 0, to: muteProgress)
                                .stroke(brass, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                                .allowsHitTesting(false)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voice.isListening ? "Mute voice control" : "Listen for voice")
            .accessibilityInputLabels(voice.isListening
                ? ["Mute", "Stop listening"]
                : ["Listen", "Start listening"])
            .popoverTip(MicListeningTip())   // first-run guidance for plain mic users

            Button { metronome.toggle() } label: {
                transportLabel(metronome.isPlaying ? "Stop" : "Start",
                               icon: metronome.isPlaying ? "stop.fill" : "play.fill",
                               color: metronome.isPlaying ? .red : brass,
                               filled: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(metronome.isPlaying ? "Stop metronome" : "Start metronome")
            .accessibilityInputLabels(metronome.isPlaying
                ? ["Stop", "Stop metronome", "Pause"]
                : ["Start", "Start metronome", "Play"])
            .popoverTip(VoiceControlTip())   // first-run guidance for Voice Control users
        }
    }

    private func transportLabel(_ title: String, icon: String, color: Color, filled: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(filled ? Color.white : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(filled ? color : color.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(filled ? 0 : 0.35), lineWidth: 1.5))
    }

    // MARK: Commands sheet

    private var commandsSheet: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        Toggle(isOn: $usesVoiceControl) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("I use iOS Voice Control").font(.subheadline.weight(.semibold))
                                Text("Turns off this app\u{2019}s mic so the two don\u{2019}t clash. Control it by saying \u{201C}Tap Start\u{201D}, \u{201C}Tap Faster\u{201D}, \u{201C}Tap 3 beats\u{201D}.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .tint(brass)
                        .accessibilityHint("Turns off the app's own microphone and drives controls by name")
                    } header: {
                        Text("Accessibility")
                    }
                    Section("How to use") {
                        usageRow("mic.fill", "Open", "Say \u{201C}help\u{201D} or tap the ? button.")
                        usageRow("xmark.circle", "Close", "Say \u{201C}close\u{201D} / \u{201C}done\u{201D}, or tap Done.")
                        usageRow("hand.draw", "Scroll", "Say \u{201C}scroll down\u{201D} / \u{201C}scroll up\u{201D}, or swipe.")
                    }
                    .id(helpSections[0])
                    Section("Playback") {
                        commandRow("\"start\" / \"stop\"", "play / pause")
                    }
                    .id(helpSections[1])
                    Section("Tempo") {
                        commandRow("\"faster\" / \"slower\"", "±5 BPM")
                        commandRow("\"up\" / \"down\"", "±1 BPM")
                        commandRow("\"tempo 120\"", "set value")
                        commandRow("\"double\" / \"half\"", "×2 / ÷2")
                        commandRow("\"trainer\"", "auto speed-up on/off")
                    }
                    .id(helpSections[2])
                    Section {
                        Toggle("Speed trainer", isOn: Binding(
                            get: { metronome.speedTrainerOn },
                            set: { metronome.setSpeedTrainer($0) }))
                            .tint(brass)
                        Stepper("Add \(metronome.trainerStep) BPM", value: $metronome.trainerStep, in: 1...20)
                        Stepper("Every \(metronome.trainerBars) bars", value: $metronome.trainerBars, in: 1...16)
                        Stepper("Up to \(metronome.trainerTarget) BPM", value: $metronome.trainerTarget, in: 40...260, step: 5)
                    } header: {
                        Text("Speed trainer")
                    } footer: {
                        Text("Raises the tempo automatically every few bars while you play — for gradually pushing a passage faster. Stops at the target.")
                    }
                    Section("Subdivision") {
                        commandRow("\"quarter\"", "1/4 notes")
                        commandRow("\"eighth\"", "1/8 notes")
                        commandRow("\"triplet\"", "triplets")
                        commandRow("\"sixteenth\"", "1/16 notes")
                    }
                    .id(helpSections[3])
                    Section("Tuner") {
                        commandRow("\"tune\"", "open the tuner")
                    }
                    .id(helpSections[4])
                    Section("Scrolling") {
                        commandRow("\"scroll down\" / \"scroll up\"", "move this list")
                        commandRow("\"help\"", "show this list")
                        commandRow("\"done\" / \"close\"", "close a panel")
                    }
                    .id(helpSections[5])
                }
                .onChange(of: helpIndex) { idx in
                    withAnimation { proxy.scrollTo(helpSections[idx], anchor: .top) }
                }
            }
            .navigationTitle("Voice Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showCommands = false }
                }
            }
        }
    }

    private func usageRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(brass)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Tuner sheet

    private var tunerSheet: some View {
        NavigationStack {
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
                        .foregroundStyle(inTune ? Color.green : brass)
                        .accessibilityHidden(true)   // pitch already announced on the note
                }
                Text(tuner.frequency > 0 ? String(format: "%.1f Hz", tuner.frequency) : "Play a note…")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Text("Say \"close\" to exit")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .navigationTitle("Tuner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showTuner = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var inTune: Bool { tuner.frequency > 0 && abs(tuner.cents) <= tuneTolerance }

    /// Spoken pitch summary for VoiceOver, replacing the visual cents meter.
    private var tunerAccessibilityValue: String {
        guard tuner.frequency > 0 else { return "No note detected, play a note" }
        if inTune { return "\(tuner.noteName), in tune" }
        let cents = Int(tuner.cents.rounded())
        return "\(tuner.noteName), \(abs(cents)) cents \(cents > 0 ? "sharp" : "flat")"
    }

    private var centsMeter: some View {
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
                    Circle().fill(inTune ? Color.green : brass)
                        .frame(width: 22, height: 22)
                        .position(x: w / 2 + CGFloat(cents / 50) * half, y: cy)
                        .animation(.easeOut(duration: 0.22), value: tuner.cents)
                }
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 36)
    }

    private func commandRow(_ phrase: String, _ effect: String) -> some View {
        HStack {
            Text(phrase).fontWeight(.medium)
            Spacer()
            Text(effect).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Small pieces

    private func stepButton(systemName: String, delta: Int) -> some View {
        Button {
            metronome.nudge(delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: stepIconSize))
                .foregroundStyle(brass)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta < 0 ? "Decrease tempo" : "Increase tempo")
        .accessibilityInputLabels(delta < 0
            ? ["Decrease tempo", "Slower", "Minus"]
            : ["Increase tempo", "Faster", "Plus"])
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
    }

    private var bpmBinding: Binding<Double> {
        Binding(get: { Double(metronome.bpm) },
                set: { metronome.bpm = Int($0) })
    }

    // MARK: Logic

    private var micMessage: String {
        switch voice.status {
        case .idle: return "Tap Listen to control by voice"
        case .listening:
            return voice.lastHeard.isEmpty
                ? "Say \"start\", \"faster\", or \"help\""
                : "Heard: \(voice.lastHeard)"
        case .denied: return "Mic/Speech blocked — enable in Settings"
        case .unavailable: return "Speech recognition unavailable here"
        }
    }

    private func toggleDetect() {
        if detector.isRunning { detector.cancel(); return }
        metronome.stop()   // our own clicks would pollute the recording
        voice.stop()       // free the mic from speech recognition
        detector.start()
    }

    private func wireUp() {
        metronome.onBeat = { beat in pulseBeat(beat) }
        voice.onCommand = { handle($0) }
        voice.onAudioBuffer = { buffer in tuner.process(buffer) }
        haptic.prepare()
    }

    private func openTuner() {
        metronome.stop()        // clicks would corrupt pitch detection
        showCommands = false
        tuner.start()
        showTuner = true
    }

    private func closePanels() {
        showCommands = false
        showTuner = false       // the sheet's onDismiss stops the tuner
    }

    private func restartMuteCountdown() {
        guard voice.isListening else { return }
        muteProgress = 1
        DispatchQueue.main.async {
            guard voice.isListening else { return }
            withAnimation(.linear(duration: voice.autoMuteAfter)) { muteProgress = 0 }
        }
    }

    private func handle(_ cmd: VoiceController.Command) {
        lastCommandText = commandLabel(cmd)
        FeedbackSound.shared.play()   // brief chime confirming the command landed
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
        case .help: showHelp()
        case .tuner: openTuner()
        case .dismiss: closePanels()
        case .scrollUp: helpIndex = max(0, helpIndex - 1)
        case .scrollDown: helpIndex = min(helpSections.count - 1, helpIndex + 1)
        case .speedTrainer: metronome.toggleSpeedTrainer()
        }
    }

    private func showHelp() {
        helpIndex = 0
        showCommands = true
        HelpVoiceTip().invalidate(reason: .actionPerformed)
    }

    private func commandLabel(_ cmd: VoiceController.Command) -> String {
        switch cmd {
        case .start: return "▶ Start"
        case .stop: return "■ Stop"
        case .faster: return "Faster +5"
        case .slower: return "Slower −5"
        case .up: return "Up +1"
        case .down: return "Down −1"
        case .double: return "Double ×2"
        case .half: return "Half ÷2"
        case .setTempo(let v): return "Tempo \(v)"
        case .setSubdivision(let v): return MetronomeEngine.subdivisionName(for: v)
        case .help: return "Help"
        case .tuner: return "Tuner"
        case .dismiss: return "Close"
        case .scrollUp: return "Scroll up"
        case .scrollDown: return "Scroll down"
        case .speedTrainer: return "Speed trainer"
        }
    }

    private func pulseBeat(_ beat: Int) {
        currentBeat = beat
        haptic.impactOccurred(intensity: beat == 0 ? 1.0 : 0.6)
        // Reduce Motion: skip the bounce — the lit dot still marks the beat.
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.06)) { beatScale = 1.1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            withAnimation(.easeIn(duration: 0.1)) { beatScale = 1.0 }
        }
    }
}

/// One-time hint that the voice "help" command exists.
struct HelpVoiceTip: Tip {
    var title: Text { Text("See every command") }
    var message: Text? { Text("Say \u{201C}help\u{201D} anytime — or tap here — to view all voice commands.") }
    var image: Image? { Image(systemName: "questionmark.circle.fill") }
}

/// Shared TipKit rule inputs. iOS exposes no API to detect system Voice Control,
/// so `usesVoiceControl` is user-declared (toggle in the Voice Commands sheet);
/// `voiceOverRunning` mirrors UIAccessibility so tips can defer to VoiceOver.
enum AppTips {
    @Parameter static var usesVoiceControl: Bool = false
    @Parameter static var voiceOverRunning: Bool = false
}

/// First-run, plain mic users: the app is already listening — just talk to it.
struct MicListeningTip: Tip {
    var title: Text { Text("Control it by voice") }
    var message: Text? {
        Text("The mic is already listening — say \u{201C}start\u{201D}, \u{201C}faster\u{201D}, or \u{201C}help\u{201D}. Use iOS Voice Control? Open Voice Commands to switch.")
    }
    var image: Image? { Image(systemName: "mic.fill") }
    var rules: [Rule] {
        #Rule(AppTips.$usesVoiceControl) { $0 == false }
        #Rule(AppTips.$voiceOverRunning) { $0 == false }
    }
}

/// First-run, Voice Control users: our mic is off; drive the app by control name.
struct VoiceControlTip: Tip {
    var title: Text { Text("Made for Voice Control") }
    var message: Text? {
        Text("The app\u{2019}s own mic is off so it won\u{2019}t clash with Voice Control. Say \u{201C}Tap Start\u{201D}, \u{201C}Tap Faster\u{201D}, or \u{201C}Tap 3 beats\u{201D}.")
    }
    var image: Image? { Image(systemName: "waveform") }
    var rules: [Rule] {
        #Rule(AppTips.$usesVoiceControl) { $0 == true }
    }
}

/// A circle drawn as `segments` equal arcs — visualizes how a beat is divided.
struct SegmentedRing: View {
    let segments: Int
    let color: Color

    var body: some View {
        ZStack {
            if segments <= 1 {
                Circle().stroke(color, lineWidth: 4)
            } else {
                ForEach(0..<segments, id: \.self) { i in
                    Circle()
                        .trim(from: CGFloat(i) / CGFloat(segments) + 0.04,
                              to: CGFloat(i + 1) / CGFloat(segments) - 0.04)
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
        }
        .padding(2)
    }
}

#Preview {
    ContentView()
}
