//
//  MealType.swift
//  RoutineCameraCore
//
//  끼니 종류 — 순수 로직(UI/색은 앱 쪽 확장에서). 앱과 패키지가 공유한다.
//

import Foundation

public enum MealType: String, CaseIterable, Codable, Identifiable, Sendable {
    case breakfast = "아침"
    case lunch = "점심"
    case dinner = "저녁"
    case snack1 = "간식1"
    case snack2 = "간식2"
    case snack3 = "간식3"
    // 간식을 하루 세 번 넘게 먹는 사람을 위한 칸. 예전에는 세 칸이 다 차면 네 번째 간식이 앞 간식을 덮어썼다.
    // 뒤에 덧붙이기만 한다 — 저장 · 동기화 이름이 case 이름(snack4…)과 rawValue 라 순서를 바꾸면 안 된다.
    case snack4 = "간식4"
    case snack5 = "간식5"
    case snack6 = "간식6"
    case snack7 = "간식7"
    case snack8 = "간식8"
    case snack9 = "간식9"

    public var id: String { rawValue }

    /// 간식 칸 전부, 채우는 순서대로
    public static let snacks: [MealType] = [.snack1, .snack2, .snack3, .snack4, .snack5, .snack6, .snack7, .snack8, .snack9]

    /// 예전부터 있던 여섯 칸 (아침 · 점심 · 저녁 · 간식 셋). 끼니별 통계처럼 칸마다 줄을 그리는 화면에 쓴다
    public static let standardCases: [MealType] = [.breakfast, .lunch, .dinner, .snack1, .snack2, .snack3]

    /// SF Symbol 이름 (색은 앱의 MealType+UI 확장에서)
    public var symbolName: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        default: return "cup.and.saucer.fill"
        }
    }

    public var isSnack: Bool {
        switch self {
        case .breakfast, .lunch, .dinner: return false
        default: return true
        }
    }

    /// 타임스탬프가 없는 기록의 정렬용 대표 시각(시)
    public var typicalHour: Int {
        switch self {
        case .breakfast: return 8
        case .snack1:    return 10
        case .lunch:     return 12
        case .snack2:    return 15
        case .dinner:    return 18
        case .snack3:    return 21
        default:         return 22   // 늘어난 간식 칸 — 새 기록은 먹은 시각이 있어 이 값으로 줄 세울 일이 거의 없다
        }
    }

    /// 촬영 시각으로 끼니 자동 추론 (아침 5~10 / 점심 11~15 / 저녁 16~21 / 그 외 간식)
    public static func inferred(at date: Date = Date(), calendar: Calendar = .current) -> MealType {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5...10:  return .breakfast
        case 11...15: return .lunch
        case 16...21: return .dinner
        default:      return .snack1
        }
    }

    /// 기록 화면이 미리 채우는 "먹은 시각" — 오늘 지금 끼니면 지금, 아니면 그 날 끼니 대표 시각
    public func suggestedCapturedAt(on date: Date, now: Date = Date()) -> Date {
        MealTimeSuggestion.capturedAt(day: date, mealType: self, now: now)
    }
}
