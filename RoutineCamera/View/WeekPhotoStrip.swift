//
//  WeekPhotoStrip.swift
//  RoutineCamera
//
//  홈 맨 위의 최근 7일 사진 띠. 먹은 날은 그날 사진으로 채워지고, 오늘은 아직 남은 자리로 보인다.
//  어제 남긴 사진 옆에 오늘 칸이 비어 있는 것 — 앱을 다시 열었을 때 "오늘도 하나" 가 보이게 하는 것이 목적이다.
//  누르면 달력이 열린다. 지난 빈 날은 조용한 회색일 뿐, 거른 날로 벌주지 않는다.
//

import SwiftUI
import RoutineCameraCore

extension MealRecordStore {
    /// 그날을 대표하는 식단 사진 한 장 — 가장 늦게 먹은 끼니의 사진. 달력 칸 · 7일 띠가 쓴다.
    func coverMeal(on date: Date) -> MealRecord? {
        dietMeals(for: date).values
            .filter { $0.isComplete && $0.thumbnailImageData != nil }
            .max { $0.feedDate < $1.feedDate }
    }
}

struct WeekPhotoStrip: View {
    @ObservedObject var mealStore: MealRecordStore
    var now: Date = Date()
    let action: () -> Void

    // 왼쪽=6일 전, 오른쪽=오늘
    private var days: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        return (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    var body: some View {
        let recordedCount = days.filter { day in mealStore.dietMeals(for: day).values.contains(where: \.isComplete) }.count
        Button(action: action) {
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    dayColumn(day)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(String(localized: "달력", comment: "Title: habit calendar")), 최근 7일 중 \(recordedCount)일 기록")
        .accessibilityAddTraits(.isButton)
    }

    private func dayColumn(_ day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        return VStack(spacing: 4) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.caption.weight(isToday ? .bold : .regular).monospacedDigit())
                .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { cellContent(day, isToday: isToday) }
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func cellContent(_ day: Date, isToday: Bool) -> some View {
        if let cover = mealStore.coverMeal(on: day), let data = cover.thumbnailImageData {
            MealThumbnail(id: cover.id, data: data, maxPixel: 180) { Color(.tertiarySystemFill) }
        } else if mealStore.dietMeals(for: day).values.contains(where: \.isComplete) {
            // 사진 없이 남긴 날
            ZStack {
                Color.green.opacity(0.15)
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
            }
        } else if isToday {
            // 오늘은 아직 끝나지 않았으니 빈 날이 아니라 남은 자리
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .foregroundStyle(Color.accentColor.opacity(0.6))
                .overlay {
                    Image(systemName: "camera")
                        .font(.footnote)
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                }
        } else {
            Color(.tertiarySystemFill)
        }
    }
}
