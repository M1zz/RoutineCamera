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
    @State private var showingBeforeAfterComparison = false

    private var navigationTitle: String {
        "\(SettingsManager.shared.albumType.rawValue) 통계"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // 연속 기록 및 목표
                    StreakAndGoalView(mealStore: mealStore)

                    // 업적 섹션
                    AchievementsSectionView()

                    // Before/After 비교 버튼 (식단 모드에서만)
                    if SettingsManager.shared.albumType == .diet {
                        BeforeAfterComparisonButton(showingComparison: $showingBeforeAfterComparison)
                    }

                    // 주간 통계
                    WeeklyStatsView(mealStore: mealStore)

                    // 월간 통계
                    MonthlyStatsView(mealStore: mealStore)

                    // 식사별 통계 (식단 모드에서만)
                    if SettingsManager.shared.albumType == .diet {
                        MealTypeStatsView(mealStore: mealStore)
                    }

                    // 음식 소비 통계 (식단 모드에서만)
                    if SettingsManager.shared.albumType == .diet {
                        FoodConsumptionStatsView(mealStore: mealStore)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingBeforeAfterComparison) {
                BeforeAfterComparisonView(mealStore: mealStore)
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

        let isExerciseMode = SettingsManager.shared.albumType == .exercise

        for day in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: day, to: startOfWeek) {
                let meals = mealStore.getMeals(for: date)
                if isExerciseMode {
                    // 운동 모드: 하루 1회
                    if meals[.breakfast]?.isComplete ?? false {
                        recorded += 1
                    }
                    total += 1
                } else {
                    // 식단 모드: 하루 3끼
                    recorded += meals.values.filter { $0.isComplete }.count
                    total += 3
                }
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
                        Text(SettingsManager.shared.albumType == .exercise ? "운동 기록" : "식사 기록")
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

        let isExerciseMode = SettingsManager.shared.albumType == .exercise

        for day in 0..<range.count {
            if let date = calendar.date(byAdding: .day, value: day, to: startOfMonth) {
                let meals = mealStore.getMeals(for: date)
                if isExerciseMode {
                    // 운동 모드: 하루 1회
                    if meals[.breakfast]?.isComplete ?? false {
                        recorded += 1
                    }
                    total += 1
                } else {
                    // 식단 모드: 하루 3끼
                    recorded += meals.values.filter { $0.isComplete }.count
                    total += 3
                }
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
                        Text(SettingsManager.shared.albumType == .exercise ? "운동 기록" : "식사 기록")
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

// 연속 기록 및 목표 뷰
struct StreakAndGoalView: View {
    @ObservedObject var mealStore: MealRecordStore

    var body: some View {
        VStack(spacing: 16) {
            // 연속 기록
            HStack(spacing: 20) {
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("🔥")
                            .font(.title)
                        Text("\(mealStore.getCurrentStreak())")
                            .font(.system(size: 36, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    Text("현재 연속")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 60)

                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("🏆")
                            .font(.title)
                        Text("\(mealStore.getMaxStreak())")
                            .font(.system(size: 36, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    Text("최고 연속")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// 업적 섹션 뷰
struct AchievementsSectionView: View {
    @StateObject private var achievementManager = AchievementManager.shared
    @State private var showingAllAchievements = false

    private var unlockedCount: Int {
        achievementManager.achievements.filter { $0.isUnlocked }.count
    }

    private var recentAchievements: [Achievement] {
        achievementManager.achievements
            .filter { $0.isUnlocked }
            .sorted { ($0.unlockedDate ?? Date.distantPast) > ($1.unlockedDate ?? Date.distantPast) }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("업적")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Text("\(unlockedCount)/\(achievementManager.achievements.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // 진행도 바
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange)
                        .frame(width: geometry.size.width * CGFloat(unlockedCount) / CGFloat(achievementManager.achievements.count), height: 12)
                }
            }
            .frame(height: 12)

            // 최근 달성 업적
            if !recentAchievements.isEmpty {
                VStack(spacing: 8) {
                    ForEach(recentAchievements) { achievement in
                        HStack {
                            Text(achievement.icon)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(achievement.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(achievement.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
            }

            Button(action: {
                showingAllAchievements = true
            }) {
                Text("모든 업적 보기")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        .sheet(isPresented: $showingAllAchievements) {
            AllAchievementsView()
        }
    }
}

// 모든 업적 뷰
struct AllAchievementsView: View {
    @StateObject private var achievementManager = AchievementManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(achievementManager.achievements) { achievement in
                        HStack(spacing: 12) {
                            Text(achievement.icon)
                                .font(.system(size: 40))
                                .opacity(achievement.isUnlocked ? 1.0 : 0.3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(achievement.title)
                                    .font(.headline)
                                    .foregroundColor(achievement.isUnlocked ? .primary : .secondary)

                                Text(achievement.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if let date = achievement.unlockedDate {
                                    Text(date, style: .date)
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }

                            Spacer()

                            if achievement.isUnlocked {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title3)
                            } else {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.gray)
                                    .font(.title3)
                            }
                        }
                        .padding(16)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("모든 업적")
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

// Before/After 비교 버튼
struct BeforeAfterComparisonButton: View {
    @Binding var showingComparison: Bool

    var body: some View {
        Button(action: {
            showingComparison = true
        }) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title3)
                Text("Before/After 비교")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .foregroundColor(.primary)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        }
    }
}

// Before/After 비교 뷰
struct BeforeAfterComparisonView: View {
    @ObservedObject var mealStore: MealRecordStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedPeriod: ComparisonPeriod = .oneWeek

    enum ComparisonPeriod: String, CaseIterable {
        case oneWeek = "1주 전"
        case twoWeeks = "2주 전"
        case oneMonth = "1개월 전"

        var daysAgo: Int {
            switch self {
            case .oneWeek: return 7
            case .twoWeeks: return 14
            case .oneMonth: return 30
            }
        }
    }

    private func getMealsForDate(_ date: Date) -> [MealType: MealRecord] {
        mealStore.getMeals(for: date)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 기간 선택
                    Picker("기간", selection: $selectedPeriod) {
                        ForEach(ComparisonPeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)

                    let beforeDate = Calendar.current.date(byAdding: .day, value: -selectedPeriod.daysAgo, to: Date())!
                    let todayDate = Date()

                    // Before
                    ComparisonDayView(
                        title: "Before (\(selectedPeriod.rawValue))",
                        date: beforeDate,
                        meals: getMealsForDate(beforeDate)
                    )

                    // After (오늘)
                    ComparisonDayView(
                        title: "After (오늘)",
                        date: todayDate,
                        meals: getMealsForDate(todayDate)
                    )

                    // 통계 비교
                    ComparisonStatsView(
                        mealStore: mealStore,
                        beforeDate: beforeDate,
                        afterDate: todayDate
                    )
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Before/After 비교")
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

// 비교 날짜 뷰
struct ComparisonDayView: View {
    let title: String
    let date: Date
    let meals: [MealType: MealRecord]

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일 (E)"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(dateFormatter.string(from: date))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                ForEach(MealType.allCases, id: \.self) { mealType in
                    VStack(spacing: 8) {
                        if let meal = meals[mealType], meal.isComplete {
                            if let photoData = meal.thumbnailImageData, let uiImage = UIImage(data: photoData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                        .frame(width: 100, height: 100)
                                    Text("📷")
                                        .font(.system(size: 40))
                                }
                            }
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                                    .frame(width: 100, height: 100)
                                Text("기록 없음")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text(mealType.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        .padding(.horizontal)
    }
}

// 통계 비교 뷰
struct ComparisonStatsView: View {
    @ObservedObject var mealStore: MealRecordStore
    let beforeDate: Date
    let afterDate: Date

    private func getWeeklyRecordCount(from date: Date) -> Int {
        let calendar = Calendar.current
        var count = 0

        for i in 0..<7 {
            if let checkDate = calendar.date(byAdding: .day, value: -i, to: date) {
                let meals = mealStore.getMeals(for: checkDate)
                count += meals.values.filter { $0.isComplete }.count
            }
        }

        return count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("주간 기록 비교")
                .font(.headline)

            HStack {
                VStack(spacing: 8) {
                    Text("Before")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(getWeeklyRecordCount(from: beforeDate))")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("기록")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Image(systemName: "arrow.right")
                    .foregroundColor(.blue)
                    .font(.title2)

                VStack(spacing: 8) {
                    Text("After")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(getWeeklyRecordCount(from: afterDate))")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("기록")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            let difference = getWeeklyRecordCount(from: afterDate) - getWeeklyRecordCount(from: beforeDate)
            if difference > 0 {
                Text("✨ \(difference)회 더 기록했어요!")
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            } else if difference < 0 {
                Text("💪 조금만 더 힘내세요!")
                    .font(.subheadline)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            } else {
                Text("동일한 기록을 유지하고 있어요")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        .padding(.horizontal)
    }
}

// 음식 소비 통계 뷰
struct FoodConsumptionStatsView: View {
    @ObservedObject var mealStore: MealRecordStore
    @State private var selectedPeriod: ConsumptionPeriod = .week

    enum ConsumptionPeriod: String, CaseIterable {
        case week = "이번 주"
        case month = "이번 달"
    }

    // 기간별 음식 데이터 가져오기 (음식별 식사 횟수)
    private func getFoodConsumption(period: ConsumptionPeriod) -> [(food: String, mealCount: Int)] {
        let calendar = Calendar.current
        let today = Date()
        let startDate: Date

        switch period {
        case .week:
            startDate = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        case .month:
            startDate = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
        }

        // 각 음식이 어떤 식사들에서 나왔는지 추적
        var foodToMeals: [String: Set<String>] = [:] // "음식명": Set(["2025-11-19-breakfast", "2025-11-19-lunch", ...])

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for record in mealStore.records {
            // 기간 내의 기록만 처리
            guard record.date >= startDate, record.date <= today else { continue }

            // Vision 분석이 있고 음식 항목이 있는 경우만 처리
            if let analysis = record.visionAnalysis, !analysis.foodItems.isEmpty {
                // 고유 식사 ID 생성 (날짜-식사타입)
                let mealId = "\(dateFormatter.string(from: record.date))-\(record.mealType.rawValue)"

                // 이 식사의 모든 음식 태그에 대해
                for food in analysis.foodItems {
                    if foodToMeals[food] == nil {
                        foodToMeals[food] = []
                    }
                    // 이 음식이 이 식사에 포함되어 있음을 기록
                    foodToMeals[food]?.insert(mealId)
                }
            }
        }

        // 음식별 식사 횟수로 변환 및 정렬 (많이 먹은 순서대로)
        let result = foodToMeals.map { (food: $0.key, mealCount: $0.value.count) }
            .sorted { $0.mealCount > $1.mealCount }

        return result
    }

    private var foodConsumption: [(food: String, mealCount: Int)] {
        getFoodConsumption(period: selectedPeriod)
    }

    private var totalMealsWithAnalysis: Int {
        let calendar = Calendar.current
        let today = Date()
        let startDate: Date

        switch selectedPeriod {
        case .week:
            startDate = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        case .month:
            startDate = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
        }

        return mealStore.records.filter { record in
            record.date >= startDate &&
            record.date <= today &&
            record.visionAnalysis != nil &&
            !record.visionAnalysis!.foodItems.isEmpty
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("음식 소비 통계")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Picker("기간", selection: $selectedPeriod) {
                    ForEach(ConsumptionPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 180)
            }

            if foodConsumption.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "fork.knife.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("분석된 음식 데이터가 없습니다")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("식사 사진을 촬영하고 분석하면\n먹은 음식들을 여기서 확인할 수 있어요")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 4) {
                    Text("총 \(totalMealsWithAnalysis)개 식사 분석됨")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(foodConsumption.count)가지 음식 섭취")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)

                Divider()

                // 음식 목록 (상위 10개만 표시)
                VStack(spacing: 10) {
                    ForEach(Array(foodConsumption.prefix(10).enumerated()), id: \.element.food) { index, item in
                        HStack {
                            // 순위
                            Text("#\(index + 1)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(index < 3 ?
                                            (index == 0 ? Color.yellow : index == 1 ? Color.gray : Color.orange) :
                                            Color.blue.opacity(0.6)
                                        )
                                )

                            // 음식명
                            Text(item.food)
                                .font(.subheadline)
                                .lineLimit(1)

                            Spacer()

                            // 식사 횟수
                            HStack(spacing: 4) {
                                Text("\(item.mealCount)")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                                Text("끼")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if foodConsumption.count > 10 {
                    Text("외 \(foodConsumption.count - 10)가지 더 있음")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}
