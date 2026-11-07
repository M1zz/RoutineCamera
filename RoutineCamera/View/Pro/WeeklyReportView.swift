//
//  WeeklyReportView.swift
//  RoutineCamera
//
//  세끼 프로 — 한 주를 한 장으로. 며칠 · 몇 끼 남겼는지, 끼니마다 보통 몇 시에 먹었는지, 날마다 찍은 사진.
//  놓친 것을 세지 않고 남긴 것을 센다 (앱 전체의 완벽주의 완화 원칙).
//

import SwiftUI
import RoutineCameraCore

struct WeeklyReportView: View {
    @ObservedObject var mealStore: MealRecordStore
    /// 0 = 이번 주, -1 = 지난 주 (기본)
    @State private var weekOffset = -1
    @AppStorage(NotificationManager.weeklyReportEnabledKey) private var notifyWeekly = true

    private let calendar = Calendar.current

    private var week: DateInterval {
        let anchor = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) ?? Date()
        return calendar.dateInterval(of: .weekOfYear, for: anchor) ?? DateInterval(start: anchor, duration: 7 * 86_400)
    }

    private var days: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }

    var body: some View {
        let records = mealStore.records.completed(in: week)
        List {
            Section {
                weekSwitcher
                HStack(spacing: 12) {
                    tile(value: Set(records.map { calendar.startOfDay(for: $0.date) }).count, unit: String(localized: "일 기록", comment: "Weekly report tile: days logged"))
                    tile(value: records.count, unit: String(localized: "끼 남김", comment: "Weekly report tile: meals logged"))
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
            }

            Section("보통 먹은 시각") {
                ForEach([MealType.breakfast, .lunch, .dinner], id: \.self) { meal in
                    usualTimeRow(meal, records: records.filter { $0.mealType == meal })
                }
            }

            Section("날마다") {
                ForEach(days, id: \.self) { day in
                    dayRow(day, records: records.filter { calendar.isDate($0.date, inSameDayAs: day) })
                }
            }

            Section {
                Toggle("월요일 아침에 알려 주기", isOn: $notifyWeekly)
                    .onChange(of: notifyWeekly) { _, _ in NotificationManager.shared.scheduleWeeklyReport() }
            }
        }
        .navigationTitle("주간 리포트")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var weekSwitcher: some View {
        HStack {
            Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("이전 주")
            Spacer()
            Text(week.start.formatted(.dateTime.month().day()) + " – "
                 + (calendar.date(byAdding: .day, value: 6, to: week.start) ?? week.end).formatted(.dateTime.month().day()))
                .font(.headline)
            Spacer()
            Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
                .disabled(weekOffset >= 0)
                .accessibilityLabel("다음 주")
        }
        .buttonStyle(.borderless)
    }

    private func tile(value: Int, unit: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func usualTimeRow(_ meal: MealType, records: [MealRecord]) -> some View {
        HStack {
            Label(meal.displayName, systemImage: meal.symbolName)
                .foregroundStyle(meal.symbolColor)
            Spacer()
            if let usual = usualTime(of: records) {
                Text("\(usual.formatted(date: .omitted, time: .shortened)) · \(records.count)번",
                     comment: "Weekly report: usual time for a meal and how many times it was logged")
                    .foregroundStyle(.secondary)
            } else {
                Text("기록 없음").foregroundStyle(.tertiary)
            }
        }
    }

    /// 찍은 시각들의 가운데 값 — 한 번 늦게 먹은 날에 끌려가지 않게 평균 대신 쓴다
    private func usualTime(of records: [MealRecord]) -> Date? {
        let minutes = records.compactMap(\.capturedAt).map { date -> Int in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }.sorted()
        guard !minutes.isEmpty else { return nil }
        let middle = minutes[minutes.count / 2]
        return calendar.date(bySettingHour: middle / 60, minute: middle % 60, second: 0, of: Date())
    }

    private func dayRow(_ day: Date, records: [MealRecord]) -> some View {
        HStack(spacing: 10) {
            Text(day.formatted(.dateTime.weekday(.abbreviated).day()))
                .font(.subheadline.weight(.semibold))
                .frame(width: 56, alignment: .leading)
            if records.isEmpty {
                Text("기록 없음").font(.subheadline).foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(records) { record in thumbnail(record) }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(day.formatted(.dateTime.weekday(.wide).month().day())), \(records.count)끼",
                                 comment: "VoiceOver: weekly report day row (date, meals logged)"))
    }

    private func thumbnail(_ record: MealRecord) -> some View {
        Group {
            if let data = record.thumbnailImageData {
                MealThumbnail(id: record.id, data: data, maxPixel: 132) { Color(.systemGray5) }
            } else {
                ZStack {
                    Color(.tertiarySystemFill)
                    Image(systemName: record.ateAll ? "checkmark.circle.fill" : record.mealType.symbolName)
                        .foregroundStyle(record.ateAll ? .green : record.mealType.symbolColor)
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
