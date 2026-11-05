//
//  PedalKeys.swift
//  HandsFreeMetronome
//
//  블루투스 페이지 넘김 페달 · 키보드로 템포와 시작/멈춤.
//  페달은 키보드처럼 키를 보낸다 — 모드에 따라 방향키, Page Up/Down, 스페이스 · 리턴.
//  어느 모드든 '다음 페이지' 쪽(오른쪽 페달)이 빠르게, '이전 페이지' 쪽(왼쪽 페달)이 느리게다:
//    빠르게 +5  → · ↓ · Page Down        (Shift 를 누르면 +1)
//    느리게 −5  ← · ↑ · Page Up          (Shift 를 누르면 −1)
//    시작/멈춤  Space · Return
//  ±5 는 음성 명령 "faster" · "slower" 와 같은 폭이다.
//
//  키는 초점을 가진 뷰에서 위로 올라오므로 화면 뿌리를 초점 받을 수 있게 두고 처음에 초점을 준다.
//  시트가 열려 있으면 키는 시트로 가고, 여기까지 오지 않는다.
//

import SwiftUI

struct PedalKeys: ViewModifier {
    /// 꺼 두면 키를 흘려보낸다(첫 안내 · 페이월처럼 화면을 덮는 것이 떠 있을 때).
    let enabled: Bool
    let nudge: (Int) -> Void
    let toggle: () -> Void

    @FocusState private var focused: Bool

    private static let faster: Set<KeyEquivalent> = [.rightArrow, .downArrow, .pageDown]
    private static let slower: Set<KeyEquivalent> = [.leftArrow, .upArrow, .pageUp]
    private static let startStop: Set<KeyEquivalent> = [.space, .return]

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onAppear { focused = true }
            // 시트가 닫히거나 앱으로 돌아오면 초점이 비어 있을 수 있다 — 다시 잡는다.
            .onChange(of: enabled) { _, _ in focused = true }
            .onKeyPress(keys: Self.faster.union(Self.slower).union(Self.startStop),
                        phases: [.down, .repeat]) { press in
                guard enabled else { return .ignored }
                if Self.startStop.contains(press.key) {
                    guard press.phase == .down else { return .handled }   // 길게 눌러도 한 번만
                    toggle()
                } else {
                    let step = press.modifiers.contains(.shift) ? 1 : 5
                    nudge(Self.faster.contains(press.key) ? step : -step)
                }
                return .handled
            }
    }
}

extension View {
    func pedalKeys(enabled: Bool, nudge: @escaping (Int) -> Void, toggle: @escaping () -> Void) -> some View {
        modifier(PedalKeys(enabled: enabled, nudge: nudge, toggle: toggle))
    }
}
