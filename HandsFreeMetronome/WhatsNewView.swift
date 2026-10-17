import SwiftUI

// MARK: - Content

/// What the "What's new" card announces. Shown once to people who were already
/// using the app when they first open this version — never to a fresh install
/// (they get the introduction instead; "new" means nothing to them).
///
/// ⚠️ When the rows change, bump `version` too. People who saw the previous
///    card are recorded as having seen `version`, so without a bump they would
///    never see the new one.
enum WhatsNewContent {
    static let version = "1.0.10"

    struct Row: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
    }

    static var rows: [Row] {[
        Row(id: "offer-code", symbol: "ticket",
            title: String(localized: "Redeem an offer code", comment: "What's new 1.0.10: title"),
            detail: String(localized: "Got a code for Pro? Enter it right in the app, on the Pro screen or under Voice Commands.",
                           comment: "What's new 1.0.10: offer code detail")),
        Row(id: "contrast", symbol: "circle.lefthalf.filled",
            title: String(localized: "Clearer with Increase Contrast", comment: "What's new 1.0.10: title"),
            detail: String(localized: "With Increase Contrast or Reduce Transparency on, beats, outlines and the help overlay are drawn bolder and solid.",
                           comment: "What's new 1.0.10: contrast detail")),
        Row(id: "large-text", symbol: "textformat.size",
            title: String(localized: "Room for the largest text", comment: "What's new 1.0.10: title"),
            detail: String(localized: "At the largest text sizes, buttons and lists rearrange so nothing gets cut off.",
                           comment: "What's new 1.0.10: large text detail")),
    ]}
}

// MARK: - Who just opened the app

/// Decides, in one place, whether this launch greets a newcomer (introduction),
/// a returning user who hasn't seen this version's card (What's new), or
/// neither. Pure, so the tests feed it the same inputs the screen does.
enum LaunchAudience: Equatable {
    case newcomer
    case returningNeedsWhatsNew
    case returning

    /// - Parameters:
    ///   - launchCount: LeeoKit's launch count, already including this launch.
    ///   - hasCompletedOnboarding: the introduction was finished or skipped.
    ///   - lastSeenWhatsNewVersion: the last What's-new card this device saw.
    static func resolve(launchCount: Int,
                        hasCompletedOnboarding: Bool,
                        lastSeenWhatsNewVersion: String?,
                        currentWhatsNewVersion: String = WhatsNewContent.version) -> LaunchAudience {
        if !hasCompletedOnboarding {
            // First launch ever — or a fresh install that quit mid-introduction
            // (the card was marked seen silently on that first launch).
            if launchCount <= 1 || lastSeenWhatsNewVersion == currentWhatsNewVersion {
                return .newcomer
            }
        }
        return lastSeenWhatsNewVersion == currentWhatsNewVersion ? .returning : .returningNeedsWhatsNew
    }
}

// MARK: - Card

/// Full-screen card, slid up in ContentView's ZStack like the paywall (a TipKit
/// popover would swallow a sheet). "Close" by voice dismisses it too.
struct WhatsNewView: View {
    let onClose: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 26) {
                    VStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(Color.cue)
                            .accessibilityHidden(true)
                        Text("What\u{2019}s new")
                            .font(.title.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Version \(WhatsNewContent.version)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 28)

                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(WhatsNewContent.rows) { row in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: row.symbol)
                                    .font(.title3)
                                    .foregroundStyle(Color.cue)
                                    .frame(width: 30)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.title).font(.headline)
                                    Text(row.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button(action: onClose) {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(Color.onCue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.cue))
            }
            .buttonStyle(.plain)
            .accessibilityInputLabels(["Continue", "Close", "Done"])
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .padding(.top, 8)
        }
        .background {
            if reduceTransparency {
                Color(.systemGroupedBackground).ignoresSafeArea()
            } else {
                Rectangle().fill(.regularMaterial).ignoresSafeArea()
            }
        }
    }
}
