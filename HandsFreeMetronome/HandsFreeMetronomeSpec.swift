import Foundation
import LeeoKit

enum HandsFreeMetronomeSpec: LeeoAppSpec {
    static let appName = "Not My Tempo"
    static let developerEmail = "leeo@kakao.com"
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
            termsURL: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!))
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

    static var isEnabled: Bool { !UserDefaults.standard.bool(forKey: optOutKey) }

    /// Call once from `App.init()`.
    static func start() {
        // Launch count, analytics sink and preflight. Diagnostics and the
        // usage snapshot are started below so the switch can gate them.
        LeeoKit.bootstrap(HandsFreeMetronomeSpec.self, diagnostics: false, usageReporting: false)
        LeeoDiagnostics.shared.start(spec: HandsFreeMetronomeSpec.self) { isEnabled }
        guard isEnabled else { return }
        // One snapshot per install (12 h throttle) plus one `app_open` per day
        // whenever the app comes to the foreground.
        LeeoUsageReporter(spec: HandsFreeMetronomeSpec.self).reportInBackground()
    }
}

/// LeeoKit's own events (paywall, purchase, satisfaction, review, feedback)
/// go through here, so switching statistics off silences them too.
struct NotMyTempoAnalytics: LeeoAnalytics {
    private let hub = LeeoUsageAnalytics(spec: HandsFreeMetronomeSpec.self)

    func track(_ event: LeeoEvent) {
        guard Telemetry.isEnabled else { return }
        hub.track(event)
    }
}
