//
//  MealPaceViews.swift
//  RoutineCamera
//
//  밥 먹는 데 걸린 시간과 권하는 식사 시간을 보여 준다.
//  천천히 먹어야 적게 먹어도 배가 부르다 — 열량을 세는 대신 먹는 속도를 본다.
//  식전 사진을 남긴 때부터 식후 사진 · "다 먹음" 까지를 잰다 (MealPace).
//

import SwiftUI
import RoutineCameraCore

/// 사진 상세의 한 줄: 다 먹은 식사는 걸린 시간, 먹는 중인 식사는 지금까지 지난 시간
struct MealPaceRow: View {
    let record: MealRecord

    var body: some View {
        if let minutes = record.eatingMinutes {
            row(title: Text("식사 시간", comment: "Label: how long this meal took"),
                value: Text("\(minutes)분", comment: "Duration in minutes"),
                note: minutes >= MealPace.recommendedMinutes
                    ? Text("천천히 먹었어요", comment: "Meal pace: this meal was eaten slowly enough")
                    : Text("권장 \(MealPace.recommendedMinutes)분 이상", comment: "Meal pace: recommended meal length in minutes"),
                reached: minutes >= MealPace.recommendedMinutes)
        } else if record.isEatingInProgressToday, record.startedAt != nil {
            // 먹는 동안 열어 보면 1분마다 올라간다
            SwiftUI.TimelineView(.periodic(from: .now, by: 30)) { context in
                if let elapsed = MealPace.elapsedMinutes(since: record.startedAt, now: context.date) {
                    row(title: Text("먹는 중", comment: "Label: this meal is still being eaten"),
                        value: Text("\(elapsed)분", comment: "Duration in minutes"),
                        note: Text("권장 \(MealPace.recommendedMinutes)분 이상", comment: "Meal pace: recommended meal length in minutes"),
                        reached: elapsed >= MealPace.recommendedMinutes)
                }
            }
        }
    }

    private func row(title: Text, value: Text, note: Text, reached: Bool) -> some View {
        // 큰 글씨에서는 두 줄로 내려 잘리지 않게
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                label(title)
                Spacer(minLength: 8)
                trailing(value: value, note: note, reached: reached)
            }
            VStack(alignment: .leading, spacing: 4) {
                label(title)
                trailing(value: value, note: note, reached: reached)
            }
        }
        .font(.body)
        .accessibilityElement(children: .combine)
    }

    private func label(_ title: Text) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .accessibilityHidden(true)
            title.fontWeight(.semibold)
        }
        .foregroundColor(.secondary)
    }

    private func trailing(value: Text, note: Text, reached: Bool) -> some View {
        HStack(spacing: 6) {
            value.fontWeight(.semibold).monospacedDigit()
            Text(verbatim: "·").foregroundColor(.secondary)
            note.foregroundColor(reached ? .green : .secondary)
        }
    }
}

/// 통계의 "식사 속도" 카드: 보통 걸리는 시간, 권하는 시간, 끼니별 시간
struct MealPaceCard: View {
    @ObservedObject var mealStore: MealRecordStore
    var now: Date = Date()

    private let dayCount = 30

    /// 최근 30일만 날짜 목록에서 바로 꺼낸다 (전체 기록을 훑지 않는다)
    private var summary: MealPace.Summary? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let records = (0..<dayCount).flatMap { offset -> [MealRecord] in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return [] }
            return Array(mealStore.getMeals(for: day).values)
        }
        return MealPace.summary(of: records)
    }

    var body: some View {
        let summary = summary
        VStack(alignment: .leading, spacing: 12) {
            Text("식사 속도", comment: "Stats card title: how fast the user eats")
                .font(.title3)
                .fontWeight(.bold)

            if let summary {
                measured(summary)
            } else {
                Text("식전 사진을 찍고, 다 먹은 뒤 식후 사진을 찍거나 다 먹음을 누르면 식사 시간이 재져요.",
                     comment: "Meal pace card: how meal time gets measured (shown when nothing is measured yet)")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text("권장 \(MealPace.recommendedMinutes)분 이상", comment: "Meal pace: recommended meal length in minutes")
                    .font(.body.weight(.semibold))
            }

            // 왜 천천히인가 — 이 카드가 말하려는 것
            Text("천천히 먹으면 적게 먹어도 배가 불러요. 배부르다는 신호가 닿기까지 \(MealPace.recommendedMinutes)분쯤 걸려요.",
                 comment: "Meal pace card: why eating slowly matters; argument is minutes (20)")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }

    @ViewBuilder
    private func measured(_ summary: MealPace.Summary) -> some View {
        let tint: Color = summary.isUnhurried ? .green : .orange

        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    usualText(summary)
                    Spacer(minLength: 8)
                    recommendedText
                }
                VStack(alignment: .leading, spacing: 4) {
                    usualText(summary)
                    recommendedText
                }
            }

            // 막대 끝이 권하는 시간
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint)
                        .frame(width: geometry.size.width
                               * min(CGFloat(summary.usualMinutes) / CGFloat(MealPace.recommendedMinutes), 1))
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)

            Group {
                if summary.isUnhurried {
                    Text("좋아요, 충분히 천천히 먹고 있어요.", comment: "Meal pace card: usual meal time meets the recommendation")
                } else {
                    Text("지금보다 \(summary.minutesToSlowDown)분 더 천천히 먹어 보세요.",
                         comment: "Meal pace card: how many more minutes to take per meal")
                }
            }
            .font(.body.weight(.semibold))
            .foregroundColor(tint)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)

        // 끼니별 — 어느 끼니를 급하게 먹는지
        // 간식 칸 셋은 이름이 같아 구분되지 않으니 세 끼만
        let meals = [MealType.breakfast, .lunch, .dinner].filter { summary.usualByMeal[$0] != nil }
        if meals.count > 1 {
            VStack(spacing: 8) {
                ForEach(meals, id: \.self) { meal in
                    HStack {
                        Image(systemName: meal.symbolName)
                            .foregroundColor(meal.symbolColor)
                            .accessibilityHidden(true)
                        Text(meal.displayName)
                        Spacer()
                        Text("\(summary.usualByMeal[meal] ?? 0)분", comment: "Duration in minutes")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    .font(.body)
                    .accessibilityElement(children: .combine)
                }
            }
        }

        Text("최근 \(dayCount)일 · \(summary.mealCount)끼 기준",
             comment: "Meal pace card: period and number of timed meals the numbers are based on")
            .font(.body)
            .foregroundColor(.secondary)
    }

    private func usualText(_ summary: MealPace.Summary) -> some View {
        Text("보통 \(summary.usualMinutes)분", comment: "Meal pace card: the user's usual (median) meal length in minutes")
            .font(.title2)
            .fontWeight(.bold)
            .monospacedDigit()
    }

    private var recommendedText: some View {
        Text("권장 \(MealPace.recommendedMinutes)분 이상", comment: "Meal pace: recommended meal length in minutes")
            .font(.body)
            .foregroundColor(.secondary)
    }
}
