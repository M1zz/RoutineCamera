//
//  MealLoggingIntents.swift
//  RoutineCamera
//
//  앱을 열지 않고 기록하는 App Intents — 액션버튼/단축어/시리로 "다 먹음" 한 탭.
//  Phase 2에서 잠금화면/홈 위젯 버튼도 이 인텐트를 재사용한다.
//

import AppIntents
import Foundation

/// "다 먹음" 기록 — 가장 최근 '먹는 중'(식전만 찍은) 기록에 다먹음 신호를 붙이고,
/// 없으면 현재 시각으로 추론한 끼니에 사진 없이 다먹음 기록을 남긴다.
struct LogAteAllIntent: AppIntent {
    static var title: LocalizedStringResource = "다 먹음 기록"
    static var description = IntentDescription("방금 먹은 걸 '다 먹음'으로 남깁니다. 앱을 열지 않아도 돼요.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = MealRecordStore.shared
        let mealType: MealType
        let date: Date
        if let inProgress = store.latestEatingInProgress() {
            mealType = inProgress.mealType
            date = inProgress.date
        } else {
            mealType = MealType.inferred()
            date = Date()
        }
        store.recordAteAll(date: date, mealType: mealType)
        return .result(dialog: "\(mealType.rawValue) 다 먹음으로 남겼어요.")
    }
}

/// 시리/단축어 자동 노출 문구.
struct MealLoggingShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogAteAllIntent(),
            phrases: [
                "\(.applicationName)에 다 먹음 기록",
                "\(.applicationName) 다 먹었어"
            ],
            shortTitle: "다 먹음",
            systemImageName: "checkmark.circle.fill"
        )
    }
}
