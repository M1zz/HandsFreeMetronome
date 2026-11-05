//
//  WristDemo.swift
//  스토어 스크린샷용 장면 (DEBUG 전용). -wristDemo playing | still
//

#if DEBUG
import Foundation

enum WristDemo {
    @MainActor static func apply(to metronome: WristMetronome) {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-wristDemo"), i + 1 < args.count else { return }
        switch args[i + 1] {
        case "playing":
            metronome.bpm = 92
            metronome.beats = 4
            metronome.start()
        default:
            metronome.bpm = 120
            metronome.beats = 3
        }
    }
}
#endif
