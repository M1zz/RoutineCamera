//
//  MealRhythmCard.swift
//  RoutineCamera
//
//  순간 피드 맨 위의 "최근 7일 식사 리듬" 카드.
//  피드는 남긴 기록만 보여주므로, 끼니를 규칙적으로 챙기고 있는지는 여기서 한눈에 본다.
//  끼니(행) × 날짜(열) 점 격자 — 오늘 아직 안 먹은 끼니는 빈 칸이 아니라 점선으로 "남은 자리"만 표시.
//

import SwiftUI

struct MealRhythmCard: View {
    @ObservedObject var mealStore: MealRecordStore
    @ObservedObject private var settingsManager = SettingsManager.shared
    var now: Date = Date()

    private let dayCount = 7

    // 챙기기로 한 주요 끼니만 (간식은 규칙성 지표가 아니다)
    private var meals: [MealType] {
        let cared = [MealType.breakfast, .lunch, .dinner].filter { settingsManager.caredMeals.contains($0) }
        return cared.isEmpty ? [.breakfast, .lunch, .dinner] : cared
    }

    // 왼쪽=6일 전, 오른쪽=오늘
    private var days: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        return (0..<dayCount).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    // 날짜별 기록된 끼니
    private var recorded: [Date: Set<MealType>] {
        let cal = Calendar.current
        guard let first = days.first else { return [:] }
        var result: [Date: Set<MealType>] = [:]
        for r in mealStore.records where r.isComplete {
            let day = cal.startOfDay(for: r.date)
            guard day >= first else { continue }
            result[day, default: []].insert(r.mealType)
        }
        return result
    }

    private var fullDays: Int {
        let rec = recorded
        return days.filter { day in meals.allSatisfy { rec[day]?.contains($0) ?? false } }.count
    }

    private var rhythmTitle: some View {
        Text("최근 7일 식사 리듬")
            .font(.headline)
    }

    private var fullDaysText: some View {
        Text("다 챙긴 날 \(fullDays)일")
            .font(.body.weight(.semibold))
            .foregroundColor(fullDays > 0 ? .green : .secondary)
    }

    var body: some View {
        let rec = recorded
        VStack(alignment: .leading, spacing: 12) {
            // 좁은 화면·큰 글씨에서는 제목 아래로 내려 둘 다 잘리지 않게
            ViewThatFits(in: .horizontal) {
                HStack {
                    rhythmTitle
                    Spacer()
                    fullDaysText
                }
                VStack(alignment: .leading, spacing: 4) {
                    rhythmTitle
                    fullDaysText
                }
            }

            Grid(horizontalSpacing: 0, verticalSpacing: 10) {
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    ForEach(days, id: \.self) { day in
                        Text(weekdayLabel(day))
                            .font(.body)
                            .fontWeight(Calendar.current.isDateInToday(day) ? .bold : .regular)
                            .foregroundColor(Calendar.current.isDateInToday(day) ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                    }
                    Color.clear.frame(width: 1, height: 1)
                }

                ForEach(meals) { meal in
                    let count = days.filter { rec[$0]?.contains(meal) ?? false }.count
                    GridRow {
                        Text(meal.displayName)
                            .font(.body)
                            .gridColumnAlignment(.leading)
                        ForEach(days, id: \.self) { day in
                            dot(meal: meal, done: rec[day]?.contains(meal) ?? false,
                                isToday: Calendar.current.isDateInToday(day))
                                .frame(maxWidth: .infinity)
                        }
                        Text("\(count)/\(dayCount)")
                            .font(.body.monospacedDigit())
                            .foregroundColor(.secondary)
                            .gridColumnAlignment(.trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(meal.displayName), 최근 7일 중 \(count)일 기록")
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func dot(meal: MealType, done: Bool, isToday: Bool) -> some View {
        let size: CGFloat = 18
        if done {
            Circle()
                .fill(meal.symbolColor)
                .frame(width: size, height: size)
        } else if isToday {
            // 오늘은 아직 끝나지 않았으니 "거름"이 아니라 남은 자리
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .foregroundColor(meal.symbolColor.opacity(0.6))
                .frame(width: size, height: size)
        } else {
            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: size, height: size)
        }
    }

    private func weekdayLabel(_ day: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "E"
        return fmt.string(from: day)
    }
}
