import SwiftUI
import TipKit
import os
import LeeoKit

@main
struct HandsFreeMetronomeApp: App {
    init() {
        // 백업 금고는 무엇보다 먼저 — 예약된 복원을 설정(UserDefaults) · TipKit 저장소가 열리기 전에 적용한다.
        // 아래 Telemetry.start() 의 bootstrap 이 다시 부르지만, 한 번만 켜진다.
        LeeoVault.start(HandsFreeMetronomeSpec.self)

        // Crash-loop guard first — two launches in a row that never reached the
        // first screen open this one in safe mode (→ Operations.swift).
        LaunchGuard.begin()
        if !LaunchGuard.isSafeMode {
            do {
                try Tips.configure([
                    .displayFrequency(.immediate),
                    .datastoreLocation(.applicationDefault)
                ])
            } catch {
                Log.app.error("TipKit configure failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        // 실행 횟수 · 분석 싱크 · 크래시 진단 · 설치 스냅샷과 하루 한 번 app_open (→ Telemetry.swift).
        Telemetry.start()
    }

    var body: some Scene {
        WindowGroup {
            // The satisfaction prompt is asked right after practice (ContentView),
            // not on launch.
            ContentView()
                // 개발자가 보낸 의견에 답장하면, 앱이 앞으로 올 때 답장을 시트로 보여 준다 (LeeoKit).
                .leeoFeedbackReplyNotice(HandsFreeMetronomeSpec.self)
                // iPhone Duo: measures the fold and keeps sheets and alerts off it (LeeoKit Fold).
                .foldAware()
        }
    }
}
