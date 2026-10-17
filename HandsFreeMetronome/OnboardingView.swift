import SwiftUI

/// First-launch introduction: three short pages, then the microphone prompt.
///
/// Before this, a fresh install went straight to two system permission alerts
/// (microphone, speech recognition) with no word on why a metronome wants
/// them — and nothing said the commands are English words in every language.
/// The app now waits for the last page before it starts listening, so the
/// alerts arrive right after the explanation.
///
/// Skippable from any page, and replayable from Voice Commands ▸ Help.
struct NotMyTempoOnboardingView: View {
    /// Persisted by the caller (`@AppStorage(hasCompletedOnboardingKey)`).
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    /// The user relies on iOS Voice Control — our own mic stays off, so the
    /// last page talks about "Tap …" names instead of asking for the mic.
    let usesVoiceControl: Bool
    let onFinish: () -> Void

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Page {
        let symbol: String
        let title: String
        let body: String
    }

    private var pages: [Page] {[
        Page(symbol: "metronome",
             title: String(localized: "A metronome you talk to", comment: "Onboarding page 1 title"),
             body: String(localized: "Say \u{201C}start\u{201D}, \u{201C}stop\u{201D}, \u{201C}faster\u{201D} or \u{201C}tempo 120\u{201D} and keep both hands on your instrument.",
                          comment: "Onboarding page 1 body. The quoted words are English voice commands; keep them in English")),
        Page(symbol: "character.bubble",
             title: String(localized: "Commands are English words", comment: "Onboarding page 2 title"),
             body: String(localized: "In every language, you control the app with short English words. Say \u{201C}help\u{201D} anytime to see them all on screen.",
                          comment: "Onboarding page 2 body. \u{201C}help\u{201D} is an English voice command; keep it in English")),
        usesVoiceControl
        ? Page(symbol: "waveform",
               title: String(localized: "Made for Voice Control", comment: "Onboarding page 3 title, Voice Control users"),
               body: String(localized: "The app\u{2019}s own mic stays off so it won\u{2019}t clash with Voice Control. Say \u{201C}Tap Start\u{201D} or \u{201C}Tap Faster\u{201D}.",
                            comment: "Onboarding page 3 body, Voice Control users"))
        : Page(symbol: "mic.fill",
               title: String(localized: "Next: the microphone", comment: "Onboarding page 3 title"),
               body: String(localized: "iOS will ask for the microphone and speech recognition. They are used only to hear your commands. The app never records or saves what it hears.",
                            comment: "Onboarding page 3 body")),
    ]}

    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if !isLast {
                    Button("Skip") { onFinish() }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityInputLabels(["Skip", "Skip introduction"])
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 20)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    pageView(pages[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if isLast {
                    onFinish()
                } else if reduceMotion {
                    page += 1
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) { page += 1 }
                }
            } label: {
                Text(isLast ? (usesVoiceControl ? String(localized: "Get started")
                                                : String(localized: "Start listening"))
                            : String(localized: "Next"))
                    .font(.headline)
                    .foregroundStyle(Color.onCue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.cue))
            }
            .buttonStyle(.plain)
            .accessibilityInputLabels(isLast ? ["Get started", "Continue", "Done"] : ["Next", "Continue"])
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private func pageView(_ p: Page) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: p.symbol)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Color.cue)
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 72 : 120)
                    .accessibilityHidden(true)
                Text(p.title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(p.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .padding(.top, dynamicTypeSize.isAccessibilitySize ? 8 : 48)
            .padding(.bottom, 56)   // clear the page dots
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
