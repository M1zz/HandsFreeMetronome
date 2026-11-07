import SwiftUI
import UIKit
import AppIntents
import TipKit
import LeeoKit

struct ContentView: View {
    @StateObject var metronome = MetronomeEngine.shared
    @StateObject var voice = VoiceController()
    /// English or the app language's own command words (→ VoiceVocabulary.swift).
    /// Also redraws every quoted command on screen when it changes.
    @AppStorage(VoiceLanguage.storageKey) var voiceLanguage = VoiceLanguage.english.rawValue
    @StateObject var tuner = TunerEngine()
    @StateObject var noteSignal = NoteSignalDetector()
    @StateObject var pro = ProStore()

    // A locked Pro feature was reached — which one shapes the paywall's pitch.
    @State var paywallFeature: ProFeature?

    @State var beatScale: CGFloat = 1.0
    @State var currentBeat = -1   // which beat (0-based) is sounding now
    /// The one panel covering the main screen, if any (→ `Panel`, `present(_:)`).
    @State var panel: Panel?
    @State var showSavePreset = false     // name prompt for a new accent preset
    @State var presetNameDraft = ""       // text field backing the prompt
    @State var showHelpMarks = false   // "help" → quick "what can I say" list
    @State var hintDismissed = false   // hide "tap dots" after first tap/start
    @State var didLaunch = false       // launch-only work in onAppear has run
    @State var didAutoStart = false    // auto-enable listening once on launch
    @State var muteProgress: CGFloat = 1   // Listen-button countdown ring (1→0)
    @State var lastCommandText = ""     // last recognized voice command
    @State var flashingCommand = false  // briefly show the command on the Mute button
    @State var flashToken = 0           // invalidates stale flash timers
    @State var helpIndex = 0            // voice-driven scroll position in Help
    @State var tapTimes: [TimeInterval] = []   // recent taps for tap-tempo
    @State var timingVerdict: TimingVerdict?   // orbit tap-accuracy readout
    @State var timingToken = 0                 // invalidates stale fade-outs
    @State var timingStats = TimingStats()     // running tally of play-along taps
    @State var tapGhosts: [TapGhost] = []      // fading rings where taps landed
    @State var flashOpacity: Double = 0        // whole-screen beat flash (0…~0.2)
    @State var flashIsDownbeat = false         // red flash on beat 1, cue otherwise
    @AppStorage("tempoAsNumber") var tempoAsNumber = false   // big display: term vs. BPM
    @State var beatAnchor = Date()   // wall-clock moment the current beat fired
    // Which beat visualization is showing. Persisted so it survives relaunch.
    @AppStorage("beatVizMode") var vizModeRaw = BeatVizMode.bounce.rawValue
    let helpSections = ["howto", "playback", "tempo", "subdivision", "tuner", "scrolling"]

    // Feature-discovery tips, surfaced one at a time in a guided order (TipGroup)
    // so popovers never pile up. Each is dismissed for good once its feature is
    // used, which advances the tour to the next stop.
    @State var featureTips = TipGroup(.ordered) {
        AccentGridTip()
        TempoDisplayTip()
        VizModeTip()
        PracticeTip()
        TunerTip()
    }

    // Spoken once, the first time a VoiceOver user opens the app.
    @AppStorage("didIntroduceVoiceOver") var didIntroduceVoiceOver = false

    // The user relies on iOS system Voice Control. There is no public API to detect
    // this, so it is a user-declared setting (toggled in the Voice Commands sheet).
    // When on, we keep our OWN mic off to avoid two speech recognizers fighting over
    // the input — the user drives every control by its name ("Tap Start", "Tap Faster").
    @AppStorage("usesVoiceControl") var usesVoiceControl = false

