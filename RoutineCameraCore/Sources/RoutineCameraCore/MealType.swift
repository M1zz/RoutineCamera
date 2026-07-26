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

    public var id: String { rawValue }

    /// SF Symbol 이름 (색은 앱의 MealType+UI 확장에서)
    public var symbolName: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack1, .snack2, .snack3: return "cup.and.saucer.fill"
        }
    }

    public var isSnack: Bool {
        switch self {
        case .snack1, .snack2, .snack3: return true
        default: return false
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
}
