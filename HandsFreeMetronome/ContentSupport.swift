import SwiftUI
import UIKit
import AppIntents
import TipKit
import LeeoKit

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
struct TransportLabelStyle: LabelStyle {
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
struct GhostCircle: View {
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
    var message: Text? { Text("Tap to switch between the bouncing ball and the orbit ring — or say \u{201C}\(voiceWord(.bounce))\u{201D} / \u{201C}\(voiceWord(.orbit))\u{201D}.") }
    var image: Image? { Image(systemName: "circle.circle") }
    var rules: [Rule] { #Rule(AppTips.$snoozed) { $0 == false } }
}

/// Guided-tour stop: the speed trainer, which is voice-first and easy to miss.
struct PracticeTip: Tip {
    var title: Text { Text("Speed trainer") }
    var message: Text? { Text("Say \u{201C}\(voiceWord(.practice))\u{201D} to raise the tempo automatically every few bars while you play — great for speed drills.") }
    var image: Image? { Image(systemName: "chart.line.uptrend.xyaxis") }
    var rules: [Rule] { #Rule(AppTips.$snoozed) { $0 == false } }
}

/// Guided-tour stop: there's a chromatic tuner behind a voice command.
struct TunerTip: Tip {
    var title: Text { Text("There\u{2019}s a tuner too") }
    var message: Text? { Text("Say \u{201C}\(voiceWord(.tune))\u{201D} to open the chromatic tuner, and \u{201C}\(voiceWord(.close))\u{201D} when you\u{2019}re done.") }
    var image: Image? { Image(systemName: "tuningfork") }
    var rules: [Rule] { #Rule(AppTips.$snoozed) { $0 == false } }
}

/// One-time hint that the voice "help" command exists.
struct HelpVoiceTip: Tip {
    var title: Text { Text("Forget a command?") }
    var message: Text? { Text("Say \u{201C}\(voiceWord(.help))\u{201D} anytime — or tap here — to see every command you can say, then \u{201C}\(voiceWord(.close))\u{201D} to dismiss.") }
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
        Text("The mic is already listening — say \u{201C}\(voiceWord(.start))\u{201D}, \u{201C}\(voiceWord(.faster))\u{201D}, or \u{201C}\(voiceWord(.help))\u{201D}. Use iOS Voice Control? Open Voice Commands to switch.")
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

/// Pro 칸 바로 아래의 **선물** 줄. 받은 App Store 코드(오퍼 코드)는 여기서 넣고,
/// 판매를 연 뒤에는(`LeeoGiftConfig.sellsGifts`) Pro 를 다른 사람에게 보낸다.
///
/// ⚠️ 보내기는 `isAvailable`(판매가 열렸고 상품이 왔다), 받기는 `canRedeem` 을 본다.
///    판매가 닫혀 있어도 이미 결제했거나 보낸 선물이 있는 사람에게는 보내기 줄이 남는다 —
///    코드를 다시 보거나 문의까지 갈 길이 있어야 한다.
/// ⚠️ 문구는 LeeoKit 카탈로그에 있다(`LeeoGiftText`) — 24개 언어가 이미 들어 있다.
/// ⚠️ 엔진(`LeeoGiftStore`)은 따로 관찰한다. 상품은 앱이 뜬 뒤에 오는데 `ProStore` 는 그 변화를 알리지 않는다.
/// 설정의 '개발자 응원하기' 줄 — 클립키보드와 같다: 제목 · 한 줄 설명 · 응원한 사람의 단계 배지.
/// 누르면 응원 화면(`LeeoTipJarView`, 지금 단계와 다음 단계 카드). 팁 상품이 App Store 에서 와야 선다.
struct TipRow: View {
    @ObservedObject var tipJar: LeeoTipJar

    var body: some View {
        if tipJar.isAvailable {
            NavigationLink {
                LeeoTipJarView<HandsFreeMetronomeSpec>(tipJar: tipJar)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LeeoTipText.entry)
                        Text(LeeoTipText.entrySubtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        LeeoSupporterBadge(tipJar: tipJar)
                            .padding(.top, 4)
                    }
                } icon: {
                    Image(systemName: "heart.fill")
                }
            }
            .task { await tipJar.syncSupporter(containerIdentifier: HandsFreeMetronomeSpec.feedback.containerIdentifier) }
        }
    }
}

/// 설정의 선물하기 한 줄. 보낼 선물이 있거나 받은 코드를 넣을 수 있을 때만 선다.
struct GiftRow: View {
    @ObservedObject var gift: LeeoGiftStore
    let isPro: Bool