    // First-launch introduction and the once-per-version "What's new" card.
    // Both ride in the ZStack like the paywall (a TipKit popover swallows sheets).
    @AppStorage(NotMyTempoOnboardingView.hasCompletedOnboardingKey) var hasCompletedOnboarding = false
    @AppStorage("lastSeenWhatsNewVersion") var lastSeenWhatsNewVersion = ""
    @State var showOnboarding = false
    @State var showWhatsNew = false
    @State var playStartedAt: Date?         // a run long enough to count as practice
    @State var showReviewGate = false       // "Enjoying Not My Tempo?" right after practice
    @State var practiceJustEnded = false    // 연습을 막 마쳤다 — 팁 부탁이 설 수 있는 자리

    // Landscape on iPhone reports a compact height → switch to a two-column layout.
    @Environment(\.verticalSizeClass) var vSizeClass
    @Environment(\.horizontalSizeClass) var hSizeClass
    // iPhone Duo unfolded: controls on one side of the fold, the beat on the other (LeeoKit Fold).
    @Environment(\.foldLayout) var fold
    // Accessibility preferences we honour throughout the UI.
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor
    // Assistive Access (iOS 18+): when the app runs inside the simplified system
    // experience for people with cognitive disabilities, we show a distilled UI.
    @Environment(\.accessibilityAssistiveAccessEnabled) var assistiveAccess
    // Increase Contrast: dimmed beats and hairline outlines are drawn stronger.
    @Environment(\.colorSchemeContrast) var contrast
    // Reduce Transparency: the help overlay's see-through scrims turn solid.
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    // Accessibility text sizes: crowded rows rearrange instead of truncating.
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    // Dynamic Type: scale the big fixed-size displays with the user's text setting.
    @ScaledMetric(relativeTo: .largeTitle) var bpmFontSize: CGFloat = 52
    @ScaledMetric(relativeTo: .largeTitle) var standTempoSize: CGFloat = 128   // iPad on a music stand, read from ~1 m
    @ScaledMetric(relativeTo: .largeTitle) var noteFontSize: CGFloat = 96
    @ScaledMetric(relativeTo: .title) var stepIconSize: CGFloat = 30

