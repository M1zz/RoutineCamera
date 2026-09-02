//
//  MomentsView.swift
//  RoutineCamera
//
//  "순간 컬렉션" 메인 화면 — 아침/점심/저녁 슬롯을 없애고, 남긴 기록만 시간순으로 쌓는
//  사진 일기 피드. 빈 칸이 존재하지 않아 "채워야 한다"는 완벽주의 압박이 원천 제거된다.
//  List 기반이라 스와이프 삭제 지원, 상세는 네비게이션 스택으로 push.
//

import SwiftUI
import Combine

struct MomentsView: View {
    @ObservedObject var mealStore: MealRecordStore
    @ObservedObject private var settingsManager = SettingsManager.shared
    @ObservedObject private var notificationManager = NotificationManager.shared

    // 기록(카메라) 시트
    @State private var recordingMealType: MealType?
    @State private var recordingPhotoType: MealPhotoView.PhotoType = .before

    // 고스트 셀이 시간이 지나면 스스로 사라지도록 주기적으로 현재 시각을 갱신한다
    @State private var now: Date = Date()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var isExercise: Bool { settingsManager.albumType == .exercise }

    // 고스트 셀이 떠 있는 구간: 식사 시각 1시간 전 ~ 2시간 후.
    // 지나가면 사라진다 — 기록 안 한 과거를 빈 칸으로 남겨 압박하지 않기 위함.
    private let ghostLeadTime: TimeInterval = -60 * 60
    private let ghostGraceTime: TimeInterval = 2 * 60 * 60

