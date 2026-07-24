import Foundation
import Combine
import StoreKit
import LeeoKit

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

/// StoreKit 2 storefront for the single "Pro" entitlement — now a thin façade.
///
/// The raw StoreKit 2 plumbing (product loading, purchase/restore, the lifetime
/// transaction listener, verification, entitlement tracking, and the offline
/// cache) is shared infrastructure that lives in LeeoKit's `LeeoStore`. This
/// type keeps its exact public API so `ContentView` and `PaywallView` keep
/// working unchanged, and layers the two things that are genuinely
/// app-specific on top of the shared engine:
///   - the paid-era **grandfather** clause (AppTransaction) → `grandfather:`
///   - the **DEBUG dev unlock** (unlocked unless `-paywall`) → `unlockOverride:`
///
/// Business model (see docs/business-strategy.md): the core metronome and every
/// voice/accessibility feature stay free forever. The three "serious practice"
/// tools (speed trainer, accent editor + presets, tuner) unlock with Pro, sold
/// as either a yearly subscription (with a free trial, configured in App Store
/// Connect) or a one-time lifetime purchase.
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

    /// Cached grandfather flag. A positive grandfather result is written here so
    /// the (potentially prompt-raising) AppTransaction check is never re-asked.
    private static let grandfatherKey = "proGrandfathered"

    #if DEBUG
    /// Dev builds run unlocked — the developer dogfoods Pro features daily and
    /// the paywall must never block that. Launch with -paywall (or the
    /// -uitest-paywall hook) to put the real gate back for testing purchases.
    private static var debugUnlocked: Bool {
        let args = ProcessInfo.processInfo.arguments
        return !args.contains("-paywall") && !args.contains("-uitest-paywall")
    }
    #endif

    /// The shared StoreKit engine. Owned privately — the app only ever touches
    /// it through this façade's forwarding API below.
    private let store: LeeoStore
    private var cancellable: AnyCancellable?

    init() {
        store = LeeoStore(
            config: HandsFreeMetronomeSpec.paywall!,
            unlockOverride: {
                // Dev override lives here, NOT in the persisted cache — a cached
                // `true` would leak Pro into a later -paywall test run. LeeoStore
                // re-evaluates this on every entitlement read and never caches it.
                #if DEBUG
                return Self.debugUnlocked ? true : nil
                #else
                return nil
                #endif
            },
            grandfather: {
                // Only the production App Store reports a real originalAppVersion.
                // Sandbox and TestFlight report "1.0", which would grandfather
                // EVERY reviewer and auto-unlock Pro — so the paywall (where the
                // IAPs live) never appears and App Review, which runs in the
                // sandbox, files a 2.1(b) "can't locate the In-App Purchases"
                // rejection. Gate the clause to production.
                #if DEBUG
                // Dev builds have no App Store receipt, so AppTransaction.shared
                // throws up a system Apple-Account sign-in sheet — right on top
                // of the paywall. Sandbox receipts also report originalAppVersion
                // as "1.0", which would mark every tester as grandfathered and
                // make the paywall untestable. Production installs always carry a
                // receipt, so the real check below runs silently there.
                return false
                #else
                if UserDefaults.standard.bool(forKey: Self.grandfatherKey) { return true }
                guard let result = try? await AppTransaction.shared,
                      case .verified(let appTransaction) = result else { return false }
                guard appTransaction.environment == .production else { return false }
                guard let firstComponent = appTransaction.originalAppVersion
                    .split(separator: ".").first,
                      let build = Int(firstComponent) else { return false }
                let grandfathered = build < Self.firstFreemiumBuild
                if grandfathered {
                    UserDefaults.standard.set(true, forKey: Self.grandfatherKey)
                }
                return grandfathered
                #endif
            }
        )
        // Forward the shared store's state changes to this façade's observers so
        // existing @ObservedObject/@StateObject bindings refresh unchanged.
        cancellable = store.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Public state (unchanged API, forwarded to LeeoStore)

    /// True while a verified entitlement (either product), the paid-era
    /// grandfather clause, or the DEBUG dev unlock is active.
    var isPro: Bool { store.hasPro }

    /// Store products, ordered yearly-first for the paywall (config order).
    var products: [Product] { store.products }

    var isPurchasing: Bool { store.purchasingProductID != nil }
    var isRestoring: Bool { store.isRestoring }

    /// Last user-facing error. Settable so the paywall can clear stale messages.
    var lastError: String? {
        get { store.lastError }
        set { store.lastError = newValue }
    }

    // MARK: - Actions (delegated to LeeoStore)

    func loadProducts() async {
        await store.loadProducts()
    }

    func purchase(_ product: Product) async {
        await store.purchase(product)
    }

    /// Restore for users on a new device (also an App Review requirement).
    func restore() async {
        await store.restore()
        // Restoring must never end in silence: either the paywall closes
        // (isPro flipped true) or the user learns nothing was found.
        if !isPro { lastError = "No previous purchase was found." }
    }

    /// Re-derive entitlements from the shared engine.
    func refreshEntitlement() async {
        await store.refreshEntitlements()
    }
}
