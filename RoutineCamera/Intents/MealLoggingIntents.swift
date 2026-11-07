//
//  MealLoggingIntents.swift
//  RoutineCamera
//
//  앱을 열지 않고 기록하는 App Intents — 액션버튼/단축어/시리로 "다 먹음" 한 탭.
//  Phase 2에서 잠금화면/홈 위젯 버튼도 이 인텐트를 재사용한다.
//
//  식단 기록은 Siri · Spotlight 가 알아보게 색인한다(iOS 18+). 메모 · 음식 · 찍은 곳으로 찾고, 누르면 그 기록이 열린다.
//

import AppIntents
import CoreSpotlight
import Foundation
import RoutineCameraCore

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
        // 단축어·시리의 '다 먹음'도 식단 기록이다 — 운동 앨범을 보고 있어도 식단에 남긴다
        store.inDietAlbum { store.recordAteAll(date: date, mealType: mealType) }
        return .result(dialog: "\(mealType.displayName) 다 먹음으로 남겼어요.")
    }
}

// MARK: - 식사 기록

/// 열어 달라는 식사 기록. ContentView 가 그 기록의 사진 화면을 띄우고 비운다.
@MainActor @Observable
final class MealRouter {
    static let shared = MealRouter()
    var recordID: UUID?
}

struct MealRecordEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("식사 기록", comment: "Siri/Spotlight: one logged meal")
    )
    static let defaultQuery = MealRecordQuery()

    let id: UUID
    let mealName: String
    let day: String
    /// 메모 · 음식 이름 · 찍은 곳. 검색 · 색인에 쓴다.
    let text: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(mealName)", subtitle: "\(day)")
    }

    init(_ record: MealRecord) {
        id = record.id
        mealName = record.mealType.displayName
        day = record.date.formatted(date: .abbreviated, time: .omitted)
        text = ([record.memo, record.place?.name] + (record.visionAnalysis?.foodItems ?? []))
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    @MainActor private static var indexedRevision: Int?

    /// 식단 앨범의 기록 — 최근 것부터.
    @MainActor
    static func all() -> [MealRecordEntity] {
        MealRecordStore.shared.dietMeals.filter(\.isComplete)
            .sorted { $0.sortDate > $1.sortDate }
            .map(MealRecordEntity.init)
    }

    /// Spotlight 에 싣는 기록을 지금 것에 맞춘다. 앱을 열 때와 뒤로 보낼 때 부른다.
    /// 지난번에 싣은 뒤로 식단 기록이 그대로면 건너뛴다 — 앞뒤로 오갈 때마다 전부 다시 싣지 않게.
    @MainActor
    static func reindex() async {
        let revision = MealRecordStore.shared.dietRevision
        guard revision != indexedRevision else { return }
        indexedRevision = revision
        let entities = all()
        let index = CSSearchableIndex.default()
        try? await index.deleteAppEntities(ofType: MealRecordEntity.self)
        try? await index.indexAppEntities(entities)
    }
}

extension MealRecordEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.textContent = text
        return set
    }
}

struct MealRecordQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [MealRecordEntity] {
        let wanted = Set(identifiers)
        return await MealRecordEntity.all().filter { wanted.contains($0.id) }
    }

    /// 메모 · 음식 · 찍은 곳 · 끼니 이름에서 찾는다.
    func entities(matching string: String) async throws -> [MealRecordEntity] {
        await MealRecordEntity.all().filter {
            $0.text.localizedCaseInsensitiveContains(string) || $0.mealName.localizedCaseInsensitiveContains(string)
        }
    }

    func suggestedEntities() async throws -> [MealRecordEntity] {
        Array(await MealRecordEntity.all().prefix(20))
    }
}

/// 식사 기록을 연다. Spotlight · Siri 결과를 누르면 여기로 온다.
struct OpenMealRecordIntent: OpenIntent {
    static let title = LocalizedStringResource("식사 기록 열기", comment: "Siri/Spotlight: open a logged meal")
    static let description = IntentDescription(
        LocalizedStringResource("남긴 식사 기록의 사진과 메모를 엽니다.", comment: "Siri: open meal record description")
    )

    @Parameter(title: LocalizedStringResource("식사 기록", comment: "Siri: meal record parameter"),
               description: LocalizedStringResource("열어 볼 식사 기록", comment: "Siri: meal record parameter description"))
    var target: MealRecordEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        MealRouter.shared.recordID = target.id
        return .result()
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