    /// 오늘 곧 다가오는(또는 진행 중인) 끼니. 이미 기록했거나 시간대가 아니면 nil.
    private var ghost: (mealType: MealType, at: Date)? {
        guard !isExercise else { return nil }   // 운동은 정해진 시각이 없다
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let recordedToday = Set(
            mealStore.records
                .filter { $0.isComplete && cal.isDate(sortValue($0), inSameDayAs: now) }
                .map(\.mealType)
        )

        let schedule: [(MealType, Date)] = [
            (.breakfast, notificationManager.breakfastTime),
            (.lunch, notificationManager.lunchTime),
            (.dinner, notificationManager.dinnerTime)
        ]

        // 창이 열려 있는 끼니 중 가장 이른 것 하나만 (한 번에 하나의 고스트)
        return schedule.compactMap { meal, time -> (MealType, Date)? in
            guard !recordedToday.contains(meal) else { return nil }
            let comps = cal.dateComponents([.hour, .minute], from: time)
            guard let at = cal.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: 0, of: today) else { return nil }
            let elapsed = now.timeIntervalSince(at)
            guard elapsed >= ghostLeadTime, elapsed <= ghostGraceTime else { return nil }
            return (meal, at)
        }
        .min { $0.1 < $1.1 }
        .map { (mealType: $0.0, at: $0.1) }
    }

    // 버튼에 "무엇으로 기록될지" 미리 표시 (운동, 또는 현재 시각 기준 끼니)
    private var recordButtonTitle: String {
        isExercise ? "운동 기록하기" : "\(MealType.inferred().rawValue) 기록하기"
    }

    // 정렬용 시각: 촬영 시각이 있으면 그것, 없으면 끼니 대표 시간으로 합성.
    // → 같은 날 안에서도 아침(아래) → 저녁(위) 순으로 시간 흐름대로 정렬된다.
    private func sortValue(_ r: MealRecord) -> Date {
        if let c = r.capturedAt { return c }
        let base = Calendar.current.startOfDay(for: r.date)
        let hour: Int
        switch r.mealType {
        case .breakfast: hour = 8
        case .snack1:    hour = 10
        case .lunch:     hour = 12
        case .snack2:    hour = 15
        case .dinner:    hour = 18
        case .snack3:    hour = 21
        }
        return Calendar.current.date(byAdding: .hour, value: hour, to: base) ?? base
    }

    // 최신순(위=최근, 아래=과거)
    private var moments: [MealRecord] {
        mealStore.records
            .filter { $0.isComplete }
            .sorted { sortValue($0) > sortValue($1) }
    }

    /// 피드 한 줄 — 남긴 기록, 또는 곧 다가올 끼니의 자리를 미리 잡아두는 고스트
    private enum FeedRow: Identifiable {
        case record(MealRecord)
        case ghost(MealType, Date)

        var id: String {
            switch self {
            case .record(let r): return r.id.uuidString
            case .ghost(let meal, _): return "ghost-\(meal.rawValue)"
            }
        }
    }

    // 일자별 그룹 (최신 날 먼저), 각 날 안에서도 최신순.
    // 오늘 그룹에는 고스트 셀을 "기록되면 생길 그 자리"에 끼워 넣는다.
    private var dayGroups: [(day: Date, rows: [FeedRow], recordCount: Int)] {
        let cal = Calendar.current
        var grouped = Dictionary(grouping: moments) { cal.startOfDay(for: sortValue($0)) }

        let today = cal.startOfDay(for: now)
        if ghost != nil, grouped[today] == nil { grouped[today] = [] }

        return grouped
            .map { day, records -> (day: Date, rows: [FeedRow], recordCount: Int) in
                var rows: [(sort: Date, row: FeedRow)] = records.map { (sortValue($0), .record($0)) }
                if let ghost, cal.isDate(day, inSameDayAs: today) {
                    rows.append((ghost.at, .ghost(ghost.mealType, ghost.at)))
                }
                return (day: day,
                        rows: rows.sorted { $0.sort > $1.sort }.map(\.row),
                        recordCount: records.count)
            }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        Group {
            if moments.isEmpty && ghost == nil {
                emptyState
            } else {
                List {
                    ForEach(dayGroups, id: \.day) { group in
                        Section {
                            ForEach(group.rows) { row in
                                switch row {
                                case .record(let record):
                                    NavigationLink {
                                        PhotoDetailView(
                                            date: record.date,
                                            mealType: record.mealType,
                                            mealRecord: record,
                                            mealStore: mealStore,
                                            embedInNavigation: false
                                        )
                                    } label: {
                                        momentRow(record)
                                    }
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            mealStore.deleteMeal(date: record.date, mealType: record.mealType)
                                        } label: {
                                            Label("삭제", systemImage: "trash")
                                        }
                                    }
                                case .ghost(let meal, let at):
                                    ghostRow(meal, at: at)
                                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                }
                            }
                        } header: {
                            dayHeader(group.day, count: group.recordCount)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .onReceive(clock) { now = $0 }
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

    // MARK: - 기록하기 버튼

    private var recordButton: some View {
        Button {
            recordingPhotoType = .before
            // 식단·운동 모두 "지금 시각"으로 슬롯을 정한다.
            // (운동을 늘 .breakfast에 넣던 탓에 저녁 운동도 아침 칸에 들어가고 하루 한 번만 기록됐다)
            recordingMealType = MealType.inferred()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isExercise ? "figure.run" : "camera.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text(recordButtonTitle)
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
            }
            .foregroundColor(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(isExercise ? Color.green : Color.blue)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recordButtonTitle)
        .accessibilityHint("두 번 탭하여 사진으로 기록")
    }

    // MARK: - 일자 헤더

    private func dayHeader(_ day: Date, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(dayLabel(day))
                .font(.headline)
                .foregroundColor(.primary)
                .textCase(nil)
            Text("· \(count)개")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .textCase(nil)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "오늘" }
        if cal.isDateInYesterday(day) { return "어제" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M월 d일 (E)"
        return fmt.string(from: day)
    }

    // MARK: - 순간 행 (NavigationLink label)

    private func momentRow(_ record: MealRecord) -> some View {
        HStack(spacing: 12) {
            thumbnail(record)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: isExercise ? "figure.run" : record.mealType.symbolName)
                        .font(.system(size: 13))
                        .foregroundColor(isExercise ? .green : record.mealType.symbolColor)
                    Text(isExercise ? "운동" : record.mealType.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    if let t = record.capturedAt {
                        Text(timeLabel(t))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    if isExercise {
                        // 운동은 음식 태그 대신 완료 표시
                        tag("완료", system: "checkmark.circle.fill", color: .green)
                    } else {
                        // 상태는 하나만 — 마감된 식사 / 다 먹음 / 어떤 사진이 비었는지 명시
                        // 식후 사진을 쓰지 않는 설정에서는 사진 한 장이 곧 마감이라 미마감 상태가 없다
                        if record.hasBeforeAfterComparison {
                            tag("식사 완료", system: "checkmark.circle.fill", color: .green)
                        } else if record.ateAll {
                            tag("다 먹음", system: "checkmark.circle.fill", color: .green)
                        } else if !SettingsManager.shared.useAfterPhoto {
                            tag("기록 완료", system: "checkmark.circle.fill", color: .green)
                        } else if record.isEatingInProgressToday {
                            // 식전만 찍힌 오늘 기록 — 무엇이 비었는지 그대로 말해준다
                            tag("식후 사진 기록 필요", system: "hourglass", color: .orange)
                        } else if record.needsRecordCompletion {
                            tag("식후 사진 기록 필요", system: "pencil.circle", color: .gray)
                        } else if record.needsBeforePhoto {
                            tag("식전 사진 기록 필요", system: "pencil.circle", color: .gray)
                        }
                    }
                    if let memo = record.memo, !memo.isEmpty {
                        tag("메모", system: "note.text", color: .orange)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    // MARK: - 고스트 셀 (곧 다가올 끼니의 자리)

    // 기록하면 셀이 생길 바로 그 자리에 미리 자리를 잡아둔다.
    // 실제 기록 행과 같은 레이아웃(썸네일 + 제목 + 시각)이라 기록되면 그대로 채워지는 느낌.
    private func ghostRow(_ meal: MealType, at: Date) -> some View {
        Button {
            recordingPhotoType = .before
            recordingMealType = meal
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundColor(meal.symbolColor.opacity(0.45))
                    .frame(width: 72, height: 72)
                    .overlay(
                        Image(systemName: "camera")
                            .font(.system(size: 22))
                            .foregroundColor(meal.symbolColor.opacity(0.5))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: meal.symbolName)
                            .font(.system(size: 13))
                            .foregroundColor(meal.symbolColor.opacity(0.6))
                        Text(meal.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                        Text(timeLabel(at))
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    Text(now < at ? "곧 \(meal.rawValue) 시간이에요" : "지금 남기면 여기에 들어가요")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(meal.rawValue), 아직 기록 전")
        .accessibilityHint("두 번 탭하여 지금 기록")
    }

    @ViewBuilder
    private func thumbnail(_ record: MealRecord) -> some View {
        let size: CGFloat = 72
        if let data = record.thumbnailImageData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemBackground))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: isExercise ? "figure.run" : (record.ateAll ? "checkmark.circle.fill" : record.mealType.symbolName))
                        .font(.system(size: 26))
                        .foregroundColor(isExercise ? .green : (record.ateAll ? .green : record.mealType.symbolColor.opacity(0.6)))
                )
        }
    }

    private func tag(_ text: String, system: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: system)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func timeLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "a h:mm"
        return fmt.string(from: date)
    }

    // MARK: - 빈 상태

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: isExercise ? "figure.run.circle" : "fork.knife.circle")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.5))
            VStack(spacing: 6) {
                Text("아직 기록이 없어요")
                    .font(.title3.weight(.semibold))
                Text(isExercise
                     ? "운동한 순간을 사진으로 툭 남겨보세요.\n채워야 할 칸은 없어요."
                     : "먹은 순간을 사진으로 툭 남겨보세요.\n채워야 할 칸은 없어요.")
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
