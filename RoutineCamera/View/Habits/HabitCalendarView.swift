//
//  HabitCalendarView.swift
//  RoutineCamera
//
//  달력으로 돌아보기: 날마다 찍은 스탬프 · 물 · 카페인을 한 달 단위로 본다.
//  스탬프 하나를 고르면 그 스탬프를 찍은 날만 크게 보이고, 몇 번 · 며칠째인지 알려 준다.
//  이번 달은 무료, 지난 달과 이어 온 날 수는 플러스(habitHistory).
//

import SwiftUI
import RoutineCameraCore

struct HabitCalendarView: View {
    @ObservedObject var mealStore: MealRecordStore
    @ObservedObject private var habits = HabitStore.shared
    @ObservedObject private var subscription = SubscriptionManager.shared

    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var filter: String?
    @State private var selectedDay: SelectedDay?
    @State private var showingPaywall = false

    private struct SelectedDay: Identifiable {
        let date: Date
        var id: Date { date }
    }

    private var calendar: Calendar { .current }
    private var thisMonth: Date { calendar.dateInterval(of: .month, for: Date())?.start ?? Date() }
    private var historyUnlocked: Bool { subscription.allows(.habitHistory) }
    private var monthEnd: Date { calendar.date(byAdding: DateComponents(month: 1, day: -1), to: month) ?? month }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthHeader
                filterBar
                grid
                summary
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text("달력", comment: "Title: habit calendar"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedDay) { day in
            NavigationStack { HabitDayView(date: day.date, mealStore: mealStore) }
                .presentationDetents([.medium, .large])
        }
        .proPaywall(isPresented: $showingPaywall, lead: .habitHistory)
    }

    // MARK: - 달 넘기기

    private var monthHeader: some View {
        HStack {
            Button {
                if historyUnlocked { shiftMonth(-1) } else { showingPaywall = true }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("지난 달", comment: "VoiceOver: previous month"))

            Spacer()
            VStack(spacing: 2) {
                Text(month.formatted(.dateTime.year().month(.wide)))
                    .font(.headline)
                if !historyUnlocked && month == thisMonth {
                    ProBadge(feature: .habitHistory)
                        .onTapGesture { showingPaywall = true }
                }
            }
            Spacer()

            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(month >= thisMonth)
            .accessibilityLabel(Text("다음 달", comment: "VoiceOver: next month"))
        }
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: month), next <= thisMonth else { return }
        withAnimation(.easeInOut(duration: 0.2)) { month = next }
    }

    // MARK: - 스탬프 고르기

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(nil, label: String(localized: "전체", comment: "Calendar filter: all stamps"))
                ForEach(habits.stamps) { stamp in
                    filterChip(stamp.id, label: "\(stamp.symbol) \(stamp.displayName)")
                }
            }
        }
        .scrollClipDisabled()
    }

    private func filterChip(_ id: String?, label: String) -> some View {
        let selected = filter == id
        return Button {
            withAnimation(.snappy(duration: 0.2)) { filter = id }
        } label: {
            Text(label)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(Capsule().fill(selected ? Color.accentColor : Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - 달력 칸

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// 이 달의 칸들. 첫 주 앞의 빈 칸은 nil.
    private var days: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let dates = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: leading) + dates.map { Optional($0) }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 64) }
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func dayCell(_ day: Date) -> some View {
        let log = habits.log(on: day)
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > Date()
        let ateSomething = mealStore.dietMeals(for: day).values.contains { $0.isComplete }
        let shown = log.stamps.compactMap(habits.stamp(id:)).sorted { order($0) < order($1) }

        return Button {
            selectedDay = SelectedDay(date: day)
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.footnote.weight(isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isToday ? Color.white : (isFuture ? Color.secondary : Color.primary))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(isToday ? Color.accentColor : Color.clear))

                if let filter {
                    let stamped = log.stamps.contains(filter)
                    Text(habits.stamp(id: filter)?.symbol ?? "")
                        .font(.title3)
                        .opacity(stamped ? 1 : 0)
                } else {
                    Text(shown.prefix(3).map(\.symbol).joined())
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(height: 14)
                    HStack(spacing: 2) {
                        if log.water > 0 { Image(systemName: "drop.fill").foregroundStyle(.cyan) }
                        if log.caffeine > 0 { Image(systemName: "cup.and.saucer.fill").foregroundStyle(.brown) }
                        if ateSomething { Circle().fill(Color.secondary.opacity(0.5)).frame(width: 4, height: 4) }
                    }
                    .font(.system(size: 7))
                    .frame(height: 8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .top)
            .padding(.top, 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(filter.map { log.stamps.contains($0) } == true
                          ? (habits.stamp(id: filter!)?.kind.color ?? .green).opacity(0.15)
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.month().day().weekday(.wide)))
        .accessibilityValue(accessibilityValue(log, ateSomething: ateSomething))
    }

    private func order(_ stamp: Stamp) -> Int {
        habits.stamps.firstIndex { $0.id == stamp.id } ?? Int.max
    }

    private func accessibilityValue(_ log: DayLog, ateSomething: Bool) -> String {
        var parts = log.stamps.compactMap(habits.stamp(id:)).map(\.displayName)
        if log.water > 0 { parts.append(String(localized: "물 \(log.water)잔", comment: "VoiceOver: glasses of water")) }
        if log.caffeine > 0 { parts.append(String(localized: "카페인 \(log.caffeine)잔", comment: "VoiceOver: caffeinated drinks")) }
        if ateSomething { parts.append(String(localized: "식사 기록 있음", comment: "VoiceOver: day has meal entries")) }
        return parts.isEmpty ? String(localized: "기록 없음", comment: "VoiceOver: nothing recorded on this day") : parts.formatted()
    }

    // MARK: - 요약

    @ViewBuilder
    private var summary: some View {
        if let filter, let stamp = habits.stamp(id: filter) {
            stampSummary(stamp)
        } else {
            monthSummary
        }
    }

    private func stampSummary(_ stamp: Stamp) -> some View {
        let count = HabitStats.count(of: stamp.id, in: habits.logs, from: month, to: monthEnd)
        return VStack(alignment: .leading, spacing: 12) {
            Text("\(stamp.symbol) \(stamp.displayName)")
                .font(.headline)
            statRow(String(localized: "이번 달 찍은 날", comment: "Stat: days stamped in the shown month"),
                    value: String(localized: "\(count)일", comment: "Number of days"))
            if historyUnlocked {
                statRow(String(localized: "지금 이어 가는 날", comment: "Stat: current streak"),
                        value: String(localized: "\(HabitStats.currentStreak(of: stamp.id, in: habits.logs))일", comment: "Number of days"))
                statRow(String(localized: "가장 길게 이은 날", comment: "Stat: longest streak"),
                        value: String(localized: "\(HabitStats.longestStreak(of: stamp.id, in: habits.logs))일", comment: "Number of days"))
            } else {
                Button { showingPaywall = true } label: {
                    HStack {
                        Text("며칠째 이어 가는지 보기", comment: "Locked stat: see streaks")
                        Spacer()
                        ProBadge(feature: .habitHistory)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var monthSummary: some View {
        let monthLogs = habits.logs.filter { key, _ in
            guard let date = DayKey.date(from: key) else { return false }
            return date >= month && date <= monthEnd.addingTimeInterval(86_399)
        }.map(\.value)
        let stampCounts = habits.stamps
            .map { ($0, HabitStats.count(of: $0.id, in: habits.logs, from: month, to: monthEnd)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        let waterDays = monthLogs.filter { $0.water > 0 }
        let caffeineDays = monthLogs.filter { $0.caffeine > 0 }
        let monthMeals = mealsInMonth
        let portions = HabitStats.portionCounts(of: monthMeals)

        return VStack(alignment: .leading, spacing: 12) {
            Text("이번 달", comment: "Summary card title: the shown month")
                .font(.headline)

            if stampCounts.isEmpty && waterDays.isEmpty && caffeineDays.isEmpty && portions.isEmpty {
                Text("스탬프를 찍거나 물을 마실 때마다 여기에 모여요.", comment: "Calendar summary empty state")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(stampCounts, id: \.0.id) { stamp, count in
                statRow("\(stamp.symbol) \(stamp.displayName)", value: String(localized: "\(count)일", comment: "Number of days"))
            }
            if !waterDays.isEmpty {
                statRow(String(localized: "물 (기록한 날 평균)", comment: "Stat: average glasses of water on logged days"),
                        value: String(localized: "\(average(waterDays.map(\.water)))잔", comment: "Number of cups/glasses"))
            }
            if !caffeineDays.isEmpty {
                statRow(String(localized: "카페인 (기록한 날 평균)", comment: "Stat: average caffeinated drinks on logged days"),
                        value: String(localized: "\(average(caffeineDays.map(\.caffeine)))잔", comment: "Number of cups/glasses"))
            }
            if !portions.isEmpty {
                Divider()
                Text("먹은 양", comment: "Stat group: how much was eaten")
                    .font(.subheadline.weight(.semibold))
                ForEach(MealPortion.allCases, id: \.self) { portion in
                    if let count = portions[portion] {
                        statRow(portion.tagTitle, value: String(localized: "\(count)끼", comment: "Number of meals"))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var mealsInMonth: [MealRecord] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
            .flatMap { mealStore.dietMeals(for: $0).values }
    }

    /// 소수점 한 자리 평균 (예: 6.5)
    private func average(_ values: [Int]) -> String {
        let value = Double(values.reduce(0, +)) / Double(max(values.count, 1))
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func statRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

/// 달력에서 고른 하루: 스탬프 · 잔 수를 고치고, 그날 끼니를 얼마나 먹었는지 본다.
struct HabitDayView: View {
    let date: Date
    @ObservedObject var mealStore: MealRecordStore
    @Environment(\.dismiss) private var dismiss

    private var meals: [MealRecord] {
        mealStore.dietMeals(for: date).values.filter(\.isComplete).sorted { $0.feedDate < $1.feedDate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DayCheckInCard(date: date, wrapsStamps: true)

                if !meals.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("이날 먹은 끼니", comment: "Section: meals on this day")
                            .font(.subheadline.weight(.semibold))
                        ForEach(meals) { meal in
                            HStack(spacing: 10) {
                                if let data = meal.thumbnailImageData {
                                    MealThumbnail(id: meal.id, data: data, maxPixel: 120) { Color(.tertiarySystemBackground) }
                                        .frame(width: 40, height: 40)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Text(meal.mealType.displayName)
                                Spacer()
                                PortionPicker(portion: meal.portion) { portion in
                                    mealStore.updatePortion(date: meal.date, mealType: meal.mealType, portion: portion)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(16)
        }
        .navigationTitle(date.formatted(.dateTime.month().day().weekday(.wide)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "완료"), systemImage: "checkmark") { dismiss() }
            }
        }
    }
}

/// 얼마나 먹었는지 고르기 — 다 / 절반 / 조금. 고른 것을 다시 누르면 지운다.
struct PortionPicker: View {
    let portion: MealPortion?
    let change: (MealPortion?) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MealPortion.allCases, id: \.self) { option in
                let selected = option == portion
                Button {
                    change(selected ? nil : option)
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(Capsule().fill(selected ? Color.accentColor : Color(.tertiarySystemBackground)))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: selected)
                .accessibilityLabel(option.tagTitle)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
