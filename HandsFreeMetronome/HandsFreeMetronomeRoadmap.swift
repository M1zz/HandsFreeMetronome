//
//  HandsFreeMetronomeRoadmap.swift
//  HandsFreeMetronome
//
//  **앞으로 만들 것**의 원본. 도움말 ▸ 지원 ▸ 앞으로 만들 기능(`LeeoRoadmapView`)이 이 목록을 그대로 보여 준다.
//
//  ⚠️ 개발하다 "이건 다음에" 가 생기면 **여기에 한 줄을 더한다.** 코드의 TODO 주석으로만 남기지 않는다.
//     - 새 항목: `.planned`. 손대기 시작하면 `.building`. 내보내면 `.shipped("2.1.0")`.
//     - id 는 한 번 정하면 바꾸지 않는다(문구는 바꿔도 된다).
//     - 문구는 사용자 말로 쓴다(내부 이름 · 기술 용어 금지). 키는 영어(개발 언어),
//       번역은 `Localizable.xcstrings` 의 모든 언어(ja · de · es · zh-Hans · pt-BR · fr)에 넣는다.
//     - 사용자에게 보일 만한 것만 적는다. 리팩터링 · 시험 · 빌드 설정은 `.sprintcommander/tasks.json` 의 몫이다.
//

import SwiftUI
import LeeoKit

extension HandsFreeMetronomeSpec {
    static var roadmap: [LeeoRoadmapItem] {[
        // MARK: 다음에 만들어요
        .init(id: "a11y.largetext", status: .shipped("1.0.10"),
              title: String(localized: "Even larger text", comment: "Roadmap item: a11y.largetext"),
              detail: String(localized: "The screen stays readable and tidy at the very largest text sizes.", comment: "Roadmap item detail: a11y.largetext")),
        .init(id: "a11y.contrast", status: .shipped("1.0.10"),
              title: String(localized: "Easier-to-see colors", comment: "Roadmap item: a11y.contrast"),
              detail: String(localized: "Beat and timing colors stay clear with Increase Contrast, or if colors are hard to tell apart.", comment: "Roadmap item detail: a11y.contrast")),
        .init(id: "a11y.keyboard", status: .planned,
              title: String(localized: "Keyboard control", comment: "Roadmap item: a11y.keyboard"),
              detail: String(localized: "On iPad with a keyboard, start, stop, and change the tempo with keys.", comment: "Roadmap item detail: a11y.keyboard")),
        .init(id: "whatsnew", status: .shipped("1.0.10"),
              title: String(localized: "What’s new", comment: "Roadmap item: whatsnew"),
              detail: String(localized: "After an update, see what’s new the first time you open the app.", comment: "Roadmap item detail: whatsnew")),
        .init(id: "feedback.reply", status: .planned,
              title: String(localized: "Replies to your feedback", comment: "Roadmap item: feedback.reply"),
              detail: String(localized: "Read our replies to your feedback right in the app.", comment: "Roadmap item detail: feedback.reply")),
        .init(id: "gift", status: .building,
              title: String(localized: "Gift Pro", comment: "Roadmap item: gift"),
              detail: String(localized: "Give Not My Tempo Pro to a bandmate or a student.", comment: "Roadmap item detail: gift")),
        .init(id: "widgets", status: .planned,
              title: String(localized: "Home Screen widget", comment: "Roadmap item: widgets"),
              detail: String(localized: "Start the click right from your Home Screen without opening the app.", comment: "Roadmap item detail: widgets")),
        .init(id: "shortcuts", status: .planned,
              title: String(localized: "Siri and Shortcuts", comment: "Roadmap item: shortcuts"),
              detail: String(localized: "Ask Siri or run a shortcut to start the click at your tempo.", comment: "Roadmap item detail: shortcuts")),
        .init(id: "sync.icloud", status: .planned,
              title: String(localized: "Sync across devices", comment: "Roadmap item: sync.icloud"),
              detail: String(localized: "Your presets and settings follow you between iPhone and iPad.", comment: "Roadmap item detail: sync.icloud")),
        .init(id: "backup", status: .planned,
              title: String(localized: "Back up your presets", comment: "Roadmap item: backup"),
              detail: String(localized: "Save your accent presets to a file and bring them back anytime.", comment: "Roadmap item detail: backup")),
        .init(id: "notifications", status: .planned,
              title: String(localized: "Practice reminders", comment: "Roadmap item: notifications"),
              detail: String(localized: "Get a gentle reminder at the time you choose to practice.", comment: "Roadmap item detail: notifications")),
        .init(id: "fold", status: .planned,
              title: String(localized: "Foldable iPhone layout", comment: "Roadmap item: fold"),
              detail: String(localized: "On a foldable iPhone, see the beat and the controls side by side.", comment: "Roadmap item detail: fold")),
        .init(id: "data.delete", status: .planned,
              title: String(localized: "Erase all my data", comment: "Roadmap item: data.delete"),
              detail: String(localized: "Clear all your presets and settings in the app whenever you want.", comment: "Roadmap item detail: data.delete")),
    ]}
}

// MARK: - 화면

/// 앞으로 만들 기능. "이런 기능이 있으면 좋겠어요" 는 기능 제안으로 시작하는 피드백 창을 연다.
struct RoadmapScreen: View {
    @State private var showFeedback = false

    var body: some View {
        LeeoRoadmapView<HandsFreeMetronomeSpec>(onSuggest: { showFeedback = true })
            .sheet(isPresented: $showFeedback) {
                NavigationStack {
                    LeeoFeedbackView<HandsFreeMetronomeSpec>(initialType: .feature)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button { showFeedback = false } label: { Label("Done", systemImage: "checkmark") }
                            }
                        }
                }
            }
    }
}
