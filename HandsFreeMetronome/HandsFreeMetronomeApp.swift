import SwiftUI
import TipKit
import LeeoKit

@main
struct HandsFreeMetronomeApp: App {
    init() {
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
        // 실행 횟수 · 분석 싱크 · 크래시 진단 · 설치 스냅샷과 하루 한 번 app_open (→ Telemetry.swift).
        Telemetry.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .leeoSatisfactionCheck(HandsFreeMetronomeSpec.self)
        }
    }
}
