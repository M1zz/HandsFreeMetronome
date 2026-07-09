import SwiftUI
import StoreKit

/// The Pro paywall. Presented when a locked feature is reached (voice command,
/// double-tap, Help launcher…), leading with THAT feature so the pitch stays
/// concrete. Free features are listed as "yours forever" — the paywall must
/// never feel like the free app is being taken away.
struct PaywallView: View {
    @ObservedObject var store: ProStore
    /// The feature whose gate the user hit — pinned to the top of the list.
    let feature: ProFeature
    /// Rendered as a full-screen overlay (NOT a sheet — an active TipKit popover
    /// silently swallows UIKit sheet presentations), so closing is the owner's job.
    let onClose: () -> Void

    private let brass = Color(red: 0.84, green: 0.56, blue: 0.09)

    /// The tapped feature first, then the other Pro features.
    private var orderedFeatures: [ProFeature] {
        [feature] + ProFeature.allCases.filter { $0 != feature }
    }

    var body: some View {
        // Not a NavigationStack: this view is inserted mid-animation as a
        // ZStack overlay, and a nav stack paints an empty white surface until
        // its bar resolves — the slide-up would flash blank. The hand-rolled
        // header renders on the transition's very first frame.
        VStack(spacing: 0) {
            ZStack {
                Text("Not My Tempo Pro").font(.headline)
                HStack {
                    Button("Not now") { onClose() }
                        .accessibilityInputLabels(["Not now", "Close", "Dismiss"])
                    Spacer()
                    Button("Restore") { Task { await store.restore() } }
                        .accessibilityHint("Restores a previous Pro purchase")
                        .accessibilityInputLabels(["Restore", "Restore purchases"])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 22) {
                    header
                    featureList
                    purchaseButtons
                    freeReassurance
                    footerLinks
                }
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        // A successful purchase (or restore) closes the paywall by itself,
        // dropping the user straight into the feature they reached for.
        .onChange(of: store.isPro) { unlocked in
            if unlocked { onClose() }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: feature.icon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(brass)
                .accessibilityHidden(true)
            Text(feature.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text("is part of Pro — three practice tools, one unlock.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var featureList: some View {
        VStack(spacing: 0) {
            ForEach(orderedFeatures) { f in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: f.icon)
                        .font(.title3)
                        .foregroundStyle(brass)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.title).font(.subheadline.weight(.semibold))
                        Text(f.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                if f != orderedFeatures.last { Divider() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    @ViewBuilder
    private var purchaseButtons: some View {
        if store.products.isEmpty {
            // Store unreachable (offline / products not yet approved): degrade
            // to a retry, never a dead end.
            VStack(spacing: 10) {
                Text(store.lastError == nil
                     ? "Loading prices…"
                     : "Couldn\u{2019}t reach the App Store.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try again") { Task { await store.loadProducts() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(brass)
            }
            .padding(.vertical, 8)
        } else {
            VStack(spacing: 10) {
                ForEach(store.products, id: \.id) { product in
                    purchaseButton(product)
                }
                if store.products.contains(where: { $0.subscription?.introductoryOffer != nil }) {
                    Text("Cancel anytime in Settings. The trial converts unless cancelled.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func purchaseButton(_ product: Product) -> some View {
        let isLifetime = product.id == ProStore.lifetimeID
        let trial = product.subscription?.introductoryOffer
        return Button {
            Task { await store.purchase(product) }
        } label: {
            VStack(spacing: 2) {
                Text(isLifetime ? "Lifetime — \(product.displayPrice) once"
                                : trialLabel(trial, price: product.displayPrice))
                    .font(.headline)
                Text(isLifetime ? "Pay once, yours forever"
                                : "\(product.displayPrice) per year")
                    .font(.caption)
                    .opacity(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(isLifetime ? brass : Color.white)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isLifetime ? brass.opacity(0.15) : brass))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(brass.opacity(isLifetime ? 0.4 : 0), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(store.isPurchasing)
        .opacity(store.isPurchasing ? 0.6 : 1)
        .accessibilityLabel(isLifetime ? "Buy lifetime for \(product.displayPrice)"
                                       : "Subscribe yearly for \(product.displayPrice)")
        .accessibilityInputLabels(isLifetime ? ["Lifetime", "Buy lifetime"]
                                             : ["Yearly", "Subscribe"])
    }

    private func trialLabel(_ offer: Product.SubscriptionOffer?, price: String) -> String {
        guard let offer, offer.paymentMode == .freeTrial else { return "Yearly — \(price)" }
        let unit: String
        switch offer.period.unit {
        case .day: unit = offer.period.value == 7 ? "week" : "\(offer.period.value) days"
        case .week: unit = offer.period.value == 1 ? "week" : "\(offer.period.value) weeks"
        case .month: unit = offer.period.value == 1 ? "month" : "\(offer.period.value) months"
        case .year: unit = "year"
        @unknown default: unit = "trial"
        }
        return "Try free for a \(unit)"
    }

    /// What stays free — spelled out so the gate never reads as a shakedown.
    private var freeReassurance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Free forever, no unlock needed:", systemImage: "checkmark.seal.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("The full metronome — every tempo, meter, and subdivision — all three beat views, tap tempo, timing check, and complete hands-free voice control.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var footerLinks: some View {
        HStack(spacing: 16) {
            Link("Privacy", destination: URL(string: "https://m1zz.github.io/HandsFreeMetronome/privacy.html")!)
            Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom, 6)
    }
}
