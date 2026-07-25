//
//  MomentsView.swift
//  RoutineCamera
//
//  "순간 컬렉션" 메인 화면 — 아침/점심/저녁 슬롯을 없애고, 남긴 기록만 시간순으로 쌓는
//  사진 일기 피드. 빈 칸이 존재하지 않아 "채워야 한다"는 완벽주의 압박이 원천 제거된다.
//  기록/상세 인프라(CameraPickerView·PhotoDetailView)는 그대로 재사용.
//

import SwiftUI

struct MomentsView: View {
    @ObservedObject var mealStore: MealRecordStore
    @ObservedObject private var settingsManager = SettingsManager.shared

    // 기록(카메라) 시트
    @State private var recordingMealType: MealType?
    @State private var recordingPhotoType: MealPhotoView.PhotoType = .before
    // 상세 시트
    @State private var detailRecord: MealRecord?

    // 현재 앨범의 완료된 기록을 최신순으로
    private var moments: [MealRecord] {
        mealStore.records
            .filter { $0.isComplete }
            .sorted { $0.sortDate > $1.sortDate }
    }

    // 일자별 그룹 (최신 날 먼저)
    private var dayGroups: [(day: Date, records: [MealRecord])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: moments) { cal.startOfDay(for: $0.sortDate) }
        return grouped
            .map { (day: $0.key, records: $0.value.sorted { $0.sortDate > $1.sortDate }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        Group {
            if moments.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        recordButton
                            .padding(.top, 8)

                        ForEach(dayGroups, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                dayHeader(group.day, count: group.records.count)
                                ForEach(group.records) { record in
                                    momentCard(record)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .sheet(item: $recordingMealType) { mealType in
            CameraPickerView(
                date: Date(),
                mealType: mealType,
                mealStore: mealStore,
                selectedPhotoType: $recordingPhotoType
            )
        }
        .sheet(item: $detailRecord) { record in
            PhotoDetailView(
                date: record.date,
                mealType: record.mealType,
                mealRecord: record,
                mealStore: mealStore
            )
        }
    }

    // MARK: - 기록하기 버튼

    private var recordButton: some View {
        Button {
            recordingPhotoType = .before
            recordingMealType = MealType.inferred()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text("지금 기록하기")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
            }
            .foregroundColor(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(Color.blue)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("지금 기록하기")
        .accessibilityHint("두 번 탭하여 사진으로 기록")
    }

    // MARK: - 일자 헤더

    private func dayHeader(_ day: Date, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(dayLabel(day))
                .font(.headline)
                .foregroundColor(.primary)
            Text("· \(count)개")
                .font(.subheadline)
                .foregroundColor(.secondary)
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

    // MARK: - 순간 카드

    private func momentCard(_ record: MealRecord) -> some View {
        Button {
            detailRecord = record
        } label: {
            HStack(spacing: 12) {
                thumbnail(record)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: record.mealType.symbolName)
                            .font(.system(size: 13))
                            .foregroundColor(record.mealType.symbolColor)
                        Text(record.mealType.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        if let t = record.capturedAt {
                            Text(timeLabel(t))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // 상태 태그들
                    HStack(spacing: 6) {
                        if record.hasBeforeAfterComparison {
                            tag("식전·식후 비교", system: "rectangle.on.rectangle", color: .blue)
                        }
                        if record.ateAll {
                            tag("다 먹음", system: "checkmark.circle.fill", color: .green)
                        }
                        if let memo = record.memo, !memo.isEmpty {
                            tag("메모", system: "note.text", color: .orange)
                        }
                    }

                    // "먹는 중"이면 앱 안에서 바로 다 먹음 처리 (위젯 없이도)
                    if record.isEatingInProgress {
                        ateAllQuickButton(record)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.mealType.rawValue) 기록\(record.ateAll ? ", 다 먹음" : "")")
        .accessibilityHint("두 번 탭하여 상세 보기")
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
                    Image(systemName: record.ateAll ? "checkmark.circle.fill" : record.mealType.symbolName)
                        .font(.system(size: 26))
                        .foregroundColor(record.ateAll ? .green : record.mealType.symbolColor.opacity(0.6))
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

    private func ateAllQuickButton(_ record: MealRecord) -> some View {
        Button {
            mealStore.recordAteAll(date: record.date, mealType: record.mealType)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                Text("다 먹음")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay(Capsule().stroke(Color.green.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("다 먹음으로 표시")
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
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.5))
            VStack(spacing: 6) {
                Text("아직 기록이 없어요")
                    .font(.title3.weight(.semibold))
                Text("먹은 순간을 사진으로 툭 남겨보세요.\n채워야 할 칸은 없어요.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            recordButton
                .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }
}
