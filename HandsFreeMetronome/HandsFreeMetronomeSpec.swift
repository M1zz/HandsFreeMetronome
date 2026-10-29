import Foundation
import os
import LeeoKit

enum HandsFreeMetronomeSpec: LeeoAppSpec {
    static let appName = "Not My Tempo"
    static let developerEmail = "leeo@kakao.com"
    /// "Write a review" deep-links to this listing; the family row uses it to leave this app out.
    static let appStoreID: String? = "6781537149"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.FeedbackHub", appIdentifier: "com.leeo.HandsFreeMetronome")

    // 익명 사용 통계 → FeedbackHub. 끄기 스위치를 지나서 나간다 (→ Telemetry.swift).
    static let analytics: any LeeoAnalytics = NotMyTempoAnalytics()

    static let legal = LeeoLegalConfig(
        privacyURL: URL(string: "https://m1zz.github.io/HandsFreeMetronome/privacy.html")!,
        supportURL: URL(string: "https://m1zz.github.io/HandsFreeMetronome/")!)

    // 인앱 결제(프로 잠금해제) — 연간 구독 + 평생 해제. StoreKit 엔진은 LeeoKit 의 LeeoStore 가
    // 담당하고, 앱은 얇은 ProStore 파사드(기능 게이트·그랜드파더링·개발 언락)만 유지한다.
    // 페이월 구성(`paywall`)은 이 선언에서 유도된다. yearly 를 먼저 둬 페이월에서 구독을
    // 대표 상품으로 노출한다. entitlementIDs 는 기본값(productIDs 전체) — 둘 다 Pro 권한을 준다.
    static let monetization = LeeoMonetization.freemiumSubscription(
        LeeoSubscriptionConfig(
            productIDs: [ProStore.yearlyID, ProStore.lifetimeID],
            termsURL: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!,
            // What a free user can't open without Pro — the three practice
            // tools. Everything else (the metronome, voice control, timer)
            // stays free. ContentView.requirePro asks this gate.
            gate: LeeoGatePolicy(proOnly: Set(ProFeature.allCases.map(\.rawValue))),
            // Pro 선물하기. 보내는 사람은 소모성 선물 상품을 사고, 받는 사람은 평생 Pro 를 산 것과 같아진다.
            // 선물 기록은 피드백과 같은 허브 컨테이너의 공개 DB 에 둔다. entitlements 에 이미 있다.
            // ⚠️ 선물 상품은 productIDs · entitlementIDs 에 넣지 않는다. 넣으면 선물을 산 사람이 Pro 가 된다.
            gift: LeeoGiftConfig(
                productID: ProStore.giftID,
                grantsProductID: ProStore.lifetimeID,
                containerIdentifier: "iCloud.com.Ysoup.FeedbackHub"),
            // 개발자 응원하기(팁). 이미 Pro 를 가진 사람이 조금 더 내고 싶을 때. 기능을 열지 않는다.
            tipJar: LeeoTipJarConfig(productIDs: ProStore.tipIDs)))
}

// MARK: - Usage statistics

/// Anonymous usage statistics → FeedbackHub (CloudKit public DB).
///
/// On by default; the "Share anonymous usage statistics" switch in the help
/// sheet turns it off, and then no snapshot, event or diagnostic leaves the
/// device. What goes out: a random install ID, app/OS version, locale, launch
/// and event counts, install date, one `app_open` a day, purchase-flow events,
/// and crash/hang diagnostics. No audio, no settings, no Apple ID.
///
/// Before this existed the app sent nothing, so the hub counted zero installs
/// against 1,370 App Store downloads (2026-10-15).
enum Telemetry {

    /// Stored as an *opt-out* so the default (`false`) means "sending".
    static let optOutKey = "usage.optOut"

    /// The user's switch AND the remote kill switch (→ `NotMyTempoFlag.usageStats`).
    static var isEnabled: Bool {
        !UserDefaults.standard.bool(forKey: optOutKey) && NotMyTempoFlag.usageStats.isEnabled
    }

    /// Call once from `App.init()`.
    static func start() {
        // Launch count, analytics sink and preflight. Diagnostics and the
        // usage snapshot are started below so the switch can gate them.
        // `flags:` also refreshes the remote kill switches in the background.
        // Its own DEBUG audit is off: it runs before the flags and diagnostics
        // below are on and would always report them missing (→ auditContract).
        LeeoKit.bootstrap(HandsFreeMetronomeSpec.self, flags: NotMyTempoFlag.self,
                          diagnostics: false, usageReporting: false, preflight: false)
        LeeoDiagnostics.shared.start(spec: HandsFreeMetronomeSpec.self) { isEnabled }
        #if DEBUG
        auditContract()
        #endif
        guard isEnabled else { return }
        // One snapshot per install (12 h throttle) plus one `app_open` per day
        // whenever the app comes to the foreground.
        let reporter = LeeoUsageReporter(spec: HandsFreeMetronomeSpec.self)
        reporter.reportInBackground()
        // Launches that died before the first screen (counted by LaunchGuard).
        // Release only: in development, stopping the app from Xcode or a
        // screenshot script kills it within seconds and would flood the hub —
        // and unsigned simulator builds have no iCloud entitlement to send with.
        #if !DEBUG
        if LaunchGuard.crashGuard.unreportedIncompleteLaunches > 0 {
            Task { _ = await LaunchGuard.crashGuard.reportIncompleteLaunches(to: reporter) }
        }
        #endif
    }
}

#if DEBUG
extension Telemetry {
    /// Development builds check the LeeoKit contract (paywall reachable, restore,
    /// https policy links…) on every launch and log what's wrong to Console
    /// (subsystem com.leeo.HandsFreeMetronome, category app). It only reports;
    /// what blocks a release is `SpecPreflightTests`.
    static func auditContract() {
        let issues = LeeoPreflight.audit(HandsFreeMetronomeSpec.self)
        if issues.isEmpty { Log.app.info("LeeoPreflight: contract OK") }
        for issue in issues {
            let line = "LeeoPreflight [\(issue.code)] \(issue.message)"
            switch issue.severity {
            case .error: Log.app.error("\(line, privacy: .public)")
            case .warning: Log.app.warning("\(line, privacy: .public)")
            case .info: Log.app.info("\(line, privacy: .public)")
            }
        }
    }
}
#endif

/// LeeoKit's own events (paywall, purchase, satisfaction, review, feedback)
/// go through here, so switching statistics off silences them too.
struct NotMyTempoAnalytics: LeeoAnalytics {
    private let hub = LeeoUsageAnalytics(spec: HandsFreeMetronomeSpec.self)

    func track(_ event: LeeoEvent) {
        guard Telemetry.isEnabled else { return }
        hub.track(event)
    }
}