    var body: some View {
        if GiftPage.sends(gift) || GiftPage.receives(gift, isPro: isPro) {
            NavigationLink {
                GiftPage(gift: gift, isPro: isPro)
            } label: {
                Label(LeeoGiftText.sendEntry, systemImage: "gift.fill")
            }
        }
    }
}

/// 선물 화면: 누르면 바로 Pro 선물을 사는 화면. 받은 코드 넣기는 맨 아래 링크(아직 Pro 가 아닌 사람만).
struct GiftPage: View {
    @ObservedObject var gift: LeeoGiftStore
    let isPro: Bool
    /// 선물이 안 될 때의 문의 창(결제 번호 · 코드가 붙는다) — 막힌 사람을 놓치지 않게.
    @State private var showSupport = false

    /// 상품이 왔거나, 이미 보낸 선물 · 준비 중인 결제가 있으면 늘 선다.
    static func sends(_ gift: LeeoGiftStore) -> Bool {
        gift.isAvailable || gift.pendingCount > 0 || !gift.sentGifts.isEmpty
    }

    /// 이미 Pro 인 사람은 받을 것이 없다 — 받은 적이 있으면 그 기록을 볼 수 있게만 남긴다.
    static func receives(_ gift: LeeoGiftStore, isPro: Bool) -> Bool {
        gift.canRedeem && (!isPro || gift.redeemed != nil)
    }

    var body: some View {
        // 클립키보드처럼 가운데 목록 없이 바로 선물 화면으로. 받은 코드 넣기는 그 화면 맨 아래 링크로.
        Group {
            if Self.sends(gift) {
                LeeoGiftView<HandsFreeMetronomeSpec>(gift: gift, showsRedeemLink: Self.receives(gift, isPro: isPro),
                                                     onContactSupport: { showSupport = true })
            } else {
                // 보낼 선물은 없고 받을 코드만 넣을 수 있을 때
                LeeoGiftRedeemView<HandsFreeMetronomeSpec>(gift: gift, onContactSupport: { showSupport = true })
            }
        }
        .navigationTitle(LeeoGiftText.sendEntry)
        .navigationBarTitleDisplayMode(.inline)
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

/// The live mic level beside "Listening". A view of its own that watches only
/// `MicLevel`, so the level's ~20 Hz updates never redraw the main screen.
struct VoiceWaveform: View {
    @ObservedObject var level: MicLevel
    let color: Color
    private static let factors: [CGFloat] = [0.45, 0.8, 1.0, 0.6, 0.95, 0.55, 0.85]

    var body: some View {
        let value = CGFloat(level.value)
        HStack(alignment: .center, spacing: 4) {
            ForEach(Self.factors.indices, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 4, height: max(4, 4 + value * 26 * Self.factors[i]))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level.value)
        .accessibilityHidden(true)   // purely decorative level meter
    }
}

// MARK: - Panels

/// What can cover the main screen. Only one is ever open — opening one closes
/// whatever was there, so no path can leave two sheets fighting for the screen.
enum Panel: Hashable {
    case commands   // voice commands & help (full screen)
    case settings   // accessibility · Pro · support
    case tuner      // the page that slides in from the right
    case trainer    // practice mode (speed trainer)
    case timer      // practice timer
    case accents    // accent grid
    case report     // how the practice-timer run went
}

extension ContentView {
    var showTuner: Bool { panel == .tuner }

    /// Open `next` (or close everything with nil). The tuner is a page, not a
    /// sheet: any change that brings it in or takes it out slides it.
    func present(_ next: Panel?) {
        guard next != panel else { return }
        let slides = panel == .tuner || next == .tuner
        withAnimation(slides ? tunerPageAnimation : nil) { panel = next }
    }

    /// A sheet's `isPresented` for one panel: swiping it away closes only that one.
    func isOpen(_ p: Panel) -> Binding<Bool> {
        Binding(get: { panel == p },
                set: { open in
                    if open { present(p) } else if panel == p { panel = nil }
                })
    }
}