    // Key colour and downbeat red — see Palette.swift for why these two.
    let cue = Color.cue
    let beatRed = Color.beatRed
    let haptic = UIImpactFeedbackGenerator(style: .light)
    let sliderHaptic = UISelectionFeedbackGenerator()   // per-BPM detent on the tempo slider
    let maxBeats = MetronomeEngine.maxBeatsPerMeasure
    let tuneTolerance: Double = 10   // ± cents counted as "in tune"

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
                        } else if isStand {
                            standLayout
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
        // Bluetooth page-turn pedal or keyboard: tempo and start/stop (→ PedalKeys.swift).
        .pedalKeys(enabled: !showOnboarding && !showWhatsNew && paywallFeature == nil
                    && panel != .tuner && panel != .commands && panel != .settings,
                   nudge: { metronome.nudge($0) }, toggle: { metronome.toggle() })
        .fullScreenCover(isPresented: isOpen(.commands)) { commandsSheet.foldConfined() }
        .sheet(isPresented: isOpen(.settings)) { settingsSheet.foldConfined() }
        // The tuner engine follows the page's visibility (it used to be the
        // sheet's onDismiss) — stopped on ANY path that closes it.
        .onChange(of: voiceLanguage) { _, raw in
            voice.setLanguage(VoiceLanguage(rawValue: raw) ?? .english)
        }
        .onChange(of: showTuner) { _, open in
            if !open {
                tuner.stop()
                // Voice Control mode: the mic was only borrowed for tuning.
                if usesVoiceControl && voice.isListening { voice.stop() }
            }
            noteSignal.setSuspended(open)   // tuning a string must not fire the signal
            voice.holdsOpen = open          // quiet tuning must not auto-mute the mic
        }
        .sheet(isPresented: isOpen(.trainer)) { trainerSheet }
        .sheet(isPresented: isOpen(.timer)) { timerSheet }
        // Practice timer ran out (the engine already stopped and chimed): a firm
        // haptic for players who can't hear the chime over their instrument, and
        // a spoken cue for VoiceOver.
        .onChange(of: metronome.practiceTimerFinished) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIAccessibility.post(notification: .announcement,
                                 argument: String(localized: "Practice time is up"))
            // A finished timed session is the clearest "this app did its job" moment.
            LeeoEngagement.shared.registerSignificantEvent()
            askForReviewAfterPractice()
        }
        .sheet(isPresented: isOpen(.accents)) { accentsSheet }
        .leeoReviewGate(HandsFreeMetronomeSpec.self, isPresented: $showReviewGate)
        .onChange(of: metronome.isPlaying) { _, playing in
            if playing {
                // Tell Siri the player started the click, so it learns this app does that.
                IntentDonationManager.shared.donate(intent: StartMetronomeIntent())
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
        .onChange(of: voice.activityToken) { restartMuteCountdown() }
        .onChange(of: voice.isListening) { _, listening in
            if !listening { muteProgress = 1 }
        }
        .onAppear {
            // Once per launch. A full-screen cover (Voice commands) makes this view
            // disappear and appear again; re-running would rewire the mic callback
            // while the audio thread reads it, and redo launch-only work.
            guard !didLaunch else { return }
            didLaunch = true
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
                        present(.tuner)
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
        .onChange(of: usesVoiceControl) { _, on in
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
    func syncTipState() {
        AppTips.usesVoiceControl = usesVoiceControl
        AppTips.voiceOverRunning = UIAccessibility.isVoiceOverRunning
    }

    /// One-time spoken orientation for VoiceOver users: this is a voice-driven
    /// metronome whose mic is already listening, plus the key commands and the
    /// reassurance that every control also works with VoiceOver gestures.
    func introduceVoiceOverIfNeeded() {
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
    func askForReviewAfterPractice() {
        guard LeeoReviewRequest.shouldRequest() else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            let busy = metronome.isPlaying || paywallFeature != nil || showOnboarding || showWhatsNew
                || panel != nil || showSavePreset
                || showReviewGate
            // Both a timer run-out and the stop it causes land here; the first one asks.
            guard !busy, LeeoReviewRequest.shouldRequest() else { return }
            LeeoReviewRequest.markRequested()
            showReviewGate = true
        }
    }

    /// Once per launch: a newcomer gets the introduction, someone who updated
    /// gets this version's What's-new card, everyone else goes straight in.
    func greetIfNeeded() {
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

    func finishOnboarding() {
        hasCompletedOnboarding = true
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { showOnboarding = false }
        AppTips.snoozed = false
        // Listening (and with it the permission alerts) starts now that the
        // last page has said why.
        didAutoStart = true
        startListeningIfAppropriate()
        introduceVoiceOverIfNeeded()
    }

    func closeWhatsNew() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { showWhatsNew = false }
        AppTips.snoozed = false
    }

    /// Listen by default — UNLESS the user relies on iOS Voice Control, in
    /// which case our own mic would fight the system recognizer.
    func startListeningIfAppropriate() {
        #if DEBUG
        // -nolisten: screens checked on a simulator without the permission alert on top.
        if ProcessInfo.processInfo.arguments.contains("-nolisten") { return }
        #endif
        if !usesVoiceControl && !voice.isListening { voice.toggle() }
    }

    /// Replay from the help sheet.
    func replayOnboarding() {
        panel = nil
        AppTips.snoozed = true
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { showOnboarding = true }
    }

    func reopenWhatsNew() {
        panel = nil
        AppTips.snoozed = true
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { showWhatsNew = true }
    }

    // MARK: Layouts

    /// Portrait: the cards scroll if they don't all fit (small phones / large type),
    /// with the transport bar pinned to the bottom so Start/Stop is always reachable.
    /// Once playing, the setup cards fade away so only the beat + tempo remain.
    var portraitLayout: some View {
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
            // The timer and voice strips are pinned just above the transport, so the time
            // left, "Listening" and the last heard command are never buried below the scroll.
            timerRow
                .padding(.horizontal, 16)
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


    // MARK: iPad on a music stand

    /// iPad with room in both directions (full screen, or a wide Split View pane). A narrow
    /// Split View / Slide Over window is compact width and keeps the phone layout, whose
    /// beat card stays on top — so the pulse is never lost next to a score app.
    var isStand: Bool {
        hSizeClass == .regular && vSizeClass == .regular && !fold.isUnfolded
    }

    /// Read from about a metre away, with the eyes on the score: the beat takes most of the
    /// screen and the tempo is a huge number; everything else stays on this one screen.
    /// Landscape: beat | tempo + controls. Portrait: beat on top, tempo and controls below.
    var standLayout: some View {
        GeometryReader { outer in
            #if DEBUG
            // -landscape: lay the stand screen out on its side, so the landscape arrangement
            // can be checked on a simulator that has no window to rotate.
            let turned = ProcessInfo.processInfo.arguments.contains("-landscape")
            #else
            let turned = false
            #endif
            let size = turned ? CGSize(width: outer.size.height, height: outer.size.width) : outer.size
            standArrangement(size)
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(turned ? 90 : 0))
                .position(x: outer.size.width / 2, y: outer.size.height / 2)
        }
    }

    func standArrangement(_ size: CGSize) -> some View {
        let wide = size.width > size.height
        return Group {
            if wide {
                HStack(alignment: .top, spacing: 20) {
                    standBeat
                    VStack(spacing: 14) {
                        // Playing, the tempo sits mid-column, level with the beat.
                        if metronome.isPlaying { Spacer(minLength: 0) }
                        tempoCard
                        if !metronome.isPlaying {
                            subdivisionCard.transition(.opacity)
                            voiceCard.transition(.opacity)
                            pedalHint.transition(.opacity)
                            tipAsk
                        }
                        Spacer(minLength: 0)
                        timerRow
                        transportBar
                    }
                    .frame(width: min(460, size.width * 0.4))
                }
            } else {
                VStack(spacing: 14) {
                    standBeat
                    tempoCard
                    if !metronome.isPlaying {
                        HStack(alignment: .top, spacing: 14) {
                            subdivisionCard
                            voiceCard
                        }
                        .transition(.opacity)
                        pedalHint.transition(.opacity)
                        tipAsk
                    }
                    timerRow
                    transportBar
                }
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .animation(.easeInOut(duration: 0.35), value: metronome.isPlaying)
    }

    /// The beat card blown up to fill its space: drawn at a phone-like size, then scaled,
    /// so the balls, ring and count all grow together and stay in proportion.
    var standBeat: some View {
        GeometryReader { g in
            let k = min(2.6, max(1, min(g.size.width / 400, g.size.height / 340)))
            beatDots
                .frame(width: g.size.width / k, height: g.size.height / k)
                .scaleEffect(k)
                .position(x: g.size.width / 2, y: g.size.height / 2)
        }
    }

    /// What the pedal does — page-turn pedals send these keys.
    var pedalHint: some View {
        Label("Page-turn pedal: right is faster, left is slower. Keyboard: → ← and Space to start or stop.",
              systemImage: "keyboard")
            .font(.footnote)
            .foregroundStyle(Color(.label).opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    /// 연습을 막 마친 자리의 팁 부탁(`NotMyTempoTipMoments`). 이미 Pro 를 가진 사람에게만 —
    /// 아직 안 산 사람에게는 페이월이 맞는 길이다. 드물게 묻는 규칙은 LeeoKit 이 지킨다.
    @ViewBuilder var tipAsk: some View {
        if practiceJustEnded, pro.isPro, let tipJar = pro.tipJar {
            LeeoTipAskSlot<HandsFreeMetronomeSpec>(tipJar: tipJar, reached: NotMyTempoTipMoments.reachedNow)
                .transition(.opacity)
        }
    }

    /// Landscape (compact height): two columns so everything stays on one screen.
    /// Left holds the beats + tempo; right holds subdivision, voice status, transport.
    var landscapeLayout: some View {
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
                timerRow
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
    var assistiveAccessLayout: some View {
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
    func aaButton(_ title: LocalizedStringKey, icon: String, tint: Color,
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

}
