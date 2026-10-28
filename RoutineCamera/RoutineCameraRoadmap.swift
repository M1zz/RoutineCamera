//
//  RoutineCameraRoadmap.swift
//  RoutineCamera (세끼)
//
//  **앞으로 만들 것**의 원본. 설정 ▸ 지원 ▸ 앞으로 만들 기능(`LeeoRoadmapView`)이 이 목록을 그대로 보여 준다.
//
//  ⚠️ 개발하다 "이건 다음에" 가 생기면 **여기에 한 줄을 더한다.** 코드의 TODO 주석으로만 남기지 않는다.
//     - 새 항목: `.planned`. 손대기 시작하면 `.building`. 내보내면 `.shipped("1.2.0")`.
//     - id 는 한 번 정하면 바꾸지 않는다(문구는 바꿔도 된다).
//     - 문구는 사용자 말로 쓴다(내부 이름 · 기술 용어 금지). 영어는 RoutineCamera/Localizable.xcstrings 에 넣는다
//       (영어가 빠지면 영어 쓰는 사람에게 한국어가 보인다).
//     - 사용자에게 보일 만한 것만 적는다. 리팩터링 · 시험 · 빌드 설정은 `.sprintcommander/tasks.json` 의 몫이다.
//

import SwiftUI
import LeeoKit

extension RoutineCameraSpec {
    static var roadmap: [LeeoRoadmapItem] {[
        // MARK: 다음에 만들어요
        .init(id: "gift-pro", status: .building,
              title: NSLocalizedString("세끼 프로 선물하기", comment: "Roadmap item: gift Pro to someone"),
              detail: NSLocalizedString("가족이나 친구에게 세끼 프로를 선물할 수 있어요. 받은 선물 코드도 설정에서 넣어요.", comment: "Roadmap item detail: gift Pro to someone")),
        .init(id: "a11y.largetext", status: .building,
              title: NSLocalizedString("큰 글씨에 맞춘 화면", comment: "Roadmap item: layouts for larger text"),
              detail: NSLocalizedString("글자 크기를 키워도 잘리지 않고 보기 좋게 다시 배치돼요.", comment: "Roadmap item detail: layouts for larger text")),
        .init(id: "a11y.contrast", status: .planned,
              title: NSLocalizedString("보기 편한 색과 대비", comment: "Roadmap item: better colors and contrast"),
              detail: NSLocalizedString("대비를 높이거나 색을 구별하기 어려워도 기록한 끼니를 알아볼 수 있어요.", comment: "Roadmap item detail: better colors and contrast")),
        .init(id: "lang.english", status: .building,
              title: NSLocalizedString("영어 지원", comment: "Roadmap item: English language"),
              detail: NSLocalizedString("앱을 영어로도 쓸 수 있어요.", comment: "Roadmap item detail: English language")),
        .init(id: "lang.more", status: .planned,
              title: NSLocalizedString("더 많은 언어", comment: "Roadmap item: more languages"),
              detail: NSLocalizedString("더 많은 나라 말로 앱을 쓸 수 있게 해요.", comment: "Roadmap item detail: more languages")),
        .init(id: "onboarding", status: .planned,
              title: NSLocalizedString("처음 쓰는 분을 위한 안내", comment: "Roadmap item: first-run guide"),
              detail: NSLocalizedString("처음 열었을 때 끼니를 어떻게 남기는지 짧게 보여 줘요.", comment: "Roadmap item detail: first-run guide")),
        .init(id: "whatsnew", status: .planned,
              title: NSLocalizedString("업데이트 소식", comment: "Roadmap item: what's new after an update"),
              detail: NSLocalizedString("업데이트 뒤 처음 열 때 무엇이 새로 생겼는지 알려 줘요.", comment: "Roadmap item detail: what's new after an update")),
        .init(id: "tips", status: .planned,
              title: NSLocalizedString("쓰는 요령 알려 주기", comment: "Roadmap item: in-app tips"),
              detail: NSLocalizedString("알아 두면 편한 기능을 알맞은 때에 살짝 알려 줘요.", comment: "Roadmap item detail: in-app tips")),
        .init(id: "haptics", status: .planned,
              title: NSLocalizedString("손끝으로 느끼는 반응", comment: "Roadmap item: haptic feedback"),
              detail: NSLocalizedString("기록을 남기거나 다 먹었을 때 가볍게 떨려서 알려 줘요.", comment: "Roadmap item detail: haptic feedback")),
        .init(id: "sync.icloud", status: .planned,
              title: NSLocalizedString("기기 간 동기화", comment: "Roadmap item: sync across devices"),
              detail: NSLocalizedString("기기를 바꿔도 iCloud로 내 식단 기록이 그대로 이어져요.", comment: "Roadmap item detail: sync across devices")),
        .init(id: "backup", status: .planned,
              title: NSLocalizedString("백업과 내보내기", comment: "Roadmap item: backup and export"),
              detail: NSLocalizedString("식단 기록과 사진을 파일로 저장하고 다시 불러올 수 있어요.", comment: "Roadmap item detail: backup and export")),
        .init(id: "lock.faceid", status: .building,
              title: NSLocalizedString("Face ID 잠금", comment: "Roadmap item: Face ID lock"),
              detail: NSLocalizedString("Face ID나 Touch ID로 앱을 잠가 내 식단 기록을 지켜요.", comment: "Roadmap item detail: Face ID lock")),
        .init(id: "fold", status: .planned,
              title: NSLocalizedString("펼치는 아이폰 화면", comment: "Roadmap item: foldable iPhone layout"),
              detail: NSLocalizedString("펼치는 아이폰에서 기록과 사진을 두 쪽으로 나눠 봐요.", comment: "Roadmap item detail: foldable iPhone layout")),
        .init(id: "data.delete", status: .planned,
              title: NSLocalizedString("내 기록 한 번에 지우기", comment: "Roadmap item: delete all my data"),
              detail: NSLocalizedString("원하면 앱 안에서 식단 기록을 모두 지울 수 있어요.", comment: "Roadmap item detail: delete all my data")),
        .init(id: "autosave", status: .planned,
              title: NSLocalizedString("쓰던 메모 이어 쓰기", comment: "Roadmap item: keep unsaved drafts"),
              detail: NSLocalizedString("메모를 쓰다가 앱이 꺼져도 쓰던 내용이 남아 있어요.", comment: "Roadmap item detail: keep unsaved drafts")),
    ]}
}

// MARK: - 화면

/// 설정 ▸ 지원 ▸ 앞으로 만들 기능. "이런 기능이 있으면 좋겠어요" 는 기능 제안으로 시작하는 피드백 창을 연다.
struct RoadmapScreen: View {
    @State private var showFeedback = false

    var body: some View {
        LeeoRoadmapView<RoutineCameraSpec>(onSuggest: { showFeedback = true })
            .sheet(isPresented: $showFeedback) {
                NavigationStack {
                    LeeoFeedbackView<RoutineCameraSpec>(initialType: .feature)
                }
            }
    }
}
