import SwiftUI
import UIKit
import TipKit
import LeeoKit

struct ContentView: View {
    @StateObject private var metronome = MetronomeEngine()
    @StateObject private var voice = VoiceController()
    @StateObject private var tuner = TunerEngine()
    @StateObject private var noteSignal = NoteSignalDetector()
    @StateObject private var pro = ProStore()

    // A locked Pro feature was reached — which one shapes the paywall's pitch.
    @State private var paywallFeature: ProFeature?

    @State private var beatScale: CGFloat = 1.0
    @State private var currentBeat = -1   // which beat (0-based) is sounding now
    @State private var showCommands = false
    @State private var showTuner = false
    @State private var showTrainer = false   // practice-mode modal
    @State private var showTimer = false     // practice-timer modal
    @State private var showAccents = false   // accent-pattern grid modal
    @State private var showSavePreset = false     // name prompt for a new accent preset
    @State private var presetNameDraft = ""       // text field backing the prompt
    @State private var showHelpMarks = false   // "help" → quick "what can I say" list
    @State private var hintDismissed = false   // hide "tap dots" after first tap/start
    @State private var didAutoStart = false    // auto-enable listening once on launch
    @State private var muteProgress: CGFloat = 1   // Listen-button countdown ring (1→0)
    @State private var lastCommandText = ""     // last recognized voice command
    @State private var flashingCommand = false  // briefly show the command on the Mute button
    @State private var flashToken = 0           // invalidates stale flash timers
    @State private var helpIndex = 0            // voice-driven scroll position in Help
    @State private var tapTimes: [TimeInterval] = []   // recent taps for tap-tempo
    @State private var timingVerdict: TimingVerdict?   // orbit tap-accuracy readout
    @State private var timingToken = 0                 // invalidates stale fade-outs
    @State private var timingStats = TimingStats()     // running tally of play-along taps
    @State private var tapGhosts: [TapGhost] = []      // fading rings where taps landed
    @State private var flashOpacity: Double = 0        // whole-screen beat flash (0…~0.2)
    @State private var flashIsDownbeat = false         // red flash on beat 1, cue otherwise
    @AppStorage("tempoAsNumber") private var tempoAsNumber = false   // big display: term vs. BPM
    @State private var beatAnchor = Date()   // wall-clock moment the current beat fired
    // Which beat visualization is showing. Persisted so it survives relaunch.
    @AppStorage("beatVizMode") private var vizModeRaw = BeatVizMode.bounce.rawValue
    private let helpSections = ["howto", "playback", "tempo", "subdivision", "tuner", "scrolling"]

    // Feature-discovery tips, surfaced one at a time in a guided order (TipGroup)
    // so popovers never pile up. Each is dismissed for good once its feature is
    // used, which advances the tour to the next stop.
    @State private var featureTips = TipGroup(.ordered) {
        AccentGridTip()
        TempoDisplayTip()
        VizModeTip()
        PracticeTip()
        TunerTip()
    }

    // Spoken once, the first time a VoiceOver user opens the app.
    @AppStorage("didIntroduceVoiceOver") private var didIntroduceVoiceOver = false

    // The user relies on iOS system Voice Control. There is no public API to detect
    // this, so it is a user-declared setting (toggled in the Voice Commands sheet).
    // When on, we keep our OWN mic off to avoid two speech recognizers fighting over
    // the input — the user drives every control by its name ("Tap Start", "Tap Faster").
    @AppStorage("usesVoiceControl") private var usesVoiceControl = false

    // First-launch introduction and the once-per-version "What's new" card.
    // Both ride in the ZStack like the paywall (a TipKit popover swallows sheets).
    @AppStorage(NotMyTempoOnboardingView.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @AppStorage("lastSeenWhatsNewVersion") private var lastSeenWhatsNewVersion = ""
    @State private var showOnboarding = false
    @State private var showWhatsNew = false
    @State private var showOfferCode = false        // App Store offer-code redemption sheet
    @State private var playStartedAt: Date?         // a run long enough to count as practice
    @State private var showReviewGate = false       // "Enjoying Not My Tempo?" right after practice
    @State private var practiceJustEnded = false    // 연습을 막 마쳤다 — 팁 부탁이 설 수 있는 자리

    // Landscape on iPhone reports a compact height → switch to a two-column layout.
    @Environment(\.verticalSizeClass) private var vSizeClass
    // iPhone Duo unfolded: controls on one side of the fold, the beat on the other (LeeoKit Fold).
    @Environment(\.foldLayout) private var fold
    // Accessibility preferences we honour throughout the UI.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    // Assistive Access (iOS 18+): when the app runs inside the simplified system
    // experience for people with cognitive disabilities, we show a distilled UI.
    @Environment(\.accessibilityAssistiveAccessEnabled) private var assistiveAccess
    // Increase Contrast: dimmed beats and hairline outlines are drawn stronger.
    @Environment(\.colorSchemeContrast) private var contrast
    // Reduce Transparency: the help overlay's see-through scrims turn solid.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    // Accessibility text sizes: crowded rows rearrange instead of truncating.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Dynamic Type: scale the big fixed-size displays with the user's text setting.
    @ScaledMetric(relativeTo: .largeTitle) private var bpmFontSize: CGFloat = 52
    @ScaledMetric(relativeTo: .largeTitle) private var noteFontSize: CGFloat = 96
    @ScaledMetric(relativeTo: .title) private var stepIconSize: CGFloat = 30

    // Key colour and downbeat red — see Palette.swift for why these two.
    private let cue = Color.cue
    private let beatRed = Color.beatRed
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let sliderHaptic = UISelectionFeedbackGenerator()   // per-BPM detent on the tempo slider
    private let maxBeats = MetronomeEngine.maxBeatsPerMeasure
    private let tuneTolerance: Double = 10   // ± cents counted as "in tune"

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            // Whole-screen beat flash: peripheral vision is far more sensitive to
            // brightness than to position, so a faint full-bleed pulse keeps the
            // beat readable while the eyes are on sheet music. Kept subtle (≤0.2
            // opacity) to stay comfortable at high tempos.
            (flashIsDownbeat ? beatRed : cue)
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            Group {
                if assistiveAccess {
                    assistiveAccessLayout.foldConfined()
                } else {
                    // Folded (or any ordinary phone) this is the same single screen as before.
                    // Unfolded on iPhone Duo: the controls stay on the choose side (left /
                    // bottom) and the beat moves to the result side (right / top), so the
                    // pulse sits where the eyes are while the hands work the controls.
                    FoldSplitView {
                        if vSizeClass == .compact && !fold.isUnfolded {
                            landscapeLayout
                        } else {
                            portraitLayout
                        }
                    } result: {
                        beatDots
                            .padding(16)
                    }
                }
            }
            // Cube page-turn, outgoing face: main + tuner are two sides of one
            // box rolling left. The main layout swings 90° about its trailing
            // edge while that edge travels to the screen's left — mirrored by
            // the tuner's entry below, the shared edge lines up throughout.
            .rotation3DEffect(.degrees(showTuner && !reduceMotion ? -90 : 0),
                              axis: (x: 0, y: 1, z: 0),
                              anchor: .trailing, perspective: cubePerspective)
            .offset(x: showTuner && !reduceMotion ? -UIScreen.main.bounds.width : 0)
            .brightness(showTuner && !reduceMotion ? -0.18 : 0)

            // The tuner is a full-screen page that rolls in from the right —
            // the whole screen "turns" into it like a box face — not a sheet.
            if showTuner {
                tunerScreen
                    .foldConfined()
                    .transition(reduceMotion ? .opacity : .cubeFromTrailing)
                    .zIndex(2)
            }

            // The paywall rides in the same ZStack instead of a sheet: a TipKit
            // popover (almost always up for new users — exactly the ones who hit
            // gates) silently swallows sheet presentations, and revenue UI must
            // never lose that race. Slides up like a sheet, above everything.
            if let feature = paywallFeature {
                PaywallView(store: pro, feature: feature) {
                    withAnimation(.easeInOut(duration: 0.3)) { paywallFeature = nil }
                }
                .foldConfined()
                .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                .zIndex(3)
            }

            if showWhatsNew {
                WhatsNewView { closeWhatsNew() }
                    .foldConfined()
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                    .zIndex(4)
            }

            if showOnboarding {
                NotMyTempoOnboardingView(usesVoiceControl: usesVoiceControl) { finishOnboarding() }
                    .foldConfined()
                    .transition(.opacity)
                    .zIndex(5)
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
        .fullScreenCover(isPresented: $showCommands) { commandsSheet.foldConfined() }
        // The tuner engine follows the page's visibility (it used to be the
        // sheet's onDismiss) — stopped on ANY path that closes it.
        .onChange(of: showTuner) { open in
            if !open {
                tuner.stop()
                // Voice Control mode: the mic was only borrowed for tuning.
                if usesVoiceControl && voice.isListening { voice.stop() }
            }
            noteSignal.setSuspended(open)   // tuning a string must not fire the signal
        }
        .sheet(isPresented: $showTrainer) { trainerSheet }
        .sheet(isPresented: $showTimer) { timerSheet }
        // Practice timer ran out (the engine already stopped and chimed): a firm
        // haptic for players who can't hear the chime over their instrument, and
        // a spoken cue for VoiceOver.
        .onChange(of: metronome.practiceTimerFinished) { _ in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIAccessibility.post(notification: .announcement,
                                 argument: String(localized: "Practice time is up"))
            // A finished timed session is the clearest "this app did its job" moment.
            LeeoEngagement.shared.registerSignificantEvent()
            askForReviewAfterPractice()
        }
        .sheet(isPresented: $showAccents) { accentsSheet }
        .leeoReviewGate(HandsFreeMetronomeSpec.self, isPresented: $showReviewGate)
        .onChange(of: metronome.isPlaying) { playing in
            if playing {
                withAnimation(.easeInOut(duration: 0.4)) { hintDismissed = true }
                timingStats = TimingStats()   // fresh tap-accuracy tally for each run
                playStartedAt = Date()
                practiceJustEnded = false
            } else {
                currentBeat = -1   // reset so the next start floats at centre first
                // A real practice run (not a quick test click) feeds the review
                // prompt's "was this useful?" signal.
                if let started = playStartedAt {
                    let run = Date().timeIntervalSince(started)
                    NotMyTempoTipMoments.record(practice: run)
                    if run >= PracticeMoment.minimumRun {
                        LeeoEngagement.shared.registerSignificantEvent()
                        // 리뷰를 물을 차례면 팁은 묻지 않는다 — 한 번에 하나만 부탁한다.
                        practiceJustEnded = !LeeoReviewRequest.shouldRequest()
                        askForReviewAfterPractice()
                    }
                }
                playStartedAt = nil
            }
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
            greetIfNeeded()
            LaunchGuard.markLaunchSucceeded()
            #if DEBUG
            // Simulator-test hooks: the tuner (and its paywall gate) open by
            // voice only, which automation can't drive — these launch arguments
            // stand in for saying "tune". -uitest-tuner bypasses the gate to
            // exercise the slide-in page; -uitest-paywall goes through it.
            let uitestArgs = ProcessInfo.processInfo.arguments
            // UI tests tap the controls tip popovers would sit on.
            if uitestArgs.contains("-uitest-notips") { Tips.hideAllTipsForTesting() }
            if uitestArgs.contains("-uitest-tuner") || uitestArgs.contains("-uitest-paywall") {
                Tips.hideAllTipsForTesting()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if uitestArgs.contains("-uitest-tuner") {
                        tuner.start()
                        withAnimation(tunerPageAnimation) { showTuner = true }
                    } else {
                        openTuner()
                    }
                }
            }
            // -shot <scene> sets up an App Store screenshot by itself, so the raw
            // captures (docs/screenshots/raw) can be retaken the same way every
            // release. Appearance is set from outside with `simctl ui appearance`.
            if let i = uitestArgs.firstIndex(of: "-shot"), i + 1 < uitestArgs.count {
                prepareScreenshot(uitestArgs[i + 1])
            }
            // -uitest-close stands in for saying "close" a few seconds after launch,
            // so tip dismissal by voice can be checked on the simulator.
            if uitestArgs.contains("-uitest-close") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { handle(.dismiss) }
            }
            #endif
            // Listen by default — UNLESS the user relies on iOS Voice Control, in
            // which case our own mic would fight the system recognizer. They drive
            // the app by control name ("Tap Start") instead.
            // A newcomer hears why the mic is needed first — listening (and the
            // permission alerts) start when the introduction ends. Safe mode
            // (→ LaunchGuard) leaves the mic off; "Listen" still turns it on.
            if !didAutoStart && !showOnboarding {
                didAutoStart = true
                if !LaunchGuard.isSafeMode { startListeningIfAppropriate() }
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
        // During the introduction the mic isn't on yet — wait for it to finish.
        guard UIAccessibility.isVoiceOverRunning, !didIntroduceVoiceOver, !showOnboarding else { return }
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

    // MARK: Introduction · What's new

    /// Asks "Enjoying it?" just after a real practice run ends — not on the next
    /// launch, when the player has only just picked their instrument back up.
    /// Waits a beat so the chime and haptic land first, and stays out of the way
    /// if the click started again or anything else is on screen.
    private func askForReviewAfterPractice() {
        guard LeeoReviewRequest.shouldRequest() else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            let busy = metronome.isPlaying || paywallFeature != nil || showOnboarding || showWhatsNew
                || showCommands || showTuner || showTrainer || showTimer || showAccents || showSavePreset
                || showOfferCode || showReviewGate
            // Both a timer run-out and the stop it causes land here; the first one asks.
            guard !busy, LeeoReviewRequest.shouldRequest() else { return }
            LeeoReviewRequest.markRequested()
            showReviewGate = true
        }
    }

    /// Once per launch: a newcomer gets the introduction, someone who updated
    /// gets this version's What's-new card, everyone else goes straight in.
    private func greetIfNeeded() {
        #if DEBUG
        // Screenshot and UI-test launches set up their own scene; only
        // -uitest-onboarding asks for the introduction on purpose.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uitest-onboarding") {
            hasCompletedOnboarding = false
            lastSeenWhatsNewVersion = WhatsNewContent.version
        } else if args.contains("-shot") || args.contains(where: { $0.hasPrefix("-uitest") }) {
            return
        }
        #endif
        let audience = LaunchAudience.resolve(
            launchCount: LeeoEngagement.shared.launchCount,
            hasCompletedOnboarding: hasCompletedOnboarding,
            lastSeenWhatsNewVersion: lastSeenWhatsNewVersion.isEmpty ? nil : lastSeenWhatsNewVersion)
        switch audience {
        case .newcomer:
            // "What's new" means nothing to someone who just arrived.
            lastSeenWhatsNewVersion = WhatsNewContent.version
            AppTips.snoozed = true   // no tip popovers on top of the introduction
            showOnboarding = true
        case .returningNeedsWhatsNew:
            hasCompletedOnboarding = true   // they were here before the introduction existed
            lastSeenWhatsNewVersion = WhatsNewContent.version
            AppTips.snoozed = true
            showWhatsNew = true
        case .returning:
            hasCompletedOnboarding = true
        }
    }

