//
//  ExerciseGridView.swift
//  RoutineCamera
//
//  운동 앨범 메인 화면 — 인스타그램 피드처럼 3열 정사각형 격자.
//  운동은 끼니 구분이 없고 사진 한 장이 곧 기록이라, 한 화면에 최대한 많은 날을 보여준다.
//  (날짜별 한 줄 격자는 하루에 큰 사진 한 장, 순간 피드는 72pt 썸네일 목록이라 몇 날밖에 안 보였다)
//  칸마다 날짜를 얹어 사진만 훑어도 언제 운동했는지 읽힌다.
//

import SwiftUI

struct ExerciseGridView: View {
    @ObservedObject var mealStore: MealRecordStore

    @State private var recordingMealType: MealType?
    @State private var recordingPhotoType: MealPhotoView.PhotoType = .before

    private let spacing: CGFloat = 2
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3)
    }

    // 같은 날 안에서의 순서: 촬영 시각이 있으면 그것, 없으면 슬롯 대표 시각
    private func timeOfDay(_ r: MealRecord) -> Date {
        if let c = r.capturedAt { return c }
        let base = Calendar.current.startOfDay(for: r.date)
        return Calendar.current.date(byAdding: .hour, value: r.mealType.typicalHour, to: base) ?? base
    }

    /// 월별 묶음 (최신 월 먼저), 각 월 안에서도 최신순.
    /// 날짜는 기록이 속한 날(record.date)로 판단한다 — 지난 날 기록을 오늘 올려도 그날 칸에 들어가야 한다.
    private var monthGroups: [(month: Date, records: [MealRecord])] {
        let cal = Calendar.current
        let records = mealStore.records
            .filter { $0.isComplete }
            .sorted {
                let d0 = cal.startOfDay(for: $0.date), d1 = cal.startOfDay(for: $1.date)
                return d0 != d1 ? d0 > d1 : timeOfDay($0) > timeOfDay($1)
            }
        let grouped = Dictionary(grouping: records) {
            cal.date(from: cal.dateComponents([.year, .month], from: $0.date)) ?? $0.date
        }
        return grouped
            // grouping 은 원래 순서를 유지하므로 월 안에서도 이미 최신순이다
            .map { (month: $0.key, records: $0.value) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        let groups = monthGroups
        Group {
            if groups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: spacing, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups, id: \.month) { group in
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
        }
        // 기록 버튼은 하단 고정 (스크롤해도 항상 보임)
        .safeAreaInset(edge: .bottom) {
            recordButton
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .background(.bar)
        }
        .sheet(item: $recordingMealType) { mealType in
            CameraPickerView(
                date: Date(),
                mealType: mealType,
                mealStore: mealStore,
                selectedPhotoType: $recordingPhotoType
            )
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
                .overlay(alignment: .bottomLeading) { dateBadge(record.date) }
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
        .accessibilityLabel("\(accessibilityDateLabel(record.date)) 운동")
        .accessibilityHint("두 번 탭하여 자세히 보기")
    }

    @ViewBuilder
    private func thumbnail(_ record: MealRecord) -> some View {
        // 3열 칸 크기에 맞춰 작게 푼다 (큰 사진을 원본으로 여러 장 풀면 메모리가 치솟는다)
        let maxPixel = UIScreen.appWidth / 3 * 3
        if let data = record.thumbnailImageData,
           let img = MealImageResizer.downsampledImage(from: data, maxPixel: maxPixel) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
        } else {
            // 사진 없이 남긴 기록
            ZStack {
                Color.green.opacity(0.15)
                Image(systemName: "figure.run")
                    .font(.system(size: 30))
                    .foregroundColor(.green)
            }
        }
    }

    private func dateBadge(_ date: Date) -> some View {
        Text(dateLabel(date))
            .font(.system(size: 12, weight: .semibold))
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
            Text("· \(count)회")
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

    // MARK: - 기록하기 버튼

    private var recordButton: some View {
        Button {
            recordingPhotoType = .before
            recordingMealType = slotForNewRecord()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "figure.run")
                    .font(.system(size: 17, weight: .semibold))
                Text("운동 기록하기")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
            }
            .foregroundColor(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(Color.green)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("운동 기록하기")
        .accessibilityHint("두 번 탭하여 사진으로 기록")
    }

    /// 새 운동을 담을 오늘의 슬롯: 지금 시각의 슬롯, 이미 찼으면 그 뒤의 빈 슬롯.
    /// 운동은 끼니가 아니라서 같은 시간대에 두 번 해도 앞 기록을 덮으면 안 된다.
    private func slotForNewRecord() -> MealType {
        let today = mealStore.getMeals(for: Calendar.current.startOfDay(for: Date()))
        let candidate = MealType.inferred()
        guard today[candidate]?.isComplete == true else { return candidate }
        let byTime = MealType.allCases.sorted { $0.typicalHour < $1.typicalHour }
        let isEmpty: (MealType) -> Bool = { today[$0]?.isComplete != true }
        return byTime.first { $0.typicalHour > candidate.typicalHour && isEmpty($0) }
            ?? byTime.first(where: isEmpty)
            ?? candidate
    }

    // MARK: - 라벨

    private func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "오늘" }
        if cal.isDateInYesterday(date) { return "어제" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M.d (E)"
        return fmt.string(from: date)
    }

    private func accessibilityDateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "오늘" }
        if cal.isDateInYesterday(date) { return "어제" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M월 d일 EEEE"
        return fmt.string(from: date)
    }

    private func monthLabel(_ month: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = Calendar.current.isDate(month, equalTo: Date(), toGranularity: .year) ? "M월" : "yyyy년 M월"
        return fmt.string(from: month)
    }

    // MARK: - 빈 상태

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "figure.run.circle")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.5))
            VStack(spacing: 6) {
                Text("아직 운동 기록이 없어요")
                    .font(.title3.weight(.semibold))
                Text("운동한 날 사진 한 장이면 충분해요.\n모아 보면 꾸준함이 한눈에 보여요.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }
}
