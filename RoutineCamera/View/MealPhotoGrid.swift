//
//  MealPhotoGrid.swift
//  RoutineCamera
//
//  기록 사진을 3열 정사각형 격자로 한눈에 — 운동 앨범의 메인 화면이고, 식단은 피드에서 격자로 바꿔 볼 때 쓴다.
//  월별로 묶고 칸마다 날짜를 얹어, 사진만 훑어도 언제 남긴 기록인지 읽힌다.
//  지금 보고 있는 앨범(식단 · 운동)의 기록을 그린다.
//

import SwiftUI
import RoutineCameraCore

struct MealPhotoGrid<Header: View>: View {
    @ObservedObject var mealStore: MealRecordStore
    @ObservedObject private var settingsManager = SettingsManager.shared
    private let header: Header

    /// - Parameter header: 격자 위에 함께 스크롤되는 것 (홈의 7일 띠 등)
    init(mealStore: MealRecordStore, @ViewBuilder header: () -> Header = { EmptyView() }) {
        self.mealStore = mealStore
        self.header = header()
    }

    private var isExercise: Bool { settingsManager.albumType == .exercise }

    private let spacing: CGFloat = 2
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3)
    }

    /// 기록이 하나라도 있는지 — 없으면 부르는 쪽이 빈 화면을 보여 준다
    static func hasRecords(in mealStore: MealRecordStore) -> Bool {
        mealStore.records.contains(where: \.isComplete)
    }

    /// 월별 묶음 (최신 월 먼저), 각 월 안에서도 최신순.
    /// 날짜는 기록이 속한 날(record.date)로 판단한다 — 지난 날 기록을 오늘 올려도 그날 칸에 들어가야 한다.
    private var monthGroups: [(month: Date, records: [MealRecord])] {
        let cal = Calendar.current
        // 정렬 열쇠를 한 번만 계산한다 (비교할 때마다 startOfDay 를 두 번씩 하지 않게)
        // 타입을 적어 둔다 — 추론에 맡기면 이 식 하나가 타입 검사에 5초 가까이 걸렸다
        let keyed: [Keyed] = mealStore.records.compactMap { (r: MealRecord) -> Keyed? in
            r.isComplete ? Keyed(record: r, day: cal.startOfDay(for: r.date), time: r.feedDate) : nil
        }
        let records: [MealRecord] = keyed
            .sorted { (a: Keyed, b: Keyed) -> Bool in a.day != b.day ? a.day > b.day : a.time > b.time }
            .map { $0.record }
        let grouped: [Date: [MealRecord]] = Dictionary(grouping: records) { (r: MealRecord) -> Date in
            cal.date(from: cal.dateComponents([.year, .month], from: r.date)) ?? r.date
        }
        // grouping 은 원래 순서를 유지하므로 월 안에서도 이미 최신순이다
        return grouped
            .map { (month: $0.key, records: $0.value) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        ScrollView {
            header
            LazyVGrid(columns: columns, spacing: spacing, pinnedViews: [.sectionHeaders]) {
                ForEach(monthGroups, id: \.month) { group in
                    Section {
                        ForEach(group.records) { record in
                            cell(record)
                        }
                    } header: {
                        monthHeader(group.month, count: group.records.count)
                    }
                }
            }
        }
    }

    // MARK: - 칸

    private func cell(_ record: MealRecord) -> some View {
        NavigationLink {
            PhotoDetailView(
                date: record.date,
                mealType: record.mealType,
                mealRecord: record,
                mealStore: mealStore,
                embedInNavigation: false
            )
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { thumbnail(record) }
                .overlay(alignment: .topLeading) { dateBadge(record.date) }   // 사진 왼쪽 아래에는 날짜 도장이 새겨져 있어 위에 둔다
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                mealStore.deleteMeal(date: record.date, mealType: record.mealType)
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isExercise
                            ? Text("\(accessibilityDateLabel(record.date)) 운동")
                            : Text(verbatim: "\(accessibilityDateLabel(record.date)), \(record.mealType.displayName)"))
        .accessibilityHint("두 번 탭하여 자세히 보기")
    }

    private var tint: Color { isExercise ? .green : .orange }

    @ViewBuilder
    private func thumbnail(_ record: MealRecord) -> some View {
        // 3열 칸 크기에 맞춰 작게 푼다 (큰 사진을 원본으로 여러 장 풀면 메모리가 치솟는다)
        let maxPixel = UIScreen.appWidth / 3 * 3
        if let data = record.thumbnailImageData {
            MealThumbnail(id: record.id, data: data, maxPixel: maxPixel) { tint.opacity(0.15) }
        } else {
            // 사진 없이 남긴 기록
            ZStack {
                (isExercise ? Color.green : record.mealType.symbolColor).opacity(0.15)
                Image(systemName: isExercise ? "figure.run" : record.mealType.symbolName)
                    .scaledFont(size: 30)
                    .foregroundColor(isExercise ? .green : record.mealType.symbolColor)
            }
        }
    }

    private func dateBadge(_ date: Date) -> some View {
        Text(dateLabel(date))
            .scaledFont(size: 12, weight: .semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .padding(5)
    }

    private func monthHeader(_ month: Date, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(monthLabel(month))
                .font(.headline)
            (isExercise ? Text("· \(count)회") : Text("· \(count)개"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemBackground))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - 라벨

    private func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "오늘", comment: "Date label: today") }
        if cal.isDateInYesterday(date) { return String(localized: "어제", comment: "Date label: yesterday") }
        return MealPhotoGridFormat.shortDate.string(from: date)
    }

    private func accessibilityDateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "오늘", comment: "Date label: today") }
        if cal.isDateInYesterday(date) { return String(localized: "어제", comment: "Date label: yesterday") }
        return MealPhotoGridFormat.longDate.string(from: date)
    }

    private func monthLabel(_ month: Date) -> String {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate(
            Calendar.current.isDate(month, equalTo: Date(), toGranularity: .year) ? "MMMM" : "yyyyMMMM")
        return fmt.string(from: month)
    }
}

/// 정렬 열쇠 (제네릭 화면 안에는 타입을 둘 수 없어 밖에 둔다)
private struct Keyed { let record: MealRecord; let day: Date; let time: Date }

/// 칸마다 날짜 라벨을 그리므로 포매터는 한 번만 만든다
private enum MealPhotoGridFormat {
    static let shortDate: DateFormatter = {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("MdE")
        return fmt
    }()
    static let longDate: DateFormatter = {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
        return fmt
    }()
}
