import SwiftUI
import StoreKit
import LeeoKit

/// The Pro paywall, in the same template as ClipKeyboard's:
///
///     header            title + the one line about what the user just reached for
///     benefits          what Pro adds (three tools), the one reached for in the accent colour
///     yearly · lifetime a vertical list; each row shows the full price and what it bills
///     compare           the Free vs Pro table, folded
///     fine print        renewal terms, restore · redeem code · privacy · terms
///     ─── pinned ───
///     one buy button    for the row chosen above
///
/// **What is free comes first** in the table: the whole metronome and voice control stay free.
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
    @State private var showsComparison = false
    /// Only someone who never had the yearly plan gets its intro offer — don't promise it to others.
    @State private var introEligible = false
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
                    benefits
                    options
                    comparison
                    fineprint
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            // One buy button, always in reach, for the row chosen above.
            .safeAreaInset(edge: .bottom, spacing: 0) { purchaseBar }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        // LeeoKit parts here (the lifetime price notice) draw in the app's colours.
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
        .task(id: yearly?.id) {
            introEligible = await yearly?.subscription?.isEligibleForIntroOffer ?? false
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

    /// Title, then the one line about what the user just reached for.
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "Not My Tempo Pro")
                .font(.largeTitle.bold())
            Text(feature.detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Benefits

    /// What Pro adds — only the three tools; the free metronome is in the table below.
    private var benefits: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The whole metronome stays free. Pro adds three practice tools. Choose yearly or lifetime.")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(ProFeature.allCases) { f in
                Label {
                    Text(f.title).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(cue)
                }
                .font(.body.weight(f == feature ? .semibold : .regular))
                .foregroundStyle(f == feature ? cue : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Free vs Pro

    private var comparison: some View {
        DisclosureGroup(isExpanded: $showsComparison) {
            comparisonTable.padding(.top, 12)
        } label: {
            Text("Compare all features")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .tint(.secondary)
    }

    private var comparisonTable: some View {
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

    /// The row the buy button buys. Falls back to whichever one the store returned.
    private var chosenTerm: LeeoPlanTerm { chosen?.id == ProStore.lifetimeID ? .lifetime : .yearly }

    @ViewBuilder
    private var options: some View {
        if store.products.isEmpty {
            plansStatus
        } else {
            VStack(spacing: 10) {
                optionRow(.yearly, yearly)
                optionRow(.lifetime, lifetime)
                if chosenTerm == .lifetime { LeeoLifetimePriceNotice() }
            }
        }
    }

    /// One plan: a radio mark, its name and a small note, and on the right the full
    /// price with what it bills — never a per-month figure that blurs the billing.
    private func optionRow(_ t: LeeoPlanTerm, _ item: Product?) -> some View {
        let selected = t == chosenTerm
        return Button {
            term = t
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? cue : Color(.tertiaryLabel))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t == .yearly ? LeeoLadderText.yearly : LeeoLadderText.lifetime)
                        .font(.body.weight(.semibold))
                    if let note = caption(t) {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Text(item.map { t == .yearly ? String(format: LeeoLadderText.perYearFormat, $0.displayPrice) : $0.displayPrice } ?? " ")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? cue : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item == nil)
        .opacity(item == nil ? 0.5 : 1)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Under the name: the yearly intro offer (only for those who can get it), or how
    /// many years of yearly the lifetime price is worth.
    private func caption(_ t: LeeoPlanTerm) -> String? {
        switch t {
        case .yearly:
            guard introEligible, let offer = yearly?.subscription?.introductoryOffer else { return nil }
            if offer.paymentMode == .freeTrial { return trialLabel(offer) }
            return String(format: LeeoLadderText.introFormat, offer.displayPrice)
        case .lifetime:
            guard let yearly, let lifetime, yearly.price > 0 else { return nil }
            let years = Int(NSDecimalNumber(decimal: lifetime.price / yearly.price).doubleValue.rounded(.down))
            return years >= 2 ? String(format: LeeoLadderText.lifetimeWorthFormat, years) : nil
        }
    }

    // MARK: Pinned buy button

    private var purchaseBar: some View {
        VStack(spacing: 10) {
            buyButton
            if let error = store.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(.bar)
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
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(cue))
        }
        .buttonStyle(.plain)
        .disabled(store.isPurchasing || store.isRestoring || chosen == nil)
        .accessibilityInputLabels(chosen?.id == ProStore.lifetimeID
            ? ["Buy lifetime", "Lifetime"] : ["Subscribe", "Yearly"])
    }

    private var buyTitle: String {
        chosen?.id == ProStore.lifetimeID ? String(localized: "Buy lifetime") : String(localized: "Subscribe yearly")
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

    /// Renewal terms, then restore · redeem · policies — at the bottom of the page.
    private var fineprint: some View {
        VStack(alignment: .leading, spacing: 12) {
            renewalDisclosure
            footerLinks
        }
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
