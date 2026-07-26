//
//  CaredMealsView.swift
//  RoutineCamera
//
//  "챙기고 싶은 식사"만 골라 그 식사만 알림을 받게 하는 UI.
//  삼시세끼 전부 알림으로 인한 스트레스를 줄이기 위함.
//

import SwiftUI

// 아침/점심/저녁 중 챙길 식사를 칩으로 선택 (프롬프트·설정에서 공용)
struct MealCareSelector: View {
    @ObservedObject private var settingsManager = SettingsManager.shared
    private let meals: [MealType] = [.breakfast, .lunch, .dinner]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(meals) { meal in
                let on = settingsManager.caredMeals.contains(meal)
                Button {
                    if on { settingsManager.caredMeals.remove(meal) }
                    else { settingsManager.caredMeals.insert(meal) }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: meal.symbolName)
                            .font(.system(size: 22))
                            .foregroundColor(on ? meal.symbolColor : .secondary)
                        Text(meal.rawValue)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(on ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(on ? meal.symbolColor.opacity(0.15) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(on ? meal.symbolColor : Color.clear, lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(meal.rawValue) 챙기기")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

// 첫 실행 시 "어떤 식사를 챙기고 싶은지" 물어보는 프롬프트 시트
struct CaredMealsPromptView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("어떤 식사를 챙기고 싶어요?")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("고른 식사만 살짝 알려드릴게요.\n나머지는 부담 없이, 기록하고 싶을 때만.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            MealCareSelector()

            Text(settingsManager.caredMeals.isEmpty
                 ? "아무것도 안 골라도 괜찮아요 — 알림 없이 원할 때만 기록해요."
                 : "\(caredSummary) 알림을 받아요. 언제든 설정에서 바꿀 수 있어요.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 8)

            Button {
                settingsManager.hasConfiguredCaredMeals = true
                dismiss()
            } label: {
                Text("이렇게 할게요")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .presentationDetents([.medium, .large])
    }

    private var caredSummary: String {
        let order: [MealType] = [.breakfast, .lunch, .dinner]
        return order.filter { settingsManager.caredMeals.contains($0) }
            .map { $0.rawValue }
            .joined(separator: "·")
    }
}
