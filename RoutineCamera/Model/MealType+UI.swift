//
//  MealType+UI.swift
//  RoutineCamera
//
//  끼니 종류의 화면용 이름 · 색. 모델(MealType · MealRecord)은 RoutineCameraCore 에 한 벌만 둔다.
//

import SwiftUI
import RoutineCameraCore

extension MealType {
    /// 화면에 보이는 이름 — 간식1·2·3 은 저장용 구분일 뿐이라 사용자에게는 "간식" 으로 보인다
    nonisolated var displayName: String {
        isSnack ? String(localized: "간식") : String(localized: String.LocalizationValue(rawValue))
    }

    nonisolated var symbolColor: Color {
        switch self {
        case .breakfast: return .orange
        case .lunch: return .yellow
        case .dinner: return .blue
        case .snack1: return .green
        case .snack2: return .pink
        case .snack3: return .purple
        }
    }
}
