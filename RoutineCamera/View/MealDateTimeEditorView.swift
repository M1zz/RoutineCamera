//
//  MealDateTimeEditorView.swift
//  RoutineCamera
//
//  이미 남긴 기록의 날짜 · 시각을 바꾸는 시트 (사진 상세 > 더 보기 > 날짜·시간 바꾸기).
//  사용자 피드백 "기록 날짜 · 시간을 글꼴 포함해 편집하고 싶다" (2026-11-09).
//  카메라로 찍어 도장 아래 원본 띠가 남은 사진은 새 날짜 · 고른 글꼴로 사진의 도장도 다시 새긴다.
//  예전 버전에서 찍었거나 앨범에서 고른 사진은 띠가 없어 기록의 날짜 · 시각만 바뀐다 — 화면에 그렇게 알린다.
//

import SwiftUI
import RoutineCameraCore

struct MealDateTimeEditorView: View {
    @ObservedObject var mealStore: MealRecordStore
    let record: MealRecord
    /// 저장을 마쳤을 때. 다른 날로 옮겼으면 true (상세 화면은 날짜로 기록을 찾으므로 닫아야 한다)
    var onSaved: (_ movedToOtherDay: Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var day: Date
    @State private var time: Date
    @State private var restampPhotos = true
    // 도장 모양은 여기서 고친 값을 저장할 때 설정에도 되돌려 쓴다 (새로 찍는 사진에도 같은 글꼴)
    @State private var stampEnabled: Bool
    @State private var stampFont: MealStampFont
    @State private var stampShowsTime: Bool
    @State private var isSaving = false
    @State private var showingSlotTaken = false
    @State private var preview: UIImage?

    init(mealStore: MealRecordStore, record: MealRecord, onSaved: @escaping (_ movedToOtherDay: Bool) -> Void) {
        self.mealStore = mealStore
        self.record = record
        self.onSaved = onSaved
        _day = State(initialValue: record.date)
        _time = State(initialValue: record.capturedAt ?? record.feedDate)
        let style = MealStampStyle.current
        _stampEnabled = State(initialValue: style.isEnabled)
        _stampFont = State(initialValue: style.font)
        _stampShowsTime = State(initialValue: style.showsTime)
    }

    private var isDiet: Bool { SettingsManager.shared.albumType == .diet }

    /// 저장할 시각 — 고른 날짜에 고른 시·분 (미래면 지금)
    private var newCapturedAt: Date {
        MealTimeSuggestion.combine(day: day, time: time, now: Date())
    }

    private var style: MealStampStyle {
        MealStampStyle(isEnabled: stampEnabled, font: stampFont, showsTime: stampShowsTime)
    }

    private var canRestampBefore: Bool { mealStore.canRestampPhoto(record, isBefore: true) }
    private var canRestampAfter: Bool { mealStore.canRestampPhoto(record, isBefore: false) }
    private var canRestamp: Bool { canRestampBefore || canRestampAfter }
    private var hasPhoto: Bool { record.beforeImageData != nil || record.afterImageData != nil }

    private var previewKey: String {
        "\(newCapturedAt.timeIntervalSince1970)-\(stampEnabled)-\(stampFont.rawValue)-\(stampShowsTime)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("날짜", selection: $day, in: ...Date(), displayedComponents: .date)
                    if isDiet {
                        DatePicker("먹은 시각", selection: $time, displayedComponents: .hourAndMinute)
                    } else {
                        DatePicker("시각", selection: $time, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    if !Calendar.current.isDate(day, inSameDayAs: record.date) {
                        Text("다른 날로 옮기면 그날 \(record.mealType.displayName) 칸으로 들어가요.",
                             comment: "Footer under the date picker when a meal record is being moved to another day; %@ is the meal name")
                    }
                }

                if canRestamp {
                    Section {
                        Toggle("사진에 새긴 날짜도 바꾸기", isOn: $restampPhotos)
                        if restampPhotos {
                            Toggle("사진에 날짜 새기기", isOn: $stampEnabled)
                            if stampEnabled {
                                Picker("글꼴", selection: $stampFont) {
                                    ForEach(MealStampFont.allCases) { font in
                                        Text(font.displayName).font(font.font(size: 17)).tag(font)
                                    }
                                }
                                Toggle("시간도 함께 새기기", isOn: $stampShowsTime)
                            }
                            previewRow
                        }
                    } header: {
                        Text("사진의 날짜 도장")
                    } footer: {
                        Text("여기서 고른 글꼴과 표시 방식은 새로 찍는 사진에도 쓰여요.")
                    }
                } else if hasPhoto {
                    Section {
                        Text("이 사진은 예전에 찍어 사진에 새긴 글자는 그대로예요. 기록의 날짜와 시각만 바뀌어요.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle(Text("날짜·시간 바꾸기"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", systemImage: "xmark") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", systemImage: "checkmark") { save() }
                        .disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .alert(Text("그날 \(record.mealType.displayName) 기록이 이미 있어요",
                        comment: "Alert title when a meal cannot be moved because that day already has a record for the same meal; %@ is the meal name"),
                   isPresented: $showingSlotTaken) {
                Button("확인", role: .cancel) { }
            } message: {
                Text("그 기록을 지우거나 다른 날을 골라 주세요.")
            }
        }
        .presentationDetents([.medium, .large])
        #if DEBUG
        // 시뮬레이터 검증용 (GUI 없이): AUTO_EDIT_FOR_TEST=day 면 하루 앞으로, time 이면 밤 11:45 로 바꾸고 둥근 글꼴로 저장한다
        .onAppear {
            guard let mode = ProcessInfo.processInfo.environment["AUTO_EDIT_FOR_TEST"] else { return }
            if mode == "day" { day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day }
            if mode == "time" { time = Calendar.current.date(bySettingHour: 23, minute: 45, second: 0, of: day) ?? time }
            stampFont = .rounded
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { save() }
        }
        #endif
    }

    // MARK: - 미리보기

    /// 실제 사진(줄인 것)에 띠를 덮고 새 날짜로 새겨 본다 — 저장하면 이렇게 된다
    @ViewBuilder private var previewRow: some View {
        ZStack {
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color(.secondarySystemBackground)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(ProgressView())
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 260)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .accessibilityLabel(Text("미리보기"))
        .task(id: previewKey) { await loadPreview() }
    }

    private func loadPreview() async {
        // 다시 새길 수 있는 사진 중 하나 (식전 우선)
        let photo = canRestampBefore ? record.beforeImageData : record.afterImageData
        let backing = MealStampBackingStore.shared.load(for: record.id, kind: canRestampBefore ? "before" : "after")
        guard let photo, let backing else { return }
        let (date, style) = (newCapturedAt, style)
        let rendered = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let image = MealImageResizer.downsampledImage(from: photo, maxPixel: 720),
                  let band = MealImageResizer.downsampledImage(from: backing, maxPixel: 720) else { return nil }
            return MealPhotoStamp.restamp(stamped: image, backing: band, date: date, style: style)
        }.value
        guard !Task.isCancelled else { return }
        preview = rendered
    }

    // MARK: - 저장

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        let restampStyle: MealStampStyle? = (canRestamp && restampPhotos) ? style : nil
        let originalDay = record.date
        Task { @MainActor in
            let result = await mealStore.rescheduleMeal(date: record.date, mealType: record.mealType,
                                                        to: newCapturedAt, restampStyle: restampStyle)
            isSaving = false
            switch result {
            case .moved(let newDay, _):
                if let restampStyle {
                    // 다음에 찍는 사진도 같은 모양으로
                    let settings = SettingsManager.shared
                    settings.photoStampEnabled = restampStyle.isEnabled
                    settings.photoStampFont = restampStyle.font
                    settings.photoStampShowsTime = restampStyle.showsTime
                }
                let movedToOtherDay = !Calendar.current.isDate(newDay, inSameDayAs: originalDay)
                dismiss()
                onSaved(movedToOtherDay)
            case .slotTaken:
                showingSlotTaken = true
            case .notFound:
                dismiss()
            }
        }
    }
}
