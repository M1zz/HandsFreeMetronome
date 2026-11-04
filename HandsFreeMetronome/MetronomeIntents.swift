//
//  MetronomeIntents.swift
//  HandsFreeMetronome
//
//  손을 쓰지 않는 메트로놈이라 Siri 가 가장 잘 맞는 입구다.
//   - "Start Not My Tempo": 마지막 박자로 바로 시작한다.
//   - "Set the tempo in Not My Tempo": 몇 BPM 인지 묻고 그 박자로 시작한다.
//   - "Stop Not My Tempo": 멈춘다.
//

import AppIntents
import Foundation

struct StartMetronomeIntent: AppIntent {
    static let title = LocalizedStringResource("Start Metronome", comment: "Siri: start the metronome")
    static let description = IntentDescription(
        LocalizedStringResource("Starts the metronome at your last tempo.", comment: "Siri: start metronome description")
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let engine = MetronomeEngine.shared
        if !engine.isPlaying { engine.start() }
        return .result()
    }
}

struct SetTempoIntent: AppIntent {
    static let title = LocalizedStringResource("Set Tempo", comment: "Siri: set the metronome tempo")
    static let description = IntentDescription(
        LocalizedStringResource("Sets the tempo and starts the metronome.", comment: "Siri: set tempo description")
    )
    static let openAppWhenRun = true

    @Parameter(title: LocalizedStringResource("BPM", comment: "Siri: beats per minute parameter"),
               description: LocalizedStringResource("The tempo in beats per minute, from 20 to 300.", comment: "Siri: BPM parameter description"),
               inclusiveRange: (20, 300),
               requestValueDialog: IntentDialog(LocalizedStringResource("What tempo?", comment: "Siri: ask for the BPM")))
    var bpm: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        let engine = MetronomeEngine.shared
        engine.bpm = bpm
        if !engine.isPlaying { engine.start() }
        return .result()
    }
}

struct StopMetronomeIntent: AppIntent {
    static let title = LocalizedStringResource("Stop Metronome", comment: "Siri: stop the metronome")
    static let description = IntentDescription(
        LocalizedStringResource("Stops the metronome.", comment: "Siri: stop metronome description")
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        MetronomeEngine.shared.stop()
        return .result()
    }
}

struct MetronomeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMetronomeIntent(),
            phrases: ["Start \(.applicationName)", "Start the metronome in \(.applicationName)"],
            shortTitle: "Start Metronome",
            systemImageName: "metronome"
        )
        AppShortcut(
            intent: SetTempoIntent(),
            phrases: ["Set the tempo in \(.applicationName)", "Change tempo in \(.applicationName)"],
            shortTitle: "Set Tempo",
            systemImageName: "dial.medium"
        )
        AppShortcut(
            intent: StopMetronomeIntent(),
            phrases: ["Stop \(.applicationName)", "Stop the metronome in \(.applicationName)"],
            shortTitle: "Stop Metronome",
            systemImageName: "stop.fill"
        )
    }
}
