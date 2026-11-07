import SwiftUI
import StoreKit
import LeeoKit

/// The Pro paywall, in the shared Leeo layout: header, a Free vs Pro table, then
/// yearly / lifetime (`LeeoTermPicker`) and one buy button, then restore and terms.
///
/// **What is free comes first.** Most rows of the table are ✓ in both columns — the
/// whole metronome and voice control stay free; Pro only adds three practice tools.
/// The feature the user just reached for is highlighted in the table.
struct PaywallView: View {
    @ObservedObject var store: ProStore
    /// The feature whose gate the user hit — highlighted in the table.
    let feature: ProFeature
    /// Rendered as a full-screen overlay (NOT a sheet — an active TipKit popover
    /// silently swallows UIKit sheet presentations), so closing is the owner's job.
    let onClose: () -> Void

    private let cue = Color.cue   // see Palette.swift
    @State private var term: LeeoPlanTerm = .yearly
    @State private var showOfferCode = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Not a NavigationStack: this view is inserted mid-animation as a
        // ZStack overlay, and a nav stack paints an empty white surface until
        // its bar resolves — the slide-up would flash blank. The hand-rolled
        // bar renders on the transition's very first frame.
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    comparison
                    plans
                    footerLinks
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        // The yearly / lifetime picker draws in the app's colours.
        .leeoStyle(LeeoStyle(accent: cue,
                             bg: Color(.systemGroupedBackground),
                             surface: Color(.secondarySystemGroupedBackground),
                             surfaceAlt: Color(.tertiarySystemGroupedBackground),
                             radiusSm: 12, radiusLg: 16))
        // Stale messages from a previous visit would read as answers to
        // questions the user hasn't asked yet — reset, and give prices another
        // chance if the launch-time load came up empty (offline, propagation).
        .onAppear {
            store.lastError = nil
            Task { await store.loadProducts() }   // no-op once the set is complete
        }
        // A successful purchase (or restore) closes the paywall by itself,
        // dropping the user straight into the feature they reached for.
        .onChange(of: store.isPro) { _, unlocked in
            if unlocked { onClose() }
        }
        // Promo / giveaway codes. A redeemed code lands as a transaction, which
        // the refresh turns into Pro — and the onChange above closes the paywall.
        .offerCodeRedemption(isPresented: $showOfferCode) { _ in
            Task { await store.refreshEntitlement() }
        }
    }

    // MARK: Bar

    /// Close on the left, always reachable: leaving must never require hunting for the exit.
    private var topBar: some View {
        HStack {
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .disabled(store.isPurchasing || store.isRestoring)
            .accessibilityLabel("Close")
            .accessibilityInputLabels(["Close", "Not now", "Dismiss"])
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: feature.icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(cue)
                .frame(width: 72, height: 72)
                .background(Circle().fill(cue.opacity(0.14)))
                .accessibilityHidden(true)
            Text(verbatim: "Not My Tempo Pro")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("The whole metronome stays free. Pro adds three practice tools. Choose yearly or lifetime.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Free vs Pro

    private var comparison: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Text("Feature")
                Text("Free").gridColumnAlignment(.center)
                Text(verbatim: "Pro").gridColumnAlignment(.center)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
            Divider().gridCellColumns(3)
            row(String(localized: "Every tempo, meter and subdivision"))
            row(String(localized: "Three beat views and tap tempo"))
            row(String(localized: "Hands-free voice control"))
            row(String(localized: "Timing check and practice timer"))
            ForEach(ProFeature.allCases) { f in
                row(f.title, pro: f)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    /// One row. `pro` set → a Pro-only row (– in the Free column); the one the user
    /// reached for is drawn in the accent colour.
    private func row(_ title: String, pro: ProFeature? = nil) -> some View {
        let highlighted = pro == feature
        return GridRow {
            Text(title).fixedSize(horizontal: false, vertical: true)
            cell(included: pro == nil)
            cell(included: true)
        }
        .font(.body.weight(highlighted ? .semibold : .regular))
        .foregroundStyle(highlighted ? cue : .primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(pro == nil ? String(localized: "Included free") : String(localized: "Pro only"))
    }

    private func cell(included: Bool) -> some View {
        Group {
            if included {
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(cue)
            } else {
                Text(verbatim: "–").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 48)
    }

    // MARK: Plans

    private var yearly: Product? { store.products.first { $0.id == ProStore.yearlyID } }
    private var lifetime: Product? { store.products.first { $0.id == ProStore.lifetimeID } }
    /// The plan the button buys. Falls back to whichever one the store returned.
    private var chosen: Product? { term == .yearly ? (yearly ?? lifetime) : (lifetime ?? yearly) }

    @ViewBuilder
    private var plans: some View {
        if store.products.isEmpty {
            plansStatus
        } else {
            VStack(alignment: .leading, spacing: 14) {
                LeeoTermPicker(term: $term, yearly: yearly, lifetime: lifetime)
                buyButton
                if let error = store.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                renewalDisclosure
            }
            // LeeoTermPicker is meant to sit inside a card: its unselected option
            // is drawn in `surfaceAlt`, which only reads against the card.
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    private var buyButton: some View {
        Button {
            guard let chosen else { return }
            Task { await store.purchase(chosen) }
        } label: {
            Group {
                if store.isPurchasing {
                    ProgressView().tint(Color.onCue)
                } else {
                    Text(buyTitle)
                }
            }
            .font(.headline)
            .foregroundStyle(Color.onCue)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(cue))
        }
        .buttonStyle(.plain)
        .disabled(store.isPurchasing || store.isRestoring || chosen == nil)
        .accessibilityInputLabels(chosen?.id == ProStore.lifetimeID
            ? ["Buy lifetime", "Lifetime"] : ["Subscribe", "Yearly"])
    }

    private var buyTitle: String {
        guard let chosen else { return String(localized: "Subscribe yearly") }
        if chosen.id == ProStore.lifetimeID { return String(localized: "Buy lifetime") }
        if let trial = chosen.subscription?.introductoryOffer, trial.paymentMode == .freeTrial {
            return trialLabel(trial)
        }
        return String(localized: "Subscribe yearly")
    }

    /// Whole sentences per period — a translated unit word can't be spliced
    /// into "Try free for a …" in most languages.
    private func trialLabel(_ offer: Product.SubscriptionOffer) -> String {
        let n = offer.period.value
        switch offer.period.unit {
        case .day where n == 7, .week where n == 1: return String(localized: "Try free for a week")
        case .day: return String(localized: "Try free for \(n) days")
        case .week: return String(localized: "Try free for \(n) weeks")
        case .month where n == 1: return String(localized: "Try free for a month")
        case .month: return String(localized: "Try free for \(n) months")
        case .year: return String(localized: "Try free for a year")
        @unknown default: return String(localized: "Free trial")
        }
    }

    /// Store unreachable (offline / products not yet approved): degrade to a retry,
    /// never a dead end.
    private var plansStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.lastError == nil {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading prices…").foregroundStyle(.secondary)
                }
            } else {
                Text("Couldn\u{2019}t load prices from the App Store.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    store.lastError = nil
                    Task { await store.loadProducts() }
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise").font(.body.weight(.semibold))
                }
                .foregroundStyle(cue)
            }
        }
        .font(.body)
    }

    /// App Review 3.1.2: auto-renew terms must be stated next to the price.
    @ViewBuilder
    private var renewalDisclosure: some View {
        if let yearly {
            Text("The yearly plan auto-renews at \(yearly.displayPrice)/year until cancelled at least 24 hours before renewal, in Settings > Apple Account > Subscriptions. Lifetime is a single one-time charge.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Restore · terms

    /// Each language links its own policy page (docs/<lang>/privacy.html); a
    /// malformed translation falls back to the English page instead of crashing.
    private var localizedPrivacyURL: URL {
        let english = URL(string: "https://m1zz.github.io/HandsFreeMetronome/privacy.html")!
        return URL(string: String(localized: "privacy-policy-url", defaultValue: "https://m1zz.github.io/HandsFreeMetronome/privacy.html")) ?? english
    }

    /// Purchase actions on one line, policy links on the next. Each line stacks
    /// vertically at accessibility text sizes, where side by side would clip.
    private var footerLinks: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 20))
        return VStack(alignment: .leading, spacing: 12) {
            layout {
                if store.isRestoring {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Restore Purchases") { Task { await store.restore() } }
                        .disabled(store.isPurchasing)
                        .accessibilityHint("Restores a previous Pro purchase")
                        .accessibilityInputLabels(["Restore", "Restore purchases"])
                }
                // Promo and giveaway codes for Pro.
                Button("Redeem Code") { showOfferCode = true }
                    .disabled(store.isPurchasing)
                    .accessibilityInputLabels(["Redeem code", "Offer code"])
            }
            layout {
                Link("Privacy Policy", destination: localizedPrivacyURL)
                Link("Terms of Use (EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
        }
        .font(.subheadline)
        .tint(cue)
        .padding(.bottom, 6)
    }
}
