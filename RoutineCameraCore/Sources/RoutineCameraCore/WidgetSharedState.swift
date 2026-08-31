//
//  WidgetSharedState.swift
//  RoutineCameraCore
//
//  홈/잠금화면 위젯이 App Group 공유 저장소에서 읽는 경량 스냅샷과,
//  "지금 위젯에 무엇을 보여줄지 / 다 먹음 버튼이 어느 기록에 붙어야 할지" 판단 로직.
//  앱은 스냅샷을 쓰고, 위젯은 읽는다. 순수 로직이라 여기서 테스트한다.
//

import Foundation

/// 앱이 기록을 저장할 때마다 갱신하는 위젯용 요약.
/// 위젯은 사진이 담긴 기록 전체를 디코딩하지 않고 이것만 읽는다.
/// ⚠️ 필드 이름은 앱의 `WidgetSnapshot`(RoutineCamera/AppGroup.swift)과 반드시 동일해야 한다 —
/// 같은 JSON을 앱이 쓰고 위젯이 읽기 때문이다.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public let todayCount: Int              // 오늘 남긴 기록 수
    public let inProgressMealType: String?  // 오늘 "먹는 중"인 끼니 (식전만 찍힌 것)
    public let inProgressSince: Date?       // 그 기록의 촬영 시각
    public let lastRecordedAt: Date?        // 오늘 마지막 기록 시각
    public let needsRecordCount: Int        // 날이 지나 "기록 필요"로 남은 기록 수
    public let generatedAt: Date

    public init(todayCount: Int,
                inProgressMealType: String? = nil,
                inProgressSince: Date? = nil,
                lastRecordedAt: Date? = nil,
                needsRecordCount: Int = 0,
                generatedAt: Date) {
        self.todayCount = todayCount
        self.inProgressMealType = inProgressMealType
        self.inProgressSince = inProgressSince
        self.lastRecordedAt = lastRecordedAt
        self.needsRecordCount = needsRecordCount
        self.generatedAt = generatedAt
    }
}

/// 위젯이 화면에 그릴 상태 — 저장된 스냅샷 + 아직 앱에 반영되지 않은 대기열을 합친 결과.
public struct ResolvedWidgetState: Sendable, Equatable {
    public let todayCount: Int
    public let inProgressMeal: String?   // 대기열에 이미 다먹음이 쌓였으면 nil (버튼 누른 직후 반영)
    public let needsRecordCount: Int

    public init(todayCount: Int, inProgressMeal: String?, needsRecordCount: Int) {
        self.todayCount = todayCount
        self.inProgressMeal = inProgressMeal
        self.needsRecordCount = needsRecordCount
    }
}

public enum WidgetStateResolver {

    /// 위젯 표시 상태 계산.
    /// - 대기열의 다먹음이 "먹는 중"인 끼니에 붙는 경우는 기존 기록을 마감하는 것이라 기록 수가 늘지 않는다.
    /// - 그 외 끼니의 다먹음은 새 기록이 되므로 수가 늘어난다.
    /// - 스냅샷이 없으면(앱을 아직 안 켠 경우) fallbackTodayCount 로 개수만 센다.
    public static func resolve(snapshot: WidgetSnapshot?,
                              pending: [PendingAteAll],
                              fallbackTodayCount: Int = 0,
                              now: Date,
                              calendar: Calendar = .current) -> ResolvedWidgetState {
        let pendingToday = pending.filter {
            calendar.isDate(Date(timeIntervalSince1970: $0.date), inSameDayAs: now)
        }

        guard let snapshot else {
            return ResolvedWidgetState(todayCount: fallbackTodayCount + pendingToday.count,
                                       inProgressMeal: nil,
                                       needsRecordCount: 0)
        }

        let resolvesInProgress = snapshot.inProgressMealType.map { meal in
            pendingToday.contains { $0.mealType == meal }
        } ?? false
        let added = pendingToday.filter { $0.mealType != snapshot.inProgressMealType }.count

        return ResolvedWidgetState(
            todayCount: snapshot.todayCount + added,
            inProgressMeal: resolvesInProgress ? nil : snapshot.inProgressMealType,
            needsRecordCount: snapshot.needsRecordCount
        )
    }

    /// "다 먹음"을 지금 누르면 대기열에 쌓아야 할 항목.
    /// 오늘 "먹는 중"인 끼니가 있으면 그 기록을 마감하도록 같은 끼니·같은 날짜로,
    /// 없으면 현재 시각으로 추론한 끼니에 새로 남긴다.
    public static func pendingItem(snapshot: WidgetSnapshot?,
                                   now: Date,
                                   calendar: Calendar = .current) -> PendingAteAll {
        if let meal = snapshot?.inProgressMealType {
            let since = snapshot?.inProgressSince ?? now
            return PendingAteAll(mealType: meal, date: since.timeIntervalSince1970)
        }
        return PendingAteAll(mealType: MealType.inferred(at: now, calendar: calendar).rawValue,
                             date: now.timeIntervalSince1970)
    }
}
