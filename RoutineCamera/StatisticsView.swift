//
//  StatisticsView.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/11/25.
//

import SwiftUI

struct StatisticsView: View {
    @ObservedObject var mealStore: MealRecordStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // 주간 통계
                    WeeklyStatsView(mealStore: mealStore)

                    // 월간 통계
                    MonthlyStatsView(mealStore: mealStore)

                    // 식사별 통계
                    MealTypeStatsView(mealStore: mealStore)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("통계")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// 주간 통계 뷰
struct WeeklyStatsView: View {
    @ObservedObject var mealStore: MealRecordStore

    private var weeklyStats: (recorded: Int, total: Int, percentage: Double) {
        let calendar = Calendar.current
        let today = Date()
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!

        var recorded = 0
        var total = 0

        for day in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: day, to: startOfWeek) {
                let meals = mealStore.getMeals(for: date)
                recorded += meals.values.filter { $0.isComplete }.count
                total += 3
            }
        }

        let percentage = total > 0 ? Double(recorded) / Double(total) * 100 : 0
        return (recorded, total, percentage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("이번 주 기록")
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack {
                // 진행 바
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(weeklyStats.recorded)/\(weeklyStats.total)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("식사 기록")
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray5))
                                .frame(height: 12)

                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue)
                                .frame(width: geometry.size.width * CGFloat(weeklyStats.percentage / 100), height: 12)
                        }
                    }
                    .frame(height: 12)

                    Text("\(Int(weeklyStats.percentage))% 달성")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer()
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// 월간 통계 뷰
struct MonthlyStatsView: View {
    @ObservedObject var mealStore: MealRecordStore

    private var monthlyStats: (recorded: Int, total: Int, percentage: Double) {
        let calendar = Calendar.current
        let today = Date()
        let range = calendar.range(of: .day, in: .month, for: today)!
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!

        var recorded = 0
        var total = 0

        for day in 0..<range.count {
            if let date = calendar.date(byAdding: .day, value: day, to: startOfMonth) {
                let meals = mealStore.getMeals(for: date)
                recorded += meals.values.filter { $0.isComplete }.count
                total += 3
            }
        }

        let percentage = total > 0 ? Double(recorded) / Double(total) * 100 : 0
        return (recorded, total, percentage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("이번 달 기록")
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(monthlyStats.recorded)/\(monthlyStats.total)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("식사 기록")
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray5))
                                .frame(height: 12)

                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.green)
                                .frame(width: geometry.size.width * CGFloat(monthlyStats.percentage / 100), height: 12)
                        }
                    }
                    .frame(height: 12)

                    Text("\(Int(monthlyStats.percentage))% 달성")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer()
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// 식사별 통계 뷰
struct MealTypeStatsView: View {
    @ObservedObject var mealStore: MealRecordStore

    private func getMealTypeStats(mealType: MealType) -> (recorded: Int, total: Int, percentage: Double) {
        let calendar = Calendar.current
        let today = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
        let range = calendar.range(of: .day, in: .month, for: today)!

        var recorded = 0
        let total = range.count

        for day in 0..<range.count {
            if let date = calendar.date(byAdding: .day, value: day, to: startOfMonth) {
                let meals = mealStore.getMeals(for: date)
                if let meal = meals[mealType], meal.isComplete {
                    recorded += 1
                }
            }
        }

        let percentage = total > 0 ? Double(recorded) / Double(total) * 100 : 0
        return (recorded, total, percentage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("식사별 기록률 (이번 달)")
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            ForEach(MealType.allCases, id: \.self) { mealType in
                let stats = getMealTypeStats(mealType: mealType)

                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: mealType.symbolName)
                            .foregroundColor(mealType.symbolColor)
                        Text(mealType.rawValue)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer()
                        Text("\(stats.recorded)/\(stats.total)")
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("\(Int(stats.percentage))%")
                            .fontWeight(.bold)
                            .foregroundColor(stats.percentage >= 80 ? .green : stats.percentage >= 50 ? .orange : .red)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.systemGray5))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 6)
                                .fill(stats.percentage >= 80 ? Color.green : stats.percentage >= 50 ? Color.orange : Color.red)
                                .frame(width: geometry.size.width * CGFloat(stats.percentage / 100), height: 8)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}
