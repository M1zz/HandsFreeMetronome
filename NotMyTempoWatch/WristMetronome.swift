//
//  WristMetronome.swift
//  소리 없이 손목 진동으로 박을 준다. 강박(1박)은 세게, 나머지는 가볍게.
//
//  - 손목을 내려도 멈추지 않게 마음 챙기기 세션(WKExtendedRuntimeSession, 최대 1시간)을 연다.
//    그동안 앱은 맨 앞에 남아 진동을 계속 낸다.
//  - 박 시각은 시작 시각에서 잰 절대 시각이라 타이머가 늦어도 밀려 쌓이지 않는다.
//

import SwiftUI
import WatchKit
import WidgetKit

@MainActor
final class WristMetronome: NSObject, ObservableObject {
    static let shared = WristMetronome()

    @Published var bpm = WristTempo.bpm {
        didSet {
            let clamped = min(max(bpm, WristTempo.range.lowerBound), WristTempo.range.upperBound)
            if clamped != bpm { bpm = clamped; return }
            WristTempo.bpm = bpm
            if isPlaying { realign() }
        }
    }
    @Published var beats = WristTempo.beats {
        didSet { WristTempo.beats = beats }
    }
    @Published private(set) var isPlaying = false
    @Published private(set) var currentBeat = -1   // 지금 울린 박 (0부터), 멈추면 -1

    private var timer: DispatchSourceTimer?
    private var session: WKExtendedRuntimeSession?
    private var anchor = DispatchTime.now()   // 0번째 박의 시각
    private var tick = 0                      // 다음에 울릴 박의 번호 (anchor 기준)
    private var lastFired: DispatchTime?      // 방금 울린 박의 시각

    private var interval: Double { 60.0 / Double(bpm) }

    func toggle() { isPlaying ? stop() : start() }

    func start() {
        guard !isPlaying else { return }
        isPlaying = true
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()
        session = s
        anchor = .now()
        tick = 0
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.fire() }
        }
        timer = t
        t.schedule(deadline: anchor, leeway: .nanoseconds(0))
        t.resume()
    }

    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        currentBeat = -1
        timer?.cancel()
        timer = nil
        session?.invalidate()
        session = nil
        WidgetCenter.shared.reloadAllTimelines()   // 컴플리케이션에 마지막 템포
    }

    /// 한 박: 진동하고 다음 박의 절대 시각을 잡는다.
    private func fire() {
        guard isPlaying else { return }
        let beat = tick % max(1, beats)
        currentBeat = beat
        lastFired = anchor + interval * Double(tick)   // 예정된 박 시각 (실제 깨어난 시각의 흔들림을 쌓지 않게)
        // 한 박자 마디(1)는 강세가 없다 — 모든 박이 같다.
        WKInterfaceDevice.current().play(beat == 0 && beats > 1 ? .notification : .click)
        tick += 1
        timer?.schedule(deadline: anchor + interval * Double(tick), leeway: .nanoseconds(0))
    }

    /// 연주 중에 템포가 바뀌면 방금 울린 박을 기준으로 새 간격을 잡는다(박이 튀지 않게).
    private func realign() {
        guard tick > 0, let last = lastFired else { return }
        anchor = last - interval * Double(tick - 1)
        timer?.schedule(deadline: anchor + interval * Double(tick), leeway: .nanoseconds(0))
    }
}

extension WristMetronome: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in self.stop() }
    }

    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                            error: Error?) {
        // 세션이 끝나면(1시간, 다른 앱이 맨 앞으로) 진동도 멈춘다 — 안 보이는 데서 혼자 울리지 않게.
        Task { @MainActor in
            guard self.session === extendedRuntimeSession else { return }
            self.stop()
        }
    }
}
