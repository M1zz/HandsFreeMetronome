import SwiftUI
import TipKit
import os
import LeeoKit

@main
struct HandsFreeMetronomeApp: App {
    init() {
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
            ContentView()
                .leeoSatisfactionCheck(HandsFreeMetronomeSpec.self)
        }
    }
}
