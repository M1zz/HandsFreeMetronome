import Foundation
import StoreKit

/// Which locked feature the user bumped into — the paywall leads with it, so the
/// pitch is always "unlock the thing you just reached for", never a generic ad.
enum ProFeature: String, Identifiable, CaseIterable {
    case practice   // speed trainer
    case accents    // full-measure accent editor + presets
    case tuner      // chromatic tuner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .practice: return "Practice mode"
        case .accents:  return "Accent editor & presets"
        case .tuner:    return "Chromatic tuner"
        }
    }

    var detail: String {
        switch self {
        case .practice: return "Raise the tempo automatically every few bars — push a passage faster, hands-free."
        case .accents:  return "Design every click of the measure — high, low, or silent — and save patterns per song."
        case .tuner:    return "Say \u{201C}tune\u{201D} and play — note, cents, and an in-tune zone."
        }
    }

    var icon: String {
        switch self {
        case .practice: return "chart.line.uptrend.xyaxis"
        case .accents:  return "waveform.path"
        case .tuner:    return "tuningfork"
        }
    }
}

/// StoreKit 2 storefront for the single "Pro" entitlement.
///
/// Business model (see docs/business-strategy.md): the core metronome and every
/// voice/accessibility feature stay free forever — they are the app's identity
/// and its acquisition engine. The three "serious practice" tools (speed
/// trainer, accent editor + presets, tuner) unlock with Pro, sold as either a
/// yearly subscription (with a free trial, configured in App Store Connect) or
/// a one-time lifetime purchase.
@MainActor
final class ProStore: ObservableObject {
    static let yearlyID = "com.leeo.HandsFreeMetronome.pro.yearly"
    static let lifetimeID = "com.leeo.HandsFreeMetronome.pro.lifetime"
    static let allProductIDs = [yearlyID, lifetimeID]

    /// The app was PAID up front through 1.0.4 (builds 1 and 2). Anyone whose
    /// original download predates the freemium switch already paid for the whole
    /// app, so they keep Pro forever — hitting a paywall on features they bought
    /// would be a bait-and-switch. 1.0.5, the first freemium release, ships as
    /// build 3; on iOS `AppTransaction.originalAppVersion` reports the
    /// CFBundleVersion (build number) of the user's first download.
    static let firstFreemiumBuild = 3

    /// True while a verified entitlement (either product) is active. Seeded from
    /// a cached flag so Pro features work instantly on launch and offline; the
    /// live entitlement check corrects it as soon as StoreKit answers.
    @Published private(set) var isPro: Bool

    /// Store products, ordered yearly-first for the paywall. Empty until loaded
    /// (or when the store is unreachable — the paywall shows a retry state).
    @Published private(set) var products: [Product] = []

    @Published private(set) var isPurchasing = false
    @Published var lastError: String?

    private var updatesTask: Task<Void, Never>?
    private static let cacheKey = "proEntitlementCached"
    private static let grandfatherKey = "proGrandfathered"
    // AppTransaction.shared can raise a system App Store sign-in prompt when no
    // receipt is on disk, so attempt the grandfather check at most once per
    // launch (a positive result is cached in defaults and never re-asked).
    private var grandfatherChecked = false

    init() {
        isPro = UserDefaults.standard.bool(forKey: Self.cacheKey)
        // Transactions can arrive outside a purchase flow (renewal, refund,
        // family sharing, purchase on another device) — keep listening for the
        // app's whole lifetime and re-derive the entitlement on every event.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            // Yearly first: the subscription is the lead offer, lifetime the anchor.
            products = loaded.sorted { a, _ in a.id == Self.yearlyID }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Re-derive `isPro` from the verified current entitlements (or the paid-era
    /// grandfather clause) and cache it.
    func refreshEntitlement() async {
        var entitled = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               Self.allProductIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        if !entitled { entitled = await isGrandfathered() }
        isPro = entitled
        UserDefaults.standard.set(entitled, forKey: Self.cacheKey)
    }

    /// True when the user's first download was a paid-era build (< 3).
    /// Sandbox caveat: TestFlight/sandbox reports originalAppVersion as "1.0",
    /// so testers read as grandfathered there; production values are real.
    private func isGrandfathered() async -> Bool {
        if UserDefaults.standard.bool(forKey: Self.grandfatherKey) { return true }
        guard !grandfatherChecked else { return false }
        grandfatherChecked = true
        guard let result = try? await AppTransaction.shared,
              case .verified(let appTransaction) = result else { return false }
        guard let firstComponent = appTransaction.originalAppVersion
            .split(separator: ".").first,
              let build = Int(firstComponent) else { return false }
        let grandfathered = build < Self.firstFreemiumBuild
        if grandfathered {
            UserDefaults.standard.set(true, forKey: Self.grandfatherKey)
        }
        return grandfathered
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                }
                await refreshEntitlement()
            case .userCancelled, .pending:
                break   // no error banner — the user chose to stop, or Ask to Buy is pending
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Restore for users on a new device (also an App Review requirement).
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            // Sync can throw on cancellation; entitlements below still refresh.
        }
        grandfatherChecked = false   // sync refreshed the receipt — check anew
        await refreshEntitlement()
    }
}