    private func finishOnboarding() {
        hasCompletedOnboarding = true
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { showOnboarding = false }
        AppTips.snoozed = false
        // Listening (and with it the permission alerts) starts now that the
        // last page has said why.
        didAutoStart = true
        startListeningIfAppropriate()
        introduceVoiceOverIfNeeded()
    }

    private func closeWhatsNew() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { showWhatsNew = false }
        AppTips.snoozed = false
    }

    /// Listen by default — UNLESS the user relies on iOS Voice Control, in
    /// which case our own mic would fight the system recognizer.
    private func startListeningIfAppropriate() {
        if !usesVoiceControl && !voice.isListening { voice.toggle() }
    }

    /// Replay from the help sheet.
    private func replayOnboarding() {
        showCommands = false
        AppTips.snoozed = true
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { showOnboarding = true }
    }

    private func reopenWhatsNew() {
        showCommands = false
        AppTips.snoozed = true
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { showWhatsNew = true }
    }

    // MARK: Layouts

    /// Portrait: the cards scroll if they don't all fit (small phones / large type),
    /// with the transport bar pinned to the bottom so Start/Stop is always reachable.
    /// Once playing, the setup cards fade away so only the beat + tempo remain.
    private var portraitLayout: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(spacing: 8) {
                    // Unfolded, the beat stands on the other side of the fold instead.
                    if !fold.isUnfolded {
                        beatDots     // tap to set time signature; circles wave on the beat
                    }
                    tempoCard
                    if !metronome.isPlaying {
                        subdivisionCard.transition(.opacity)
                        tipAsk
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

    /// 연습을 막 마친 자리의 팁 부탁(`NotMyTempoTipMoments`). 이미 Pro 를 가진 사람에게만 —
    /// 아직 안 산 사람에게는 페이월이 맞는 길이다. 드물게 묻는 규칙은 LeeoKit 이 지킨다.
    @ViewBuilder private var tipAsk: some View {
        if practiceJustEnded, pro.isPro, let tipJar = pro.tipJar {
            LeeoTipAskSlot<HandsFreeMetronomeSpec>(tipJar: tipJar, reached: NotMyTempoTipMoments.reachedNow)
                .transition(.opacity)
        }
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
                    tipAsk
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
                    .foregroundStyle(beatScale > 1.0 ? cue : Color.primary)
                    .accessibilityLabel("Tempo")
                    .accessibilityValue("\(metronome.bpm) beats per minute")
                Text("BPM")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 14) {
                aaButton("Slower", icon: "minus", tint: cue) { metronome.nudge(-5) }
                aaButton("Faster", icon: "plus", tint: cue) { metronome.nudge(5) }
            }

            aaButton(metronome.isPlaying ? "Stop" : "Start",
                     icon: metronome.isPlaying ? "stop.fill" : "play.fill",
                     tint: metronome.isPlaying ? .red : cue,
                     spoken: metronome.isPlaying ? "Stop metronome" : "Start metronome") { metronome.toggle() }

            Spacer(minLength: 0)
        }
        .padding(20)
    }

    /// A large, full-width button for the Assistive Access layout.
    private func aaButton(_ title: LocalizedStringKey, icon: String, tint: Color,
                          spoken: LocalizedStringKey? = nil,
                          action: @escaping () -> Void) -> some View {
        Button {
            action()
            haptic.impactOccurred(intensity: 0.6)
        } label: {
            Label(title, systemImage: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(ink(on: tint))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(tint)
        .accessibilityLabel(spoken ?? title)
    }

    // MARK: Beat visualization — two selectable modes.
    //  • bounce: a pendulum ball arcs up/down and meets a dashed target ring at
    //    its centre resting point on every click — the contact "pops" (burst ring
    //    + scale) exactly as the sound fires.
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
                case .sweep:  sweepViz.transition(.opacity)
                }
            } else {
                editableBeatGrid.transition(.opacity)
            }
        }
        // Cross-fade between the editable grid, bounce and orbit rather than snapping.
        .animation(.easeInOut(duration: 0.35), value: playing)
        .animation(.easeInOut(duration: 0.3), value: vizModeRaw)
        // Once playing, the setup cards fade out and the pendulum grows to fill the
        // screen — a clear switch to a focused "performance" view. In landscape
        // (compact height) the card flexes to whatever the column has left instead,
        // so the tempo card below it is never pushed off screen.
        // Unfolded it has a whole pane of its own, so it fills that too.
        .frame(height: beatFillsPane ? nil : (playing ? 340 : 200))
        .frame(maxHeight: beatFillsPane ? .infinity : nil)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(card)
        .overlay(alignment: .topTrailing) { vizModeButton.padding(12) }
        // Hint sits at the bottom edge as an overlay so it never nudges the content.
        .overlay(alignment: .bottom) {
            Text("\(metronome.beatsPerMeasure)/4  ·  tap dots to set beats")
                .font(.caption)
                // Small print needs 4.5:1 — system grey at this size falls just
                // short (accessibility audit), so a darker ink of the label colour.
                .foregroundStyle(Color(.label).opacity(0.7))
                // Grows with the text size: wraps onto a second line instead of clipping.
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .opacity(!hintDismissed && !playing ? 1 : 0)
                .accessibilityHidden(hintDismissed || playing)   // don't read the invisible hint
                .padding(.bottom, 6)
        }
        .coachAnchor("beat")
    }

    /// The beat card flexes to its space instead of a fixed height: landscape, or its own pane on an unfolded Duo.
    private var beatFillsPane: Bool { vSizeClass == .compact || fold.isUnfolded }

    /// Small toggle that cycles bounce → orbit → sweep; its icon previews the NEXT view.
    private var vizModeButton: some View {
        Button {
            vizModeRaw = vizMode.next.rawValue
            haptic.impactOccurred(intensity: 0.5)
            VizModeTip().invalidate(reason: .actionPerformed)
        } label: {
            Image(systemName: vizMode.next == .orbit ? "circle.circle"
                            : vizMode.next == .sweep ? "clock"
                            : "arrow.up.arrow.down")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .popoverTip(featureTips.currentTip as? VizModeTip)
        .accessibilityLabel(vizMode.next == .orbit ? "Switch to orbit view"
                          : vizMode.next == .sweep ? "Switch to ring sweep view"
                          : "Switch to bounce view")
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
        let sub = max(1, metronome.subdivision)
        // Beyond 1/8 a per-click swing blurs into jitter, so cap the pendulum at
        // one swing per beat — the ear still gets every click.
        let swings = sub <= 2 ? sub : 1
        return GeometryReader { geo in
            // Swing as wide as the card allows — the full ±110 in portrait, tighter in
            // landscape — keeping the popped ball (~55pt) inside the card's bounds.
            let amp = min(110, max(36, geo.size.height / 2 - 34))
            TimelineView(.animation(paused: reduceMotion || showHelpMarks)) { timeline in
                let phase = beatPhase(now: timeline.date)
                // Gate on isPlaying too: right after a stop this view lingers for its
                // fade-out while `currentBeat` still holds the last beat but the phase
                // has already collapsed to 0 — without the gate `f` goes negative and
                // the click index below would subscript clickYs out of bounds (crash).
                let started = metronome.isPlaying && currentBeat >= 0
                let f = started ? min(1, max(0, phase - Double(currentBeat))) : 0   // 0…1 progress in the beat
                ZStack {
                    HStack(spacing: 8) {
                        ForEach(0..<beats, id: \.self) { i in
                            let base = i == 0 ? beatRed : cue          // downbeat is red
                            let active = started && i == currentBeat
                            // The active beat's ball crosses the centre ON each click and
                            // arcs out to an alternating extreme in between. Idle circles
                            // WAIT at the centre — where every swing begins and ends — so
                            // the hand-off from one beat to the next never jumps; only
                            // brightness/scale cross-fade.
                            let y = (active && !reduceMotion)
                                ? pendulumY(f, sub: swings, beat: i, amp: amp) : 0
                            // Pop on every CLICK: progress within the current click,
                            // 1 → 0 right after it fires — phase-derived, so it stays
                            // glued to the audio even when one swing spans four clicks.
                            let g = (f * Double(sub)).truncatingRemainder(dividingBy: 1)
                            let pop = (active && !reduceMotion && g < 0.3)
                                ? CGFloat(1 - g / 0.3) : 0
                            // Where the ball sits at the moment of each click — the
                            // sounding spots along the swing. Several clicks can share
                            // a spot (at 1/16 the ¾ point is struck on the way up AND
                            // down), so dedupe to one crisp dashed ring per height.
                            let clickYs = (0..<sub).map { k in
                                pendulumY(Double(k) / Double(sub), sub: swings, beat: i, amp: amp)
                            }
                            let targetYs = Array(Set(clickYs.map { ($0 * 2).rounded() / 2 })).sorted()
                            ZStack {
                                if active && !reduceMotion {
                                    // Dashed targets where the sound lives: the ball
                                    // meeting a ring IS a click, made visible — at 1/16
                                    // that's the centre, the ¾ point and the apex.
                                    ForEach(targetYs, id: \.self) { ty in
                                        Circle()
                                            .strokeBorder(base.opacity(0.55),
                                                          style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                                            .frame(width: 46, height: 46)
                                            .offset(y: ty)
                                    }
                                    // The pop: a ring bursts outward from whichever
                                    // target the ball is passing as its click fires.
                                    if pop > 0 {
                                        let k = max(0, min(sub - 1, Int(f * Double(sub))))
                                        Circle()
                                            .stroke(base, lineWidth: 2.5)
                                            .frame(width: 46, height: 46)
                                            .scaleEffect(1 + (1 - pop) * 1.2)
                                            .opacity(Double(pop))
                                            .offset(y: clickYs[k])
                                    }
                                }
                                Circle()
                                    .fill(base.opacity(active ? 1.0 : 0.4))
                                    .frame(width: 34, height: 34)
                                    // The ball itself pops too — a burst of scale on contact.
                                    .scaleEffect(active && !reduceMotion ? 1.3 + 0.25 * pop : 1.0)
                                    .offset(y: y)
                                    .shadow(color: active ? base.opacity(0.6) : .clear, radius: active ? 12 : 0)
                            }
                            .frame(width: 34, height: 34)   // ring overflow shouldn't widen the row
                            .animation(.easeInOut(duration: 0.16), value: currentBeat)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(width: geo.size.width, height: geo.size.height)   // centre in the card
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Beat \(max(1, currentBeat + 1)) of \(beats), \(MetronomeEngine.subdivisionName(for: sub))")
    }

    /// Ball height for progress `f` (0…1) through beat `beat`: a thrown-ball arc.
    /// The ball leaves the centre at full speed, decelerates under "gravity" to
    /// float at the apex, then accelerates back to cross the centre exactly ON the
    /// next click — so the contact moment is the fastest, sharpest point of the
    /// motion and easy to anticipate. Extremes alternate top/bottom per click.
    private func pendulumY(_ f: Double, sub: Int, beat: Int, amp: CGFloat) -> CGFloat {
        let x = min(0.99999, max(0, f))
        let seg = x * Double(sub)
        let j = Int(seg)                            // which click within the beat
        let g = seg - Double(j)                     // 0…1 progress within the click
        let up = (beat * sub + j) % 2 == 0          // alternate extremes click by click
        let t = 2 * g - 1                           // -1 → 1 across the click
        let reach = CGFloat(1 - t * t)              // parabola: gravity ease in/out
        return (up ? -amp : amp) * reach
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
                    // Each tick mirrors its click level: high = cue and larger,
                    // low = grey, a silent rest = barely-there.
                    if sub > 1 {
                        ForEach(0..<(beats * sub), id: \.self) { m in
                            if m % sub != 0 {
                                let level = metronome.clickLevel(at: m)
                                let pp = orbitPoint(beat: Double(m) / Double(sub), beats: beats, radius: radius, center: center)
                                Circle().fill(level == .high ? cue : Color(.systemGray2))
                                    .frame(width: level == .high ? 11 : 7,
                                           height: level == .high ? 11 : 7)
                                    .opacity(level == .mute ? 0.25 : 1)
                                    .position(pp)
                            }
                        }
                    }
                    // Fixed beat markers at equal angles, beat 1 at the top.
                    ForEach(0..<beats, id: \.self) { i in
                        let p = orbitPoint(beat: Double(i), beats: beats, radius: radius, center: center)
                        let lit = i == currentBeat
                        Circle()
                            .fill(lit ? (i == 0 ? beatRed : cue)
                                      : (i == 0 ? beatRed.opacity(0.45) : cue.opacity(0.4)))
                            .frame(width: 20, height: 20)
                            .scaleEffect(lit ? 1.5 : 1.0)     // grow via scale so it eases cleanly
                            .position(p)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: currentBeat)
                    }
                    // The travelling dot.
                    let p = orbitPoint(beat: reduceMotion ? Double(max(0, currentBeat)) : phase,
                                       beats: beats, radius: radius, center: center)
                    let dotColor = currentBeat == 0 ? beatRed : cue
                    Circle()
                        .fill(dotColor)
                        .frame(width: 24, height: 24)
                        .shadow(color: dotColor.opacity(0.6), radius: 10)
                        .position(p)
                    // Timing verdict from tapping along — flashes in the ring's
                    // empty centre, then fades.
                    if let verdict = timingVerdict {
                        Text(verdict.label)
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundStyle(verdict.color(cue: cue, red: beatRed))
                            .position(center)
                            .transition(reduceMotion ? .opacity
                                        : .scale(scale: 0.6).combined(with: .opacity))
                    }
                    // Running tally of this run's taps, resting below the flash.
                    if timingStats.total > 0 {
                        timingStatsReadout
                            .position(x: center.x, y: center.y + 52)
                            .transition(.opacity)
                    }
                    // Afterimages: each tap freezes a ghost of the travelling dot
                    // where it was at that instant — how far it sits from a beat
                    // marker is your timing error, made visible on the ring.
                    ForEach(tapGhosts) { ghost in
                        GhostCircle(color: ghost.verdict.color(cue: cue, red: beatRed),
                                    reduceMotion: reduceMotion)
                            .position(orbitPoint(beat: ghost.phase, beats: beats,
                                                 radius: radius, center: center))
                    }
                }
            }
        }
        .contentShape(Rectangle())
        // Tap along with the click: the gap to the nearest click becomes a verdict.
        .onTapGesture { judgeTimingTap() }
        .accessibilityElement()
        .accessibilityLabel("Beat \(max(1, currentBeat + 1)) of \(beats), \(MetronomeEngine.subdivisionName(for: sub))")
        .accessibilityValue(timingStats.total == 0 ? ""
            : "\(timingStats.perfect) perfect, \(timingStats.good) good, \(timingStats.bad) bad")
        .accessibilityHint("Tap in rhythm to check your timing")
        .accessibilityAction(named: "Check timing") { judgeTimingTap() }
    }

    /// Wordless tally: one bubble per verdict colour with its tap count inside.
    private var timingStatsReadout: some View {
        HStack(spacing: 10) {
            statBubble(timingStats.perfect, color: .green, symbol: "checkmark")
            statBubble(timingStats.good, color: cue, symbol: "circle")
            statBubble(timingStats.bad, color: beatRed, symbol: "xmark")
        }
        .accessibilityHidden(true)   // spoken via the orbit view's accessibilityValue
    }

    /// Text on a solid fill: bright cyan in dark mode needs black, everything else white.
    private func ink(on fill: Color) -> Color {
        fill == cue ? .onCue : .white
    }

    private func statBubble(_ count: Int, color: Color, symbol: String) -> some View {
        Text("\(count)")
            .font(.system(.headline, design: .rounded).weight(.bold))
            .monospacedDigit()
            .minimumScaleFactor(0.5)   // three-digit counts shrink to stay inside
            .foregroundStyle(ink(on: color))
            .frame(width: 34, height: 34)
            .background(Circle().fill(color))
            // Differentiate Without Color: perfect / good / bad also differ by mark.
            .overlay(alignment: .topTrailing) {
                if differentiateWithoutColor {
                    Image(systemName: symbol)
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(color)
                        .padding(3)
                        .background(Circle().fill(Color(.systemBackground)))
                        .offset(x: 6, y: -6)
                }
            }
    }

    /// Grade a tap by its distance to the nearest CLICK — the subdivision grid, so
    /// at 1/8 a full orbit offers 8 chances at a Perfect, at 1/16 sixteen. Within
    /// 10% of the click interval = Perfect, 25% = Good, anything worse = Bad. The
    /// travelling dot drops a fading ghost at the spot it held when the tap landed.
    private func judgeTimingTap() {
        guard metronome.isPlaying, currentBeat >= 0 else { return }
        let clickDuration = 60.0 / Double(metronome.bpm) / Double(max(1, metronome.subdivision))
        let offset = Date().timeIntervalSince(beatAnchor)
            .truncatingRemainder(dividingBy: clickDuration)
        let error = min(offset, clickDuration - offset) / clickDuration
        let verdict: TimingVerdict = error <= 0.10 ? .perfect
                                   : error <= 0.25 ? .good
                                   : .bad
        timingToken += 1
        let token = timingToken
        withAnimation(.spring(duration: 0.25)) {
            timingVerdict = verdict
            timingStats.record(verdict)
        }
        let ghost = TapGhost(phase: beatPhase(now: Date()), verdict: verdict)
        tapGhosts.append(ghost)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            tapGhosts.removeAll { $0.id == ghost.id }
        }
        haptic.impactOccurred(intensity: verdict == .perfect ? 1.0 : 0.5)
        UIAccessibility.post(notification: .announcement, argument: verdict.label)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard timingToken == token else { return }   // a newer tap took over
            withAnimation(.easeOut(duration: 0.3)) { timingVerdict = nil }
        }
    }

    // MARK: Sweep visualization — a radial progress ring that fills over exactly
    // one beat (clock metaphor: zero learning curve) and "bursts" at 12 o'clock as
    // the click lands, with the beat number counting in the centre.

    private var sweepViz: some View {
        let beats = metronome.beatsPerMeasure
        return TimelineView(.animation(paused: reduceMotion || showHelpMarks)) { timeline in
            let phase = beatPhase(now: timeline.date)
            // Same guard as the bounce view: while fading out after a stop the phase
            // is already 0 but `currentBeat` isn't reset yet, so an unclamped `f`
            // would go negative for a frame (negative trim/scale glitches).
            let started = metronome.isPlaying && currentBeat >= 0
            let f = started ? min(1, max(0, phase - Double(currentBeat))) : 0   // 0…1 through the beat
            let color = currentBeat == 0 ? beatRed : cue        // downbeat sweeps red
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let radius = side / 2 - 16
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    Circle()                                      // the track
                        .stroke(Color(.systemGray5), lineWidth: 10)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                    Circle()                                      // this beat's fill
                        .trim(from: 0, to: reduceMotion ? 1 : CGFloat(f))
                        .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))            // start/burst at 12 o'clock
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                    // The burst: right after the click a dot at 12 o'clock swells and
                    // fades — driven purely by the beat phase, so it stays glued to
                    // the audio with no extra state.
                    if started && !reduceMotion && f < 0.25 {
                        let b = CGFloat(f / 0.25)                 // 0…1 through the burst
                        Circle()
                            .fill(color)
                            .frame(width: 18, height: 18)
                            .scaleEffect(1 + b * 2.4)
                            .opacity(Double(1 - b))
                            .position(x: center.x, y: center.y - radius)
                    }
                    // Centre count-off, big enough to read from across the room.
                    Text("\(max(1, currentBeat + 1))")
                        .font(.system(size: 88, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(color)
                        .contentTransition(.numericText())
                        .position(center)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Beat \(max(1, currentBeat + 1)) of \(beats)")
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
            .overlay(Circle().strokeBorder(active ? .clear : inactiveOutline,
                                           lineWidth: contrast == .increased ? 2 : 1.5))
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
            .accessibilityLabel(Text("\(i + 1) beats"))
            .accessibilityInputLabels(["\(i + 1) beats", "Beat \(i + 1)", "\(i + 1)"])
            // VoiceOver: announce as a button, mark the current time signature selected.
            .accessibilityAddTraits(i + 1 == metronome.beatsPerMeasure ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint("Sets \(i + 1)/4 time")
    }

    /// Outline of an unused beat — a hairline normally, a firm line with Increase Contrast.
    private var inactiveOutline: Color {
        contrast == .increased ? Color(.systemGray) : Color(.systemGray3)
    }

    private func isActive(_ i: Int) -> Bool { metronome.isPlaying && i == currentBeat }

    /// Fill for an active beat: the currently sounding one is bright
    /// (downbeat red, others cue); the rest keep their hue but dimmed, so the
    /// downbeat "1" still reads as red even while stopped.
    private func dotFill(_ i: Int) -> Color {
        let hue = i == 0 ? beatRed : cue
        return isActive(i) ? hue : hue.opacity(contrast == .increased ? 0.8 : 0.5)
    }

    // MARK: Tempo

    private var tempoCard: some View {
        VStack(spacing: 10) {
            // The big display shows the Italian tempo term (Largo, Moderato…) by
            // default; tap to flip it to the raw BPM number and back.
            Text(tempoAsNumber ? "\(metronome.bpm)" : MetronomeEngine.tempoName(for: metronome.bpm))
                .font(.system(size: bpmFontSize, weight: .bold, design: .rounded))
                .lineLimit(1)
                .allowsTightening(true)   // "Prestissimo" tightens before it shrinks
                .minimumScaleFactor(0.5)
                .foregroundStyle(beatScale > 1.0 ? cue : Color.primary)
                .scaleEffect(beatScale)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { tempoAsNumber.toggle() }
                    TempoDisplayTip().invalidate(reason: .actionPerformed)
                }
                .popoverTip(featureTips.currentTip as? TempoDisplayTip)
                .accessibilityLabel("Tempo")
                .accessibilityValue("\(metronome.bpm) BPM, \(MetronomeEngine.tempoName(for: metronome.bpm))")
                .accessibilityHint("Tap to switch between the tempo name and BPM")
                .accessibilityAddTraits(.isButton)
                .accessibilityInputLabels(["Tempo"])
                .accessibilityAction(named: "Tap tempo") { tapTempo() }   // VoiceOver keeps tap-tempo
            Text(tempoSubtitle)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                // Readable grey: the system secondary colour misses 4.5:1 at this size.
                .foregroundStyle(metronome.speedTrainerOn ? cue : Color(.label).opacity(0.7))
            HStack(spacing: 16) {
                stepButton(systemName: "minus.circle.fill", delta: -1)
                Slider(value: bpmBinding, in: 30...260, step: 1)
                    .tint(cue)
                    .accessibilityLabel("Tempo")
                    .accessibilityValue("\(metronome.bpm) BPM")
                    .accessibilityInputLabels(["Tempo", "Tempo slider", "BPM"])
                stepButton(systemName: "plus.circle.fill", delta: 1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(card)
        // The speed trainer has no button of its own (voice / Help launcher only),
        // so its tip anchors to the tempo card whose subtitle shows its status.
        .popoverTip(featureTips.currentTip as? PracticeTip)
        .coachAnchor("tempo")
    }

    private var tempoSubtitle: String {
        // Trainer status takes over the subtitle when it's running.
        if metronome.speedTrainerOn {
            return String(localized: "Speed trainer · +\(metronome.trainerStep) every \(metronome.trainerBars) bars → \(metronome.trainerTarget)")
        }
        // Show whichever representation the big display isn't showing, so the BPM
        // number is always visible somewhere.
        return tempoAsNumber
            ? MetronomeEngine.tempoName(for: metronome.bpm)
            : String(localized: "\(metronome.bpm) BPM")
    }

    // MARK: Subdivision — tap a ring that shows how the beat is divided

    private var subdivisionCard: some View {
        let options: [(seg: Int, value: Int, label: String, name: String)] =
            [(1, 1, "1/4", String(localized: "Quarter notes")), (2, 2, "1/8", String(localized: "Eighth notes")),
             (3, 3, "Trip", String(localized: "Triplets")), (4, 4, "1/16", String(localized: "Sixteenth notes"))]
        return HStack(spacing: 8) {
            ForEach(options, id: \.value) { opt in
                let selected = metronome.subdivision == opt.value
                Button {
                    metronome.setSubdivision(opt.value)
                    haptic.impactOccurred(intensity: 0.5)
                } label: {
                    SegmentedRing(segments: opt.seg,
                                  color: selected ? cue : Color(.systemGray3))
                        .frame(width: 40, height: 40)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(selected ? cue.opacity(0.14) : .clear))
                        // Differentiate Without Color / Increase Contrast: the faint tint
                        // alone is too weak a "selected" cue — outline it as well.
                        .overlay {
                            if selected && (differentiateWithoutColor || contrast == .increased) {
                                RoundedRectangle(cornerRadius: 12).strokeBorder(cue, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(opt.name)
                .accessibilityInputLabels([opt.name, opt.label])
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                // No on-screen Accents button — VoiceOver reaches the editor here.
                .accessibilityAction(named: "Edit accents") { openAccents() }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(card)
        // Double-tap the card to open the accent grid (documented in Help — there is
        // no separate button). Simultaneous, so the first tap still selects normally.
        // Quarters are editable too: each beat of the measure is its own cell.
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            haptic.impactOccurred(intensity: 0.6)
            openAccents()
        })
        // First-run hint — the double-tap is otherwise invisible.
        .popoverTip(featureTips.currentTip as? AccentGridTip)
        .coachAnchor("sub")
    }

    // MARK: Accent grid modal — the WHOLE measure as a step-sequencer grid: one row
    // per beat, one cell per click, so 4/4 with sixteenths shows all 16 clicks as
    // individually tappable cells cycling high → low → silent.

    private var accentsSheet: some View {
        let sub = max(1, metronome.subdivision)
        let beats = metronome.beatsPerMeasure
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Every click of the measure is its own cell — \(beats * sub) clicks in all. Tap a cell to cycle it: high → low → silent.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if sub == 1 {
                        // Undivided: a single row, one cell per beat, numbered below.
                        HStack(spacing: 6) {
                            ForEach(0..<beats, id: \.self) { b in
                                VStack(spacing: 4) {
                                    accentCell(tick: b, sub: sub)
                                    Text("\(b + 1)")
                                        .font(.caption2.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(b == 0 ? beatRed : .secondary)
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            ForEach(0..<beats, id: \.self) { b in
                                HStack(spacing: 12) {
                                    Text("\(b + 1)")
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(b == 0 ? beatRed : .secondary)
                                        .frame(width: 22, alignment: .center)
                                    HStack(spacing: 6) {
                                        ForEach(0..<sub, id: \.self) { i in
                                            accentCell(tick: b * sub + i, sub: sub)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    presetsSection
                }
                .padding(20)
                .animation(.easeInOut(duration: 0.15), value: metronome.accentLevels)
            }
            .navigationTitle("Accents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { metronome.resetAccents() } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                        .accessibilityHint("Restores the default pattern for this meter")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { showAccents = false } label: { Label("Done", systemImage: "checkmark") }
                }
            }
            .alert("Save preset", isPresented: $showSavePreset) {
                TextField("Name (e.g. Bossa intro)", text: $presetNameDraft)
                    .submitLabel(.done)
                    .onSubmit { savePresetDraft() }
                Button("Save") { savePresetDraft() }
                Button("Cancel", role: .cancel) { presetNameDraft = "" }
            } message: {
                Text("Saves this pattern with its meter and subdivision, so you can recall it per song.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Saves the pattern on screen under the typed name (Save button or Return).
    private func savePresetDraft() {
        let before = metronome.accentPresets.count
        metronome.saveAccentPreset(named: presetNameDraft)
        presetNameDraft = ""
        showSavePreset = false
        guard metronome.accentPresets.count > before else { return }   // blank name: nothing saved
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AccessibilityNotification.Announcement(String(localized: "Preset saved")).post()
        // Building a pattern for a song is real investment in the app.
        LeeoEngagement.shared.registerSignificantEvent()
    }

    /// One cell of the accent grid. Each tap cycles high → low → silent. A tall bar
    /// marks a high click, a short one low, none a rest — reads at a glance,
    /// colorblind-safe.
    private func accentCell(tick: Int, sub: Int) -> some View {
        let level = metronome.clickLevel(at: tick)
        return Button {
            metronome.cycleClickLevel(at: tick)
            haptic.impactOccurred(intensity: 0.4)
        } label: {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(level == .high ? cue
                    : level == .low ? Color(.systemGray5)
                    : Color(.systemGray6))
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .overlay {
                    if level == .mute {
                        // A rest: an empty, dashed cell.
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color(.systemGray3),
                                          style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    } else {
                        Capsule()
                            .fill(level == .high ? Color.onCue : Color(.systemGray2))
                            .frame(width: 4, height: level == .high ? 22 : 10)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Beat \(tick / sub + 1), click \(tick % sub + 1)")
        .accessibilityValue(level == .high ? "High tone" : level == .low ? "Low tone" : "Silent")
        .accessibilityHint("Cycles between high, low, and silent")
        .accessibilityInputLabels(["Beat \(tick / sub + 1) click \(tick % sub + 1)"])
    }

    /// Saved patterns: recall one per song (it restores its meter + subdivision too),
    /// or snapshot the pattern on screen under a new name.
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Presets")
                .font(.subheadline.weight(.semibold))
            if metronome.accentPresets.isEmpty {
                // Empty state with its own way out: the save button lives inside it.
                ContentUnavailableView {
                    Label("No presets yet", systemImage: "square.stack")
                        .font(.headline)
                } description: {
                    Text("Save a pattern per song — recalling it also restores its meter and subdivision.")
                        .font(.footnote)
                } actions: {
                    savePresetButton
                }
                .padding(.vertical, -12)   // sits inside a sheet; drop the full-screen padding
            }
            ForEach(metronome.accentPresets) { preset in
                HStack(spacing: 10) {
                    Button {
                        metronome.applyAccentPreset(preset)
                        haptic.impactOccurred(intensity: 0.5)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(preset.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                // Long song names keep their start and end ("Bossa … outro").
                                .lineLimit(2)
                                .truncationMode(.middle)
                            Text("\(preset.beats)/4 · \(MetronomeEngine.subdivisionName(for: preset.sub))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preset \(preset.name)")
                    .accessibilityHint("Applies this pattern, meter, and subdivision")
                    .accessibilityInputLabels([preset.name])
                    Button {
                        metronome.deleteAccentPreset(preset)
                        haptic.impactOccurred(intensity: 0.4)
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete preset \(preset.name)")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground)))
            }
            if !metronome.accentPresets.isEmpty { savePresetButton }
        }
        .padding(.top, 4)
    }

    private var savePresetButton: some View {
        Button {
            showSavePreset = true
        } label: {
            Label("Save current pattern…", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(cue)
        }
        .accessibilityInputLabels(["Save pattern", "Save preset"])
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
                 ? (lastCommandText.isEmpty ? String(localized: "Listening…") : lastCommandText)
                 : micMessage)
                .font(.subheadline.weight(voice.isListening && !lastCommandText.isEmpty ? .semibold : .regular))
                // Mic off: this line is the instruction for turning it back on,
                // so it reads at full contrast (the audit flagged grey-on-card).
                .foregroundStyle(voice.isListening
                                 ? (lastCommandText.isEmpty ? Color.secondary : cue)
                                 : .primary)
                // Wraps at large text sizes instead of shrinking out of reach.
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
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
        // This strip is far shorter than the other cards, where the shared 16pt
        // radius reads as a capsule; a tighter radius keeps the same rectangular
        // look as every other box on screen.
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
        // The tuner is voice-first ("tune"), so its tip sits on the voice strip.
        .popoverTip(featureTips.currentTip as? TunerTip)
        .coachAnchor("voice")
    }

    private var voiceWaveform: some View {
        let level = CGFloat(voice.audioLevel)
        let factors: [CGFloat] = [0.45, 0.8, 1.0, 0.6, 0.95, 0.55, 0.85]
        return HStack(alignment: .center, spacing: 4) {
            ForEach(factors.indices, id: \.self) { i in
                Capsule()
                    .fill(cue)
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
                transportLabel(flashing ? lastCommandText
                                        : (voice.isListening ? String(localized: "Mute") : String(localized: "Listen")),
                               icon: flashing ? "checkmark.circle.fill"
                                     : (voice.isListening ? "speaker.wave.2.fill" : "mic"),
                               // Off state: muted, but dark enough to read (4.5:1) —
                               // system grey on its own tinted fill fell short in the audit.
                               color: voice.isListening ? cue : Color(.label).opacity(0.7),
                               filled: false,
                               // At accessibility text sizes three labelled buttons can't
                               // share a row — this one goes icon-only so Start keeps its word.
                               iconOnly: dynamicTypeSize.isAccessibilitySize)
                    .overlay {
                        // Border countdown: drains toward the auto-mute moment.
                        if voice.isListening {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .trim(from: 0, to: muteProgress)
                                .stroke(cue, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
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

            timerButton

            Button { metronome.toggle() } label: {
                transportLabel(metronome.isPlaying ? String(localized: "Stop") : String(localized: "Start"),
                               icon: metronome.isPlaying ? "stop.fill" : "play.fill",
                               color: metronome.isPlaying ? .red : cue,
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

    /// Practice timer: a compact square that shows the time left once a timer is
    /// set, so the countdown stays in view while playing. Tap to set it up.
    private var timerButton: some View {
        let on = metronome.practiceTimerOn
        return Button { openTimer() } label: {
            Group {
                if on {
                    Label(timerText(metronome.practiceTimerRemaining), systemImage: "timer")
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                } else {
                    Label("Timer", systemImage: "timer").labelStyle(.iconOnly)
                }
            }
            .font(.headline)
            .lineLimit(1)
            .foregroundStyle(on ? cue : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
            .frame(minWidth: 56)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill((on ? cue : Color.secondary).opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke((on ? cue : Color.secondary).opacity(outlineOpacity), lineWidth: 1.5))
            .animation(.default, value: metronome.practiceTimerRemaining)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Practice timer")
        .accessibilityValue(on ? timerSpokenValue : String(localized: "Off"))
        .accessibilityInputLabels(["Timer", "Practice timer"])
        .coachAnchor("timer")
    }

    /// "4:05" — minutes are not padded, so up to 120:00 stays compact.
    private func timerText(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var timerSpokenValue: String {
        let left = Duration.seconds(metronome.practiceTimerRemaining)
        return String(localized: "\(left.formatted(.units(allowed: [.minutes, .seconds], width: .wide))) left")
    }

    /// Button outlines: soft by default, solid enough to see with Increase Contrast.
    private var outlineOpacity: Double { contrast == .increased ? 0.85 : 0.35 }

    private func transportLabel(_ title: String, icon: String, color: Color, filled: Bool,
                                iconOnly: Bool = false) -> some View {
        Label(title, systemImage: icon)
            .labelStyle(TransportLabelStyle(iconOnly: iconOnly))
            .font(.headline)
            // A flashed command name may be longer, and text may be large:
            // wrap to a second line rather than shrink.
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundStyle(filled ? ink(on: color) : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(filled ? color : color.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(filled ? 0 : outlineOpacity), lineWidth: 1.5))
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
        case "timer": return "\u{201C}timer 5 minutes\u{201D}"
        default:      return ""
        }
    }

    private func helpMarksOverlay(_ anchors: [String: Anchor<CGRect>], _ proxy: GeometryProxy) -> some View {
        let ids = ["beat", "tempo", "sub", "voice", "timer", "start"].filter { anchors[$0] != nil }
        return ZStack(alignment: .topLeading) {
            // Reduce Transparency: a near-solid scrim, so the busy screen behind
            // never shows through the callouts.
            Color.black.opacity(reduceTransparency ? 0.92 : 0.6).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissHelpMarks() }
                .accessibilityLabel("Dismiss help")
                .accessibilityAction { dismissHelpMarks() }
            // A ring + a "say …" pill on every visible control. The pill sits at the
            // centre of its own control, so pills never overlap each other (each stays
            // within its control's bounds).
            ForEach(ids, id: \.self) { id in
                // `ids` is filtered on this dictionary, but never force-unwrap in
                // a view body — a stale re-evaluation must degrade, not crash.
                if let anchor = anchors[id] {
                    let rect = proxy[anchor]
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(cue, lineWidth: 2.5)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                    helpPill(helpPhrase(for: id))
                        .frame(maxWidth: max(140, rect.width - 24))
                        .fixedSize(horizontal: false, vertical: true)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            // Persistent instructions + escape hatches, pinned near the TOP edge.
            VStack {
                HStack(spacing: 12) {
                    Label("Say \u{201C}close\u{201D} or tap to dismiss", systemImage: "xmark.circle")
                        .font(.footnote.weight(.medium)).foregroundStyle(.white)
                        .lineLimit(2).minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    Button { dismissHelpMarks(); showCommands = true } label: {
                        Text("All commands")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Color.onCue)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(cue))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(reduceTransparency ? Color.black : Color.black.opacity(0.45)))
                .padding(.horizontal, 16)
                .padding(.top, 52)   // clear the status bar / notch
                Spacer()
            }
        }
    }

    /// A small "say …" callout tag placed next to a highlighted control.
    private func helpPill(_ phrase: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("say").font(.caption2.weight(.bold)).foregroundStyle(cue)
            Text(phrase).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 2))
        .overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(cue, lineWidth: 1.5)
            }
        }
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
                        .tint(cue)
                        .accessibilityHint("Turns off the app's own microphone and drives controls by name")
                    } header: {
                        Text("Accessibility")
                    }
                    // Can be switched off remotely (→ NotMyTempoFlag.instrumentSignal).
                    if NoteSignalDetector.isAvailable { noteSignalSection }
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
                                showCommands = false
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
                            // Codes from promotions and giveaways — redeemed in place.
                            Button {
                                showOfferCode = true
                            } label: {
                                Label("Redeem offer code", systemImage: "ticket")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(cue)
                            }
                            .accessibilityInputLabels(["Redeem code", "Offer code", "Redeem offer code"])
                        }
                    } header: {
                        Text("Not My Tempo Pro")
                    }
                    // Pro 선물 보내기 · 받은 코드 넣기 (→ GiftRows)
                    if let gift = pro.gift {
                        GiftRows(gift: gift, isPro: pro.isPro)
                    }
                    // 개발자 응원하기(팁). 상품이 App Store 에서 와야 줄이 선다.
                    if let tipJar = pro.tipJar {
                        Section { LeeoTipJarLink<HandsFreeMetronomeSpec>(tipJar: tipJar) }
                    }
                    Section {
                        usageRow("circle.grid.3x3", "Set beats", "Tap the dots to choose the time signature.")
                        usageRow("hand.tap", "Tap tempo", "Tap the big BPM number in rhythm to set the tempo.")
                        usageRow("slider.horizontal.3", "Tempo", "Drag the tempo slider, or tap the − / + buttons.")
                        usageRow("speaker.wave.2.fill", "Volume", "Say \u{201C}louder\u{201D} / \u{201C}quieter\u{201D} / \u{201C}mute\u{201D}, or \u{201C}volume 60\u{201D}.")
                        usageRow("music.note", "Subdivision", "Tap 1/4, 1/8, Trip, or 1/16. Double-tap the card to open Accents and set every click of the measure high, low, or silent.")
                        usageRow("circle.circle", "Switch view", "Tap the view icon (top-right of the beat card) — bounce → orbit → ring sweep.")
                        usageRow("target", "Timing check", "In orbit view, tap the ring while playing — every click (including subdivisions) is a target. The moving dot leaves a ghost where your tap landed, and coloured counters tally Perfect / Good / Bad until you stop.")
                        usageRow("chart.line.uptrend.xyaxis", "Practice mode", "Open it from Beat view below, or say \u{201C}practice\u{201D}.")
                        usageRow("play.fill", "Play", "Tap Start / Stop at the bottom.")
                        usageRow("timer", "Practice timer", "Tap the timer button next to Start, or say \u{201C}timer 5 minutes\u{201D}. It counts down while the click plays, then stops and chimes.")
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
                        commandRow("\"timer 5 minutes\"", "set a practice timer")
                        commandRow("\"timer off\"", "turn the timer off")
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
                        commandRow("\"quarter\"", "1/4 notes")
                        commandRow("\"eighth\"", "1/8 notes")
                        commandRow("\"triplet\"", "triplets")
                        commandRow("\"sixteenth\"", "1/16 notes")
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
                        commandRow("\"tune\"", "open the tuner")
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
                        commandRow("\"scroll down\" / \"scroll up\"", "move this list")
                        commandRow("\"help\"", "list the commands you can say")
                        commandRow("\"done\" / \"close\"", "close a panel or tip")
                    }
                    .id(helpSections[5])
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
                .onChange(of: helpIndex) { idx in
                    guard helpSections.indices.contains(idx) else { return }
                    withAnimation { proxy.scrollTo(helpSections[idx], anchor: .top) }
                }
            }
            .navigationTitle("Voice Commands")
            .navigationBarTitleDisplayMode(.inline)
            .offerCodeRedemption(isPresented: $showOfferCode) { _ in
                Task { await pro.refreshEntitlement() }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { showCommands = false } label: { Label("Done", systemImage: "checkmark") }
                }
            }
        }
    }

    // MARK: Instrument signal

    private var noteSignalSection: some View {
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
    private var proLockBadge: some View {
        Text("PRO")
            .font(.caption2.weight(.heavy))
            .foregroundStyle(cue)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(cue.opacity(0.15)))
            .accessibilityLabel("Requires Pro")
    }

    private func usageRow(_ icon: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
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
    private var trainerSheet: some View {
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
                    Text("Raises the tempo automatically every few bars while you play — for gradually pushing a passage faster. Stops at the target. Say \u{201C}practice\u{201D} anytime to open this.")
                }
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { showTrainer = false } label: { Label("Done", systemImage: "checkmark") }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Practice timer modal

    private var timerSheet: some View {
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
                    Text("Counts down while the click plays and pauses when you stop. When time is up the metronome stops and chimes. Say \u{201C}timer 5 minutes\u{201D} or \u{201C}timer off\u{201D} anytime.")
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
                    Button { showTimer = false } label: { Label("Done", systemImage: "checkmark") }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Quick-pick minute buttons for the practice timer.
    private func quickTimerButtons(_ minutes: [Int]) -> some View {
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
    private var tunerScreen: some View {
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
                Text("Say \"close\" to exit")
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
    private var referenceControl: some View {
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
    private func closeTuner() {
        withAnimation(tunerPageAnimation) { showTuner = false }
    }

    /// "440.0 Hz" / "440,0 Hz" — the decimal mark follows the user's region.
    private func frequencyText(_ hz: Double) -> String {
        "\(hz.formatted(.number.precision(.fractionLength(1)).grouping(.never))) Hz"
    }

    private var inTune: Bool { tuner.frequency > 0 && abs(tuner.cents) <= tuneTolerance }

    /// Spoken pitch summary for VoiceOver, replacing the visual cents meter.
    private var tunerAccessibilityValue: String {
        guard tuner.frequency > 0 else { return String(localized: "No note detected, play a note") }
        if inTune { return String(localized: "\(tuner.noteName), in tune") }
        let cents = Int(tuner.cents.rounded())
        return cents > 0
            ? String(localized: "\(tuner.noteName), \(abs(cents)) cents sharp")
            : String(localized: "\(tuner.noteName), \(abs(cents)) cents flat")
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
    private func commandRow(_ phrase: String, _ effect: LocalizedStringKey) -> some View {
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
                .foregroundStyle(cue)
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
    private func tapTempo() {
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

    private var micMessage: String {
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

    private func wireUp() {
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
    private func prepareScreenshot(_ scene: String) {
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
            case "voice": showHelp()
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

    private func openTuner() {
        guard requirePro(.tuner) else { return }
        metronome.stop()        // clicks would corrupt pitch detection
        if !voice.isListening { voice.toggle() }   // the tuner hears through the app's mic
        showCommands = false
        showAccents = false
        tuner.start()
        withAnimation(tunerPageAnimation) { showTuner = true }
        TunerTip().invalidate(reason: .actionPerformed)
    }

    /// The freemium gate. Pro features funnel through here from every entry
    /// point — buttons, voice commands, double-taps, VoiceOver actions — so the
    /// check lives in exactly one place. Locked → swap whatever was opening for
    /// the paywall, led by the feature that was just reached for.
    private func requirePro(_ feature: ProFeature) -> Bool {
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
    private func dismissVisibleTips() {
        // The tour's current stop wins the screen when it's eligible; otherwise
        // it's one of the standalone first-run tips. Retire just that one, so a
        // tip that was only queued is never lost unseen.
        let candidates: [any Tip] = [featureTips.currentTip, MicListeningTip(), VoiceControlTip(), HelpVoiceTip()]
            .compactMap { $0 }
        candidates.first { $0.shouldDisplay }?.invalidate(reason: .tipClosed)
        AppTips.snoozed = true
    }

    private func closePanels() {
        showCommands = false
        closeTuner()            // slides the page out; onChange stops the engine
        showTrainer = false
        showTimer = false
        showAccents = false
        // "close" backs out of the paywall and the What's-new card too
        withAnimation(.easeInOut(duration: 0.3)) { paywallFeature = nil }
        if showWhatsNew { closeWhatsNew() }
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
    private func openTimer() {
        showCommands = false
        withAnimation(tunerPageAnimation) { showTuner = false }
        showTrainer = false
        showAccents = false
        showTimer = true
    }

    private func openPractice() {
        guard requirePro(.practice) else { return }
        showCommands = false
        withAnimation(tunerPageAnimation) { showTuner = false }
        showAccents = false
        showTimer = false
        showTrainer = true
        PracticeTip().invalidate(reason: .actionPerformed)
    }

    private func openAccents() {
        guard requirePro(.accents) else { return }
        showCommands = false
        withAnimation(tunerPageAnimation) { showTuner = false }
        showTrainer = false
        showTimer = false
        showAccents = true
        AccentGridTip().invalidate(reason: .actionPerformed)
    }

    /// "help" pops up the list of commands you can say right now.
    private func showHelp() {
        withAnimation(tunerPageAnimation) { showTuner = false }
        showTrainer = false
        showTimer = false
        withAnimation(.easeOut(duration: 0.2)) { showHelpMarks = true }
        HelpVoiceTip().invalidate(reason: .actionPerformed)
    }

    private func dismissHelpMarks() {
        withAnimation(.easeInOut(duration: 0.2)) { showHelpMarks = false }
    }

    private func commandLabel(_ cmd: VoiceController.Command) -> String {
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

    private func pulseBeat(_ beat: Int) {
        currentBeat = beat
        beatAnchor = Date()          // anchor the smooth viz interpolation to this beat
        haptic.impactOccurred(intensity: beat == 0 ? 1.0 : 0.6)
        // Reduce Motion: skip the bounce AND the flash — the lit dot still marks the beat.
        guard !reduceMotion else { return }
        flashIsDownbeat = beat == 0
        flashOpacity = beat == 0 ? 0.18 : 0.08     // downbeat pops, the rest whisper
        withAnimation(.easeOut(duration: 0.30)) { flashOpacity = 0 }
        withAnimation(.easeOut(duration: 0.06)) { beatScale = 1.1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            withAnimation(.easeIn(duration: 0.1)) { beatScale = 1.0 }
        }
    }
}

/// The beat-visualization styles the user can cycle through.
enum BeatVizMode: String {
    case bounce   // a pendulum ball crossing the centre on every click
    case orbit    // a dot circling a ring of beat markers
    case sweep    // a radial progress ring filling once per beat, bursting at 12

    var next: BeatVizMode {
        switch self {
        case .bounce: return .orbit
        case .orbit: return .sweep
        case .sweep: return .bounce
        }
    }
}

/// Running tally of play-along taps for one run of the metronome (orbit view).
/// Title + icon, or just the icon when the row is out of room.
private struct TransportLabelStyle: LabelStyle {
    let iconOnly: Bool
    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            Label(configuration)
        }
    }
}

/// A play run at least this long counts as practice for the review prompt
/// (`LeeoEngagement`) — a few seconds of trying the click out does not.
enum PracticeMoment {
    static let minimumRun: TimeInterval = 60
}

/// 이 앱이 그 사람에게 도움이 됐다는 숫자 — 클릭에 맞춰 연습한 시간. 팁 부탁 카드가 이 숫자를 말한다.
enum NotMyTempoTipMoments {
    /// 연습한 시간(시간). 큰 것부터.
    static let hours = [100, 30, 10]
    private static let secondsKey = "practice.totalSeconds"

    /// 클릭이 멈출 때마다 그 시간을 더한다.
    static func record(practice seconds: TimeInterval) {
        guard seconds > 0 else { return }
        let total = UserDefaults.standard.double(forKey: secondsKey) + seconds
        UserDefaults.standard.set(total, forKey: secondsKey)
    }

    /// 넘어선 순간, 인상적인 것부터.
    static func reached(practiceSeconds: TimeInterval) -> [LeeoTipMoment] {
        let h = Int(practiceSeconds / 3600)
        return hours.filter { h >= $0 }.map { threshold in
            LeeoTipMoment(id: "hours.\(threshold)",
                          message: String(localized: "\(h) hours practiced with the click so far",
                                          comment: "Tip ask card: total hours practiced with the metronome running"))
        }
    }

    static var reachedNow: [LeeoTipMoment] {
        reached(practiceSeconds: UserDefaults.standard.double(forKey: secondsKey))
    }
}

struct TimingStats: Equatable {
    var perfect = 0
    var good = 0
    var bad = 0

    var total: Int { perfect + good + bad }

    mutating func record(_ verdict: TimingVerdict) {
        switch verdict {
        case .perfect: perfect += 1
        case .good: good += 1
        case .bad: bad += 1
        }
    }
}

/// A fading afterimage of the orbit's travelling dot, frozen at the position it
/// held when a play-along tap landed — its distance from the nearest marker IS
/// the timing error, made visible.
struct TapGhost: Identifiable {
    let id = UUID()
    let phase: Double            // beats-units position on the ring at tap time
    let verdict: TimingVerdict
}

/// The ghost itself: a verdict-coloured ring that swells and fades on arrival.
/// With Reduce Motion it skips the swell and only fades.
private struct GhostCircle: View {
    let color: Color
    let reduceMotion: Bool
    @State private var faded = false

    var body: some View {
        Circle()
            .fill(color.opacity(0.3))
            .overlay(Circle().strokeBorder(color, lineWidth: 2))
            .frame(width: 30, height: 30)
            // A gentle swell only — the ghost's POSITION is the information, so it
            // must stay put and readable while it fades.
            .scaleEffect(faded && !reduceMotion ? 1.3 : 1.0)
            .opacity(faded ? 0 : 0.9)
            .onAppear { withAnimation(.easeOut(duration: 1.3)) { faded = true } }
            .allowsHitTesting(false)   // never steal the next tap
    }
}

/// How close a play-along tap landed to the beat (orbit view's timing check).
enum TimingVerdict {
    case perfect, good, bad

    var label: String {
        switch self {
        case .perfect: return String(localized: "Perfect!")
        case .good: return String(localized: "Good")
        case .bad: return String(localized: "Bad")
        }
    }

    func color(cue: Color, red: Color) -> Color {
        switch self {
        case .perfect: return .green
        case .good: return cue
        case .bad: return red
        }
    }
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

/// One-time hint that the accent grid hides behind a double-tap on the
/// subdivision card — the gesture leaves no visible trace, so point it out once.
struct AccentGridTip: Tip {
    var title: Text { Text("Customize accents") }
    var message: Text? { Text("Double-tap here to open the accent grid — set every click of the measure high, low, or silent, and save patterns as presets.") }
    var image: Image? { Image(systemName: "hand.tap") }
    var rules: [Rule] { #Rule(AppTips.$snoozed) { $0 == false } }
}

/// Guided-tour stop: the big display shows the tempo as a classical term.
struct TempoDisplayTip: Tip {
    var title: Text { Text("Largo? Moderato?") }
    var message: Text? { Text("That\u{2019}s your tempo as a classical term. Tap it to flip to the BPM number and back.") }
    var image: Image? { Image(systemName: "metronome") }
    var rules: [Rule] { #Rule(AppTips.$snoozed) { $0 == false } }
}

/// Guided-tour stop: two beat visualizations to choose from.
struct VizModeTip: Tip {
    var title: Text { Text("Two beat views") }
    var message: Text? { Text("Tap to switch between the bouncing ball and the orbit ring — or say \u{201C}bounce\u{201D} / \u{201C}orbit\u{201D}.") }
    var image: Image? { Image(systemName: "circle.circle") }
    var rules: [Rule] { #Rule(AppTips.$snoozed) { $0 == false } }
}

/// Guided-tour stop: the speed trainer, which is voice-first and easy to miss.
struct PracticeTip: Tip {
    var title: Text { Text("Speed trainer") }
    var message: Text? { Text("Say \u{201C}practice\u{201D} to raise the tempo automatically every few bars while you play — great for speed drills.") }
    var image: Image? { Image(systemName: "chart.line.uptrend.xyaxis") }
    var rules: [Rule] { #Rule(AppTips.$snoozed) { $0 == false } }
}

/// Guided-tour stop: there's a chromatic tuner behind a voice command.
struct TunerTip: Tip {
    var title: Text { Text("There\u{2019}s a tuner too") }
    var message: Text? { Text("Say \u{201C}tune\u{201D} to open the chromatic tuner, and \u{201C}close\u{201D} when you\u{2019}re done.") }
    var image: Image? { Image(systemName: "tuningfork") }
    var rules: [Rule] { #Rule(AppTips.$snoozed) { $0 == false } }
}

/// One-time hint that the voice "help" command exists.
struct HelpVoiceTip: Tip {
    var title: Text { Text("Forget a command?") }
    var message: Text? { Text("Say \u{201C}help\u{201D} anytime — or tap here — to see every command you can say, then \u{201C}close\u{201D} to dismiss.") }
    var image: Image? { Image(systemName: "questionmark.circle.fill") }
    var rules: [Rule] { #Rule(AppTips.$snoozed) { $0 == false } }
}

/// Shared TipKit rule inputs. iOS exposes no API to detect system Voice Control,
/// so `usesVoiceControl` is user-declared (toggle in the Voice Commands sheet);
/// `voiceOverRunning` mirrors UIAccessibility so tips can defer to VoiceOver.
enum AppTips {
    @Parameter static var usesVoiceControl: Bool = false
    @Parameter static var voiceOverRunning: Bool = false
    /// Set when tips are closed by voice: no more tips this launch (not persisted).
    @Parameter(.transient) static var snoozed: Bool = false
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
        #Rule(AppTips.$snoozed) { $0 == false }
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
        #Rule(AppTips.$snoozed) { $0 == false }
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

// MARK: - Usage statistics switch

/// The on/off switch, shown in the help sheet above the contact links.
struct UsageStatsSection: View {
    @AppStorage(Telemetry.optOutKey) private var optOut = false

    var body: some View {
        Section {
            Toggle("Share anonymous usage statistics", isOn: Binding(
                get: { !optOut },
                set: { optOut = !$0 }))
        } header: {
            Text("Privacy")
        } footer: {
            Text("Counts like how many devices use the app and crash reports. No audio, settings or personal information. Applies from the next launch.")
        }
    }
}

// MARK: - 선물

/// Pro 칸 바로 아래의 **선물** 줄. Pro 를 다른 사람에게 보내고(보내는 사람은 소모성 선물 상품을 산다),
/// 받은 코드는 여기서 넣는다. 받는 사람은 평생 Pro 를 산 것과 같아진다(`HandsFreeMetronomeSpec.monetization`).
///
/// ⚠️ 상품이 App Store 에서 와야 줄이 선다(`isAvailable`). 상품을 만들기 전에 이 빌드가 나가도
///    눌러도 안 되는 줄은 보이지 않는다. 단, 이미 결제했거나 주고받은 선물이 있는 사람에게는 늘 보인다 —
///    상품을 못 불러온 날에도 코드를 다시 보거나 문의까지 갈 길이 있어야 한다.
/// ⚠️ 문구는 LeeoKit 카탈로그에 있다(`LeeoGiftText`) — 24개 언어가 이미 들어 있다.
/// ⚠️ 엔진(`LeeoGiftStore`)은 따로 관찰한다. 상품은 앱이 뜬 뒤에 오는데 `ProStore` 는 그 변화를 알리지 않는다.
struct GiftRows: View {
    @ObservedObject var gift: LeeoGiftStore
    let isPro: Bool
    @State private var showSupport = false

    var body: some View {
        if gift.isAvailable || gift.pendingCount > 0 || !gift.sentGifts.isEmpty || gift.redeemed != nil {
            Section {
                NavigationLink {
                    // 선물이 안 되면 결제 번호·코드를 붙여 문의하게 한다 — 막힌 사람을 놓치지 않게.
                    LeeoGiftView<HandsFreeMetronomeSpec>(gift: gift, showsRedeemLink: false,
                                                         onContactSupport: { showSupport = true })
                } label: {
                    Label(LeeoGiftText.sendEntry, systemImage: "gift.fill")
                }
                // 이미 Pro 인 사람은 받을 것이 없다 — 받은 적이 있으면 그 기록을 볼 수 있게만 남긴다.
                if !isPro || gift.redeemed != nil {
                    NavigationLink {
                        LeeoGiftRedeemView<HandsFreeMetronomeSpec>(gift: gift,
                                                                   onContactSupport: { showSupport = true })
                    } label: {
                        Label(LeeoGiftText.redeemEntry, systemImage: "giftcard")
                    }
                }
            }
            .sheet(isPresented: $showSupport) {
                NavigationStack {
                    LeeoFeedbackView<HandsFreeMetronomeSpec>(initialType: .bug, extraInfo: gift.supportLines,
                                                             initialCategory: .purchase)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button { showSupport = false } label: { Label("Done", systemImage: "checkmark") }
                            }
                        }
                }
            }
        }
    }
}

// MARK: - Developer contact

/// Contact links for the developer, shown at the bottom of the Voice Commands
/// (help) sheet — the app's only settings-like screen.
struct DeveloperContactSection: View {
    let accent: Color

    var body: some View {
        Section {
            Link(destination: URL(string: "mailto:leeo@kakao.com")!) {
                Label("Email the developer", systemImage: "envelope")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
            }
            .accessibilityInputLabels(["Email", "Email the developer"])
            Link(destination: URL(string: "https://instagram.com/lee25_ios")!) {
                Label("Instagram DM (@lee25_ios)", systemImage: "paperplane")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
            }
            .accessibilityInputLabels(["Instagram", "Instagram DM"])
        } header: {
            Text("Contact the Developer")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bug reports and feature requests are welcome.")
                // Selectable, for people whose mail app isn't Apple Mail.
                Text(verbatim: HandsFreeMetronomeSpec.developerEmail)
                    .textSelection(.enabled)
            }
        }
    }
}

/// Shared by both faces of the tuner page-turn — mismatched perspectives would
/// split the cuboid's shared edge mid-roll. Kept subtle: strong perspective
/// reads as warp, not depth, once the faces are in motion.
let cubePerspective: CGFloat = 0.28

/// One spring for every path that opens or closes the tuner page — mixed
/// curves (or an unanimated snap) would make the same roll feel like two
/// different gestures depending on how it was triggered.
let tunerPageAnimation = Animation.smooth(duration: 0.5)

/// One face of the rolling-box page turn: swings about the vertical edge it
/// shares with the neighbouring face. Animatable so the shading below tracks
/// the interpolated angle frame by frame, not just the endpoints.
struct CubeFace: ViewModifier, Animatable {
    var angle: Double
    let edge: UnitPoint   // .leading for the incoming face, .trailing for the outgoing

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0),
                              anchor: edge, perspective: cubePerspective)
            // Faces darken as they turn away — the shading carries the depth
            // cue, which lets the geometry stay gentle.
            .brightness(-abs(angle) / 90 * 0.18)
    }
}

extension AnyTransition {
    /// Roll in from the right like the side of a box turning to face front:
    /// slide from the trailing edge while unfolding 90° about the leading edge.
    /// Pair with the mirror-image rotation on the outgoing view.
    static var cubeFromTrailing: AnyTransition {
        .move(edge: .trailing).combined(with:
            .modifier(active: CubeFace(angle: 90, edge: .leading),
                      identity: CubeFace(angle: 0, edge: .leading)))
    }
}

#Preview {
    ContentView()
}
