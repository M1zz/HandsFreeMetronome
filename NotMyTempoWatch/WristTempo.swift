//
//  WristTempo.swift
//  워치 앱과 컴플리케이션이 함께 보는 '마지막 템포'. 폰과 주고받지 않는다 — 워치가 혼자 기억한다.
//

import SwiftUI
import WidgetKit

enum WristTempo {
    static let group = "group.com.leeo.HandsFreeMetronome"
    /// 손목 진동이 박을 놓치지 않는 범위.
    /// WKInterfaceDevice.play 는 앞 진동이 아직 울리는 중이면 그것을 끊고 최소 100ms 를 쉰 뒤 다음을 시작한다.
    /// 강박 진동까지 한 박 안에 끝나도록 박 사이를 300ms(200 BPM) 이상으로 둔다. 박을 쪼개는 소리(8분 · 16분)는 손목에 싣지 않는다.
    static let range = 30...200
    static let beatsRange = 1...8

    private static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    static var bpm: Int {
        get { let v = defaults.integer(forKey: "bpm"); return v == 0 ? 100 : min(max(v, range.lowerBound), range.upperBound) }
        set { defaults.set(newValue, forKey: "bpm") }
    }

    static var beats: Int {
        get { let v = defaults.integer(forKey: "beats"); return v == 0 ? 4 : min(max(v, beatsRange.lowerBound), beatsRange.upperBound) }
        set { defaults.set(newValue, forKey: "beats") }
    }

    /// 컴플리케이션을 누르면 이 주소로 앱이 열리고 바로 시작한다.
    static let startURL = URL(string: "notmytempo-watch://start")!
}

/// 아이폰과 같은 두 색: 모든 박은 cue(청록), 강박은 빨강. 워치는 늘 어두운 화면이라 어두운 쪽 값을 쓴다.
extension Color {
    static let cue = Color(red: 0x22 / 255, green: 0xD3 / 255, blue: 0xEE / 255)
    static let beatRed = Color(red: 0.90, green: 0.22, blue: 0.20)
}
