import Foundation
import LeeoKit

enum HandsFreeMetronomeSpec: LeeoAppSpec {
    static let appName = "Not My Tempo"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.FeedbackHub", appIdentifier: "com.leeo.HandsFreeMetronome")

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
