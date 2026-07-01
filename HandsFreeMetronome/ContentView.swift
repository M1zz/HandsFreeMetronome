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
    @State private var showTrainer = false   // practice-mode modal
    @State private var showHelpMarks = false   // "help" → quick "what can I say" list
    @State private var hintDismissed = false   // hide "tap dots" after first tap/start
    @State private var didAutoStart = false    // auto-enable listening once on launch
    @State private var muteProgress: CGFloat = 1   // Listen-button countdown ring (1→0)
    @State private var lastCommandText = ""     // last recognized voice command
    @State private var flashingCommand = false  // briefly show the command on the Mute button
    @State private var flashToken = 0           // invalidates stale flash timers
    @State private var helpIndex = 0            // voice-driven scroll position in Help
    @State private var tapTimes: [TimeInterval] = []   // recent taps for tap-tempo
    @AppStorage("tempoAsNumber") private var tempoAsNumber = false   // big display: term vs. BPM
    @State private var beatAnchor = Date()   // wall-clock moment the current beat fired
    // Which beat visualization is showing. Persisted so it survives relaunch.
    @AppStorage("beatVizMode") private var vizModeRaw = BeatVizMode.bounce.rawValue
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

    // A rich, saturated gold — clearer than the old muted brass but not glaring, so
    // small gold text still reads on white and it doesn't wash out in light mode.
    private let brass = Color(red: 0.84, green: 0.56, blue: 0.09)
    // A punchy red for the downbeat, more vivid than the system red on grey cards.
    private let beatRed = Color(red: 0.90, green: 0.22, blue: 0.20)
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let maxBeats = MetronomeEngine.maxBeatsPerMeasure
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
        // "help" highlights every on-screen control at once, each tagged with the
        // voice command that drives it — read from the controls' captured bounds.
        .overlayPreferenceValue(CoachAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if showHelpMarks { helpMarksOverlay(anchors, proxy).transition(.opacity) }
            }
            .ignoresSafeArea()
        }
        // Support Dynamic Type, but cap growth so the single-screen layout holds.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .fullScreenCover(isPresented: $showCommands) { commandsSheet }
        .sheet(isPresented: $showTuner, onDismiss: { tuner.stop() }) { tunerSheet }
        .sheet(isPresented: $showTrainer) { trainerSheet }
        .onChange(of: detector.state) { newState in
            if case .result(let bpm) = newState { metronome.setTempo(bpm) }
        }
        .onChange(of: metronome.isPlaying) { playing in
            if playing { withAnimation(.easeInOut(duration: 0.4)) { hintDismissed = true } }
            else { currentBeat = -1 }   // reset so the next start floats at centre first
            // Don't let the screen auto-lock mid-practice — a running metronome you
            // can't see (or that pauses when the display sleeps) is useless.
            UIApplication.shared.isIdleTimerDisabled = playing
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
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

    /// Portrait: the cards scroll if they don't all fit (small phones / large type),
    /// with the transport bar pinned to the bottom so Start/Stop is always reachable.
    /// Once playing, the setup cards fade away so only the beat + tempo remain.
    private var portraitLayout: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(spacing: 8) {
                    beatDots         // tap to set time signature; circles wave on the beat
                    tempoCard
                    if !metronome.isPlaying {
                        subdivisionCard.transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
            }
            .scrollBounceBehavior(.basedOnSize)   // don't bounce when it already fits
            // Voice status is pinned just above the transport so "Listening" and the
            // last heard command are always in view — never buried below the scroll.
            if !metronome.isPlaying {
                voiceCard
                    .padding(.horizontal, 16)
                    .transition(.opacity)
            }
            transportBar
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .animation(.easeInOut(duration: 0.35), value: metronome.isPlaying)
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
                if !metronome.isPlaying {
                    subdivisionCard.transition(.opacity)
                    voiceCard.transition(.opacity)
                }
                Spacer(minLength: 0)
                transportBar
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.35), value: metronome.isPlaying)
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

    // MARK: Beat visualization — two selectable modes.
    //  • bounce: a ball rides up/down at constant speed, hitting the top on every
    //    (sub)beat — subdivisions just make it bounce more often.
    //  • orbit:  a dot circles a ring of beat markers (4/4 → 0/90/180/270°),
    //    landing on each marker on the beat at constant angular velocity.
    // While stopped, both fall back to the editable dot grid so the time signature
    // can still be tapped in.

    private var vizMode: BeatVizMode { BeatVizMode(rawValue: vizModeRaw) ?? .bounce }

    private var beatDots: some View {
        let playing = metronome.isPlaying
        return ZStack {
            if playing {
                switch vizMode {
                case .bounce: bounceViz.transition(.opacity)
                case .orbit:  orbitViz.transition(.opacity)
                }
            } else {
                editableBeatGrid.transition(.opacity)
            }
        }
        // Cross-fade between the editable grid, bounce and orbit rather than snapping.
        .animation(.easeInOut(duration: 0.35), value: playing)
        .animation(.easeInOut(duration: 0.3), value: vizModeRaw)
        // Once playing, the setup cards fade out and the pendulum grows to fill the
        // screen — a clear switch to a focused "performance" view.
        .frame(height: playing ? 340 : 200)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(card)
        .overlay(alignment: .topTrailing) { vizModeButton.padding(12) }
        // Hint sits at the bottom edge as an overlay so it never nudges the content.
        .overlay(alignment: .bottom) {
            Text("\(metronome.beatsPerMeasure)/4  ·  tap dots to set beats")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(!hintDismissed && !playing ? 1 : 0)
                .accessibilityHidden(hintDismissed || playing)   // don't read the invisible hint
                .padding(.bottom, 6)
        }
        .coachAnchor("beat")
    }

    /// Small toggle that flips between the bounce and orbit visualizations.
    private var vizModeButton: some View {
        Button {
            vizModeRaw = (vizMode == .bounce ? BeatVizMode.orbit : .bounce).rawValue
            haptic.impactOccurred(intensity: 0.5)
        } label: {
            Image(systemName: vizMode == .bounce ? "circle.circle" : "arrow.up.arrow.down")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(vizMode == .bounce ? "Switch to orbit view" : "Switch to bounce view")
        .accessibilityInputLabels(["Change view", "Metronome mode", "Switch view"])
    }

    /// The editable dot grid shown while stopped — tap a dot to set the meter.
    private var editableBeatGrid: some View {
        let rows = dotRows(total: maxBeats)
        return VStack(spacing: 12) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 12) {
                    ForEach(rows[r], id: \.self) { i in
                        beatDot(i, active: i < metronome.beatsPerMeasure)
                    }
                }
            }
        }
    }

    /// Continuous phase (beats since the measure's beat 0) interpolated between the
    /// audio-accurate beat callbacks, so motion stays glued to the click.
    private func beatPhase(now: Date) -> Double {
        guard metronome.isPlaying, currentBeat >= 0 else { return 0 }
        let beatDuration = 60.0 / Double(metronome.bpm)
        let progress = min(1, max(0, now.timeIntervalSince(beatAnchor) / beatDuration))
        return Double(currentBeat) + progress
    }

    // MARK: Bounce visualization — a row of circles (one per beat) that rise and
    // fall separately, so a crest travels across them like a stadium wave (파도타기).

    private var bounceViz: some View {
        let beats = metronome.beatsPerMeasure
        let amp: CGFloat = 110          // bounce only shows while playing (roomy view)
        let sub = max(1, metronome.subdivision)
        return TimelineView(.animation(paused: reduceMotion || showHelpMarks)) { timeline in
            let phase = beatPhase(now: timeline.date)
            let started = currentBeat >= 0
            let f = started ? phase - Double(currentBeat) : 0     // 0…1 progress in the beat
            // Where the striking ball is right now, to light the marker it hits.
            let ballY = (started && !reduceMotion) ? bounceHeight(f, sub: sub, amp: amp) : -amp
            ZStack {
                // Fixed hit markers: the top line is the beat; a bottom line appears
                // once subdivided, and a middle line for the triplet's centre strike.
                // Each flashes as the ball reaches it.
                hitMarker(y: -amp, struck: started && ballY < -amp * 0.55)
                if sub == 3 {
                    hitMarker(y: 0, struck: started && abs(ballY) < amp * 0.22)
                }
                if sub >= 2 {
                    hitMarker(y: amp, struck: started && ballY > amp * 0.55)
                }
                HStack(spacing: 8) {
                    ForEach(0..<beats, id: \.self) { i in
                        let base = i == 0 ? beatRed : brass          // downbeat is red
                        let active = started && i == currentBeat
                        // The active beat's ball swings down and up at constant speed,
                        // striking a fixed marker on each subdivision (top on the beat,
                        // bottom on the off-beat…). Idle circles WAIT on the top line —
                        // where every swing begins and ends — so the hand-off from one
                        // beat to the next never jumps; only brightness/scale cross-fade.
                        let y = (active && !reduceMotion) ? bounceHeight(f, sub: sub, amp: amp) : -amp
                        Circle()
                            .fill(base.opacity(active ? 1.0 : 0.4))
                            .frame(width: 34, height: 34)
                            .scaleEffect(active && !reduceMotion ? 1.3 : 1.0)
                            .offset(y: y)
                            .shadow(color: active ? base.opacity(0.6) : .clear, radius: active ? 12 : 0)
                            .animation(.easeInOut(duration: 0.16), value: currentBeat)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Beat \(max(1, currentBeat + 1)) of \(beats), \(MetronomeEngine.subdivisionName(for: sub))")
    }

    /// A fixed horizontal hit-line the ball strikes; brightens on contact.
    private func hitMarker(y: CGFloat, struck: Bool) -> some View {
        Capsule()
            .fill(struck ? brass.opacity(0.9) : Color(.systemGray4))
            .frame(height: struck ? 3 : 2)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .offset(y: y)
            .animation(.easeOut(duration: 0.08), value: struck)
    }

    /// Ball height for progress `f` (0…1) through the beat.
    private func bounceHeight(_ f: Double, sub: Int, amp: CGFloat) -> CGFloat {
        let x = min(0.99999, max(0, f))
        // Triplet strikes three evenly-spaced marks — top → middle → bottom over the
        // first two thirds — then swings back up to the top for the next beat.
        if sub == 3 {
            return x < 2.0 / 3.0
                ? -amp + CGFloat(x / (2.0 / 3.0)) * (2 * amp)          // top → middle → bottom
                : amp - CGFloat((x - 2.0 / 3.0) / (1.0 / 3.0)) * (2 * amp)  // bottom → top
        }
        // Even subdivisions alternate top/bottom cleanly (1/8 = top·bottom, 1/16 =
        // two round-trips); 1/4 does one full top→bottom→top swing.
        let segs = sub == 1 ? 2 : sub
        let seg = x * Double(segs)
        let j = Int(seg)
        let frac = CGFloat(seg - Double(j))
        let start: CGFloat = (j % 2 == 0) ? -amp : amp                    // even hit = top
        let end: CGFloat = (j == segs - 1) ? -amp                         // return to top by beat end
                          : (((j + 1) % 2 == 0) ? -amp : amp)
        return start + (end - start) * frac
    }

    // MARK: Orbit visualization

    private var orbitViz: some View {
        let beats = metronome.beatsPerMeasure
        let sub = max(1, metronome.subdivision)
        return TimelineView(.animation(paused: reduceMotion || showHelpMarks)) { timeline in
            let phase = beatPhase(now: timeline.date)
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let radius = side / 2 - 10
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    Circle()                              // the track
                        .stroke(Color(.systemGray4), lineWidth: 2.5)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                    // Subdivision minor ticks between the beats — one extra dot per
                    // click, so 1/8 shows a midpoint, 1/16 shows three per beat.
                    if sub > 1 {
                        ForEach(0..<(beats * sub), id: \.self) { m in
                            if m % sub != 0 {
                                let pp = orbitPoint(beat: Double(m) / Double(sub), beats: beats, radius: radius, center: center)
                                Circle().fill(Color(.systemGray2))
                                    .frame(width: 7, height: 7).position(pp)
                            }
                        }
                    }
                    // Fixed beat markers at equal angles, beat 1 at the top.
                    ForEach(0..<beats, id: \.self) { i in
                        let p = orbitPoint(beat: Double(i), beats: beats, radius: radius, center: center)
                        let lit = i == currentBeat
                        Circle()
                            .fill(lit ? (i == 0 ? beatRed : brass)
                                      : (i == 0 ? beatRed.opacity(0.45) : brass.opacity(0.4)))
                            .frame(width: 20, height: 20)
                            .scaleEffect(lit ? 1.5 : 1.0)     // grow via scale so it eases cleanly
                            .position(p)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: currentBeat)
                    }
                    // The travelling dot.
                    let p = orbitPoint(beat: reduceMotion ? Double(max(0, currentBeat)) : phase,
                                       beats: beats, radius: radius, center: center)
                    let dotColor = currentBeat == 0 ? beatRed : brass
                    Circle()
                        .fill(dotColor)
                        .frame(width: 24, height: 24)
                        .shadow(color: dotColor.opacity(0.6), radius: 10)
                        .position(p)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Beat \(max(1, currentBeat + 1)) of \(beats), \(MetronomeEngine.subdivisionName(for: sub))")
    }

    /// Position on the orbit ring for a (possibly fractional) beat index, with beat 0
    /// at 12 o'clock and advancing clockwise.
    private func orbitPoint(beat: Double, beats: Int, radius: CGFloat, center: CGPoint) -> CGPoint {
        let angle = -Double.pi / 2 + (beat / Double(max(1, beats))) * 2 * .pi
        return CGPoint(x: center.x + radius * CGFloat(cos(angle)),
                       y: center.y + radius * CGFloat(sin(angle)))
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
        // upward. A wide ±34 travel makes the swing read clearly across the room.
        // Idle (or Reduce Motion): centred, no motion.
        let lift: CGFloat = (reduceMotion || !metronome.isPlaying) ? 0 : (sounding ? -34 : 34)
        return Circle()
            .fill(active ? dotFill(i) : Color.clear)
            .overlay(Circle().strokeBorder(active ? .clear : Color(.systemGray3), lineWidth: 1.5))
            .frame(width: 30, height: 30)
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
    /// (downbeat red, others brass); the rest keep their hue but dimmed, so the
    /// downbeat "1" still reads as red even while stopped.
    private func dotFill(_ i: Int) -> Color {
        let hue = i == 0 ? beatRed : brass
        return isActive(i) ? hue : hue.opacity(0.5)
    }

    // MARK: Tempo

    private var tempoCard: some View {
        VStack(spacing: 10) {
            // The big display shows the Italian tempo term (Largo, Moderato…) by
            // default; tap to flip it to the raw BPM number and back.
            Text(tempoAsNumber ? "\(metronome.bpm)" : MetronomeEngine.tempoName(for: metronome.bpm))
                .font(.system(size: bpmFontSize, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(beatScale > 1.0 ? brass : Color.primary)
                .scaleEffect(beatScale)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { tempoAsNumber.toggle() } }
                .accessibilityLabel("Tempo")
                .accessibilityValue("\(metronome.bpm) BPM, \(MetronomeEngine.tempoName(for: metronome.bpm))")
                .accessibilityHint("Tap to switch between the tempo name and BPM")
                .accessibilityInputLabels(["Tempo"])
                .accessibilityAction(named: "Tap tempo") { tapTempo() }   // VoiceOver keeps tap-tempo
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
        .coachAnchor("tempo")
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
        // Show whichever representation the big display isn't showing, so the BPM
        // number is always visible somewhere.
        case .idle: return tempoAsNumber
            ? MetronomeEngine.tempoName(for: metronome.bpm)
            : "\(metronome.bpm) BPM"
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
                    SegmentedRing(segments: opt.seg,
                                  color: selected ? brass : Color(.systemGray3))
                        .frame(width: 40, height: 40)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
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
        .coachAnchor("sub")
    }

    // MARK: Voice status + help

    /// A slim, elegant voice strip: a small live waveform + one line that reads
    /// "Listening…" (or the last command in gold), with the help button trailing.
    private var voiceCard: some View {
        HStack(spacing: 10) {
            if voice.isListening {
                voiceWaveform.frame(width: 40, height: 16)
            } else {
                Image(systemName: "mic.slash.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(voice.isListening
                 ? (lastCommandText.isEmpty ? "Listening…" : lastCommandText)
                 : micMessage)
                .font(.subheadline.weight(voice.isListening && !lastCommandText.isEmpty ? .semibold : .regular))
                .foregroundStyle(voice.isListening
                                 ? (lastCommandText.isEmpty ? Color.secondary : brass)
                                 : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Button { showHelp() } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Help")
            .accessibilityInputLabels(["Help", "Tips", "Voice commands"])
            .popoverTip(HelpVoiceTip())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(card)          // same rounded-rectangle shape as the other cards
        .coachAnchor("voice")
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
                // When listening, this is the Mute control (speaker symbol). As each
                // command lands, its name flashes here for a moment, then it settles
                // back to "Mute" — press again to toggle listening.
                let flashing = flashingCommand && voice.isListening && !lastCommandText.isEmpty
                transportLabel(flashing ? lastCommandText : (voice.isListening ? "Mute" : "Listen"),
                               icon: flashing ? "checkmark.circle.fill"
                                     : (voice.isListening ? "speaker.wave.2.fill" : "mic"),
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
            .coachAnchor("start")
        }
    }

    private func transportLabel(_ title: String, icon: String, color: Color, filled: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)   // a flashed command name may be a touch longer
            .foregroundStyle(filled ? Color.white : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(filled ? color : color.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(filled ? 0 : 0.35), lineWidth: 1.5))
    }

    // MARK: Help marks ("help" → highlight every on-screen control + its command)

    /// The voice phrase shown beside each highlighted control. Only controls that are
    /// actually on screen (have a captured anchor) get a mark, so it always matches
    /// the current screen.
    private func helpPhrase(for id: String) -> String {
        switch id {
        case "beat":  return "\u{201C}bounce\u{201D} / \u{201C}orbit\u{201D}"
        case "tempo": return "\u{201C}faster\u{201D} · \u{201C}tempo 120\u{201D}"
        case "sub":   return "\u{201C}quarter\u{201D} · \u{201C}eighth\u{201D} · \u{201C}triplet\u{201D} · \u{201C}sixteenth\u{201D}"
        case "voice": return "\u{201C}help\u{201D} · \u{201C}close\u{201D}"
        case "start": return metronome.isPlaying ? "\u{201C}stop\u{201D}" : "\u{201C}start\u{201D}"
        default:      return ""
        }
    }

    private func helpMarksOverlay(_ anchors: [String: Anchor<CGRect>], _ proxy: GeometryProxy) -> some View {
        let ids = ["beat", "tempo", "sub", "voice", "start"].filter { anchors[$0] != nil }
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.6).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissHelpMarks() }
                .accessibilityLabel("Dismiss help")
                .accessibilityAction { dismissHelpMarks() }
            // A ring + a "say …" pill on every visible control. The pill sits at the
            // centre of its own control, so pills never overlap each other (each stays
            // within its control's bounds).
            ForEach(ids, id: \.self) { id in
                let rect = proxy[anchors[id]!]
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(brass, lineWidth: 2.5)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
                helpPill(helpPhrase(for: id))
                    .frame(maxWidth: max(140, rect.width - 24))
                    .fixedSize(horizontal: false, vertical: true)
                    .position(x: rect.midX, y: rect.midY)
            }
            // Persistent instructions + escape hatches, pinned near the TOP edge.
            VStack {
                HStack(spacing: 12) {
                    Label("Say \u{201C}close\u{201D} or tap to dismiss", systemImage: "xmark.circle")
                        .font(.footnote.weight(.medium)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    Button { dismissHelpMarks(); showCommands = true } label: {
                        Text("All commands")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(brass))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.45)))
                .padding(.horizontal, 16)
                .padding(.top, 52)   // clear the status bar / notch
                Spacer()
            }
        }
    }

    /// A small "say …" callout tag placed next to a highlighted control.
    private func helpPill(_ phrase: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("say").font(.caption2.weight(.bold)).foregroundStyle(brass)
            Text(phrase).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 2))
        .accessibilityElement(children: .combine)
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
                    Section {
                        usageRow("circle.grid.3x3", "Set beats", "Tap the dots to choose the time signature.")
                        usageRow("hand.tap", "Tap tempo", "Tap the big BPM number in rhythm to set the tempo.")
                        usageRow("slider.horizontal.3", "Tempo", "Drag the tempo slider, or tap the − / + buttons.")
                        usageRow("speaker.wave.2.fill", "Volume", "Say \u{201C}louder\u{201D} / \u{201C}quieter\u{201D} / \u{201C}mute\u{201D}, or \u{201C}volume 60\u{201D}.")
                        usageRow("music.note", "Subdivision", "Tap 1/4, 1/8, Trip, or 1/16.")
                        usageRow("circle.circle", "Switch view", "Tap the view icon (top-right of the beat card) — bounce ↔ orbit.")
                        usageRow("waveform.badge.magnifyingglass", "Detect tempo", "Tap the wave icon (top-right of the tempo card) to detect from music.")
                        usageRow("chart.line.uptrend.xyaxis", "Practice mode", "Open it from Beat view below, or say \u{201C}practice\u{201D}.")
                        usageRow("play.fill", "Play", "Tap Start / Stop at the bottom.")
                        usageRow("mic.fill", "Voice", "Tap Listen to turn voice control on or off.")
                    } header: {
                        Text("On-screen")
                    } footer: {
                        Text("Everything here also works by voice — see the commands below.")
                    }
                    .id(helpSections[0])
                    Section("Help navigation") {
                        usageRow("questionmark.circle", "Open", "Say \u{201C}help\u{201D} or tap the ? button.")
                        usageRow("xmark.circle", "Close", "Say \u{201C}close\u{201D} / \u{201C}done\u{201D}, or tap Done.")
                        usageRow("hand.draw", "Scroll", "Say \u{201C}scroll down\u{201D} / \u{201C}scroll up\u{201D}, or swipe.")
                    }
                    Section("Playback") {
                        commandRow("\"start\" / \"stop\"", "play / pause")
                    }
                    .id(helpSections[1])
                    Section("Tempo") {
                        commandRow("\"faster\" / \"slower\"", "±5 BPM")
                        commandRow("\"up\" / \"down\"", "±1 BPM")
                        commandRow("\"tempo 120\"", "set value")
                        commandRow("\"double\" / \"half\"", "×2 / ÷2")
                        commandRow("\"three beats\"", "set time signature")
                    }
                    .id(helpSections[2])
                    Section("Volume") {
                        commandRow("\"louder\" / \"quieter\"", "±10%")
                        commandRow("\"volume 60\"", "set percent")
                        commandRow("\"mute\"", "silence the click")
                    }
                    Section("Beat view") {
                        commandRow("\"bounce\" / \"orbit\"", "switch visualization")
                        commandRow("\"practice\"", "open practice mode")
                        Button {
                            openPractice()
                        } label: {
                            Label("Open practice mode", systemImage: "chart.line.uptrend.xyaxis")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(brass)
                        }
                        .accessibilityInputLabels(["Practice mode", "Open practice"])
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
                        commandRow("\"help\"", "list the commands you can say")
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

    // MARK: Practice mode (speed trainer) modal

    /// Practice mode as its own modal (opened by the "practice" command or a Help
    /// launcher) — replaces the old always-on tempo-card button.
    private var trainerSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Practice mode", isOn: Binding(
                        get: { metronome.speedTrainerOn },
                        set: { metronome.setSpeedTrainer($0) }))
                        .tint(brass)
                        .accessibilityInputLabels(["Practice mode", "Practice", "Trainer"])
                    Stepper("Add \(metronome.trainerStep) BPM", value: $metronome.trainerStep, in: 1...20)
                    Stepper("Every \(metronome.trainerBars) bars", value: $metronome.trainerBars, in: 1...16)
                    Stepper("Up to \(metronome.trainerTarget) BPM", value: $metronome.trainerTarget, in: 40...260, step: 5)
                } footer: {
                    Text("Raises the tempo automatically every few bars while you play — for gradually pushing a passage faster. Stops at the target. Say \u{201C}practice\u{201D} anytime to open this.")
                }
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showTrainer = false }
                }
            }
        }
        .presentationDetents([.medium])
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

    /// Tap-tempo: tapping the big BPM number in rhythm sets the tempo from the
    /// average gap between taps. A long pause (>2s) starts a fresh measurement.
    /// Uses the monotonic uptime clock so it's immune to wall-clock changes.
    private func tapTempo() {
        let now = ProcessInfo.processInfo.systemUptime
        if let last = tapTimes.last, now - last > 2.0 { tapTimes.removeAll() }
        tapTimes.append(now)
        if tapTimes.count > 6 { tapTimes.removeFirst(tapTimes.count - 6) }
        haptic.impactOccurred(intensity: 0.5)
        guard tapTimes.count >= 2 else { return }
        let gaps = zip(tapTimes.dropFirst(), tapTimes).map { $0 - $1 }
        let avg = gaps.reduce(0, +) / Double(gaps.count)
        guard avg > 0 else { return }
        metronome.setTempo(Int((60.0 / avg).rounded()))
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
        showTrainer = false
        if showHelpMarks { dismissHelpMarks() }
    }

    private func restartMuteCountdown() {
        guard voice.isListening else { return }
        muteProgress = 1
        DispatchQueue.main.async {
            guard voice.isListening else { return }
            withAnimation(.linear(duration: voice.autoMuteAfter)) { muteProgress = 0 }
        }
    }

    /// Flash the just-recognized command on the Mute button, then settle back.
    private func flashCommandBriefly() {
        flashToken += 1
        let token = flashToken
        withAnimation(.easeOut(duration: 0.15)) { flashingCommand = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard flashToken == token else { return }   // a newer command took over
            withAnimation(.easeInOut(duration: 0.25)) { flashingCommand = false }
        }
    }

    private func handle(_ cmd: VoiceController.Command) {
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
        case .toggleView: vizModeRaw = (vizMode == .bounce ? BeatVizMode.orbit : .bounce).rawValue
        case .bounceView: vizModeRaw = BeatVizMode.bounce.rawValue
        case .orbitView: vizModeRaw = BeatVizMode.orbit.rawValue
        case .help: showHelp()
        case .tuner: openTuner()
        case .dismiss: closePanels()
        case .scrollUp: helpIndex = max(0, helpIndex - 1)
        case .scrollDown: helpIndex = min(helpSections.count - 1, helpIndex + 1)
        case .practice: openPractice()
        }
    }

    private func openPractice() {
        showCommands = false
        showTuner = false
        showTrainer = true
    }

    /// "help" pops up the list of commands you can say right now.
    private func showHelp() {
        showTuner = false
        showTrainer = false
        withAnimation(.easeOut(duration: 0.2)) { showHelpMarks = true }
        HelpVoiceTip().invalidate(reason: .actionPerformed)
    }

    private func dismissHelpMarks() {
        withAnimation(.easeInOut(duration: 0.2)) { showHelpMarks = false }
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
        case .setBeats(let n): return "\(n) beats"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
        case .setVolume(let p): return "Volume \(p)%"
        case .toggleView: return "Switch view"
        case .bounceView: return "Bounce view"
        case .orbitView: return "Orbit view"
        case .help: return "Help"
        case .tuner: return "Tuner"
        case .dismiss: return "Close"
        case .scrollUp: return "Scroll up"
        case .scrollDown: return "Scroll down"
        case .practice: return "Practice"
        }
    }

    private func pulseBeat(_ beat: Int) {
        currentBeat = beat
        beatAnchor = Date()          // anchor the smooth viz interpolation to this beat
        haptic.impactOccurred(intensity: beat == 0 ? 1.0 : 0.6)
        // Reduce Motion: skip the bounce — the lit dot still marks the beat.
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.06)) { beatScale = 1.1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            withAnimation(.easeIn(duration: 0.1)) { beatScale = 1.0 }
        }
    }
}

/// The two beat-visualization styles the user can switch between.
enum BeatVizMode: String {
    case bounce   // a ball riding up/down at constant speed
    case orbit    // a dot circling a ring of beat markers
}

/// Captures the bounds of every control tagged with `.coachAnchor(id)` so the "help"
/// overlay can ring it and label it with a voice command — all at once.
struct CoachAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func coachAnchor(_ id: String) -> some View {
        anchorPreference(key: CoachAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

/// One-time hint that the voice "help" command exists.
struct HelpVoiceTip: Tip {
    var title: Text { Text("Forget a command?") }
    var message: Text? { Text("Say \u{201C}help\u{201D} anytime — or tap here — to see every command you can say, then \u{201C}close\u{201D} to dismiss.") }
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
