//
//  CameraPickerView.swift
//  RoutineCamera
//

import SwiftUI
import AVFoundation
import Photos
import RoutineCameraCore

struct CameraPickerView: View {
    // 새 기록이면 사용자가 날짜·끼니를 바꿀 수 있다 (처음 값은 누른 칸 또는 지금 시간대 끼니)
    @State private var date: Date
    @State private var mealType: MealType
    @ObservedObject var mealStore: MealRecordStore
    @Binding var selectedPhotoType: MealPhotoView.PhotoType
    @Environment(\.dismiss) var dismiss

    @State private var selectedTab = 0 // 0: 카메라, 1: 사진앨범
    @State private var selectedImage: UIImage?
    @State private var localPhotoType: MealPhotoView.PhotoType

    // "언제 먹었는지" — 제안값으로 채워 두고, 사용자가 고칠 수 있다 (점심을 깜빡하고 저녁에 남기는 경우)
    private let canEditTarget: Bool            // 새 식단 기록일 때만 (기존 기록에 사진을 더할 때는 그 기록에 붙는다)
    @State private var mealTime: Date          // 시·분만 쓰고 날짜는 date
    @State private var mealTimeEdited = false  // 직접 고쳤으면 날짜·끼니를 바꿔도 제안으로 덮지 않는다
    @State private var showingTargetEditor = false

    init(date: Date, mealType: MealType, mealStore: MealRecordStore, selectedPhotoType: Binding<MealPhotoView.PhotoType>) {
        self._date = State(initialValue: date)
        self._mealType = State(initialValue: mealType)
        self._mealTime = State(initialValue: mealType.suggestedCapturedAt(on: date))
        self.canEditTarget = SettingsManager.shared.albumType == .diet && mealStore.getMeals(for: date)[mealType] == nil
        self.mealStore = mealStore
        self._selectedPhotoType = selectedPhotoType

        // 운동 모드이거나 식후 사진을 쓰지 않을 때는 항상 before로 (1장만 저장)
        if SettingsManager.shared.albumType == .exercise {
            self._localPhotoType = State(initialValue: .before)
            print("📸 [CameraPickerView] 운동 모드 - 사진 1장만 저장")
        } else if !SettingsManager.shared.useAfterPhoto {
            self._localPhotoType = State(initialValue: .before)
            print("📸 [CameraPickerView] 식후 사진 사용 안 함 - 사진 1장만 저장")
        } else {
            // 식단 모드: 식전 사진이 이미 있으면 자동으로 식후 선택
            let meals = mealStore.getMeals(for: date)
            if let mealRecord = meals[mealType], mealRecord.beforeImageData != nil {
                self._localPhotoType = State(initialValue: .after)
                print("📸 [CameraPickerView] 식전 사진 존재 - 자동으로 식후 선택")
            } else {
                self._localPhotoType = State(initialValue: selectedPhotoType.wrappedValue)
                print("📸 [CameraPickerView] 식전 사진 없음 - 기본값(\(selectedPhotoType.wrappedValue)) 사용")
            }
        }
    }

    // 이 끼니에 이미 남긴 기록 (없으면 nil)
    private var existingRecord: MealRecord? {
        mealStore.getMeals(for: date)[mealType]
    }

    // 식전만 찍힌 끼니에서 식후를 찍으려는 중인지 — 이때는 식후 사진 없이 끝낼 수 있게 한다
    private var canFinishWithoutAfterPhoto: Bool {
        guard SettingsManager.shared.albumType == .diet,
              SettingsManager.shared.useAfterPhoto,
              localPhotoType == .after,
              let record = existingRecord else { return false }
        return record.beforeImageData != nil && record.afterImageData == nil && !record.ateAll
    }

    var body: some View {
        VStack(spacing: 0) {
            // 상단 헤더 (ZStack으로 픽커를 정중앙에 고정)
            VStack(spacing: 0) {
                ZStack {
                    // 중앙: 식전/식후 선택 (식단 모드 + 식후 사진 사용 시에만)
                    if SettingsManager.shared.albumType == .diet && SettingsManager.shared.useAfterPhoto {
                        Picker("", selection: $localPhotoType) {
                            Text("식전").tag(MealPhotoView.PhotoType.before)
                            Text("식후").tag(MealPhotoView.PhotoType.after)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                    }

                    HStack {
                        Button("취소") {
                            dismiss()
                        }
                        .font(.system(size: 17))

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 52)

                if canEditTarget {
                    recordTargetButton
                }

                // 사진 없이 끝내기 — 한 번 탭하면 바로 기록되고 닫힌다.
                // 이미 기록이 있는 끼니에서 "사진 없이 기록"은 아무 일도 하지 않으므로 보여주지 않는다.
                if canFinishWithoutAfterPhoto {
                    finishWithoutAfterPhotoButton
                } else if existingRecord == nil {
                    recordWithoutPhotoButton
                }
            }
            .background(Color(.systemBackground))

            // 사진 촬영/선택 모드
            TabView(selection: $selectedTab) {
                // 카메라 탭
                CustomCameraView(selectedImage: $selectedImage, isActive: selectedTab == 0)
                    .tag(0)

                // 사진앨범 탭
                ImagePicker(selectedImage: $selectedImage, sourceType: .photoLibrary)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // 하단 탭바
            HStack(spacing: 0) {
                Button(action: {
                    selectedTab = 0
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 24))
                        Text("카메라")
                            .font(.system(size: 12))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(selectedTab == 0 ? .blue : .gray)
                }

                Button(action: {
                    selectedTab = 1
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 24))
                        Text("사진앨범")
                            .font(.system(size: 12))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(selectedTab == 1 ? .blue : .gray)
                }
            }
            .background(Color(.systemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color(.separator)),
                alignment: .top
            )
        }
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: selectedImage) { oldValue, newValue in
            if let image = newValue, let imageData = image.jpegData(compressionQuality: 0.8) {
                mealStore.addOrUpdateMeal(date: date, mealType: mealType, imageData: imageData,
                                          isBefore: localPhotoType == .before, capturedAt: capturedAt)

                // 식단 모드일 때 식전 사진만 자동으로 Vision 분석 실행
                if SettingsManager.shared.albumType == .diet && localPhotoType == .before {
                    autoAnalyzeFood(image: image, date: date, mealType: mealType)
                }

                // 식전만 남긴 "먹는 중" 상태면 잠시 후 "다 드셨어요?" 알림 예약 (앱 안 열고 원탭)
                if SettingsManager.shared.albumType == .diet, SettingsManager.shared.useAfterPhoto,
                   let saved = mealStore.getMeals(for: date)[mealType] {
                    // 지난 날짜에 뒤늦게 남긴 기록에는 리마인더를 걸지 않는다
                    if saved.isEatingInProgressToday {
                        NotificationManager.shared.scheduleAteAllReminder(date: date, mealType: mealType)
                    } else {
                        NotificationManager.shared.cancelAteAllReminder(date: date, mealType: mealType)
                    }
                }

                dismiss()
            }
        }
        .onChange(of: localPhotoType) { oldValue, newValue in
            selectedPhotoType = newValue
        }
        .onChange(of: date) { _, _ in refreshSuggestedTime() }
        .onChange(of: mealType) { _, _ in refreshSuggestedTime() }
        .sheet(isPresented: $showingTargetEditor) {
            recordTargetEditor
        }
        #if DEBUG
        // UI 검증용: 환경변수로 "언제 먹었나요?" 편집 시트 자동 오픈 (OPEN_CAMERA_SHEET_FOR_TEST 와 함께)
        .onAppear {
            if canEditTarget, ProcessInfo.processInfo.environment["OPEN_RECORD_TARGET_FOR_TEST"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showingTargetEditor = true }
            }
        }
        #endif
    }

    // MARK: - 언제·어느 끼니로 남길지

    // 저장할 "먹은 시각" — 고른 날짜에 고른 시·분 (미래면 지금)
    private var capturedAt: Date {
        MealTimeSuggestion.combine(day: date, time: mealTime, now: Date())
    }

    private func refreshSuggestedTime() {
        guard !mealTimeEdited else { return }
        mealTime = mealType.suggestedCapturedAt(on: date)
    }

    // 그 날 이미 남긴 끼니 — 고를 수 없게 한다 (사진을 덮어쓰지 않도록)
    private func takenMeals(on day: Date) -> Set<MealType> {
        Set(mealStore.getMeals(for: day).filter { $0.value.isComplete }.keys)
    }

    private func mealName(_ type: MealType) -> String {
        type.displayName
    }

    private var dayText: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "오늘") }
        if cal.isDateInYesterday(date) { return String(localized: "어제") }
        return date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }

    private var targetSummary: String {
        "\(dayText) \(mealName(mealType)) · \(capturedAt.formatted(date: .omitted, time: .shortened))"
    }

    private var recordTargetButton: some View {
        Button {
            showingTargetEditor = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mealType.symbolName)
                    .foregroundColor(mealType.symbolColor)
                Text(targetSummary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
        .accessibilityLabel("\(targetSummary)에 기록")
        .accessibilityHint("두 번 탭하면 날짜, 끼니, 먹은 시각을 바꿀 수 있습니다")
    }

    private var recordTargetEditor: some View {
        let taken = takenMeals(on: date)
        let dayBinding = Binding<Date>(
            get: { date },
            set: { newDay in
                date = Calendar.current.startOfDay(for: newDay)
                // 고른 끼니가 그 날 이미 있으면 비어 있는 끼니로 옮긴다
                let takenThatDay = takenMeals(on: date)
                if takenThatDay.contains(mealType),
                   let free = ([mealType] + MealType.allCases).first(where: { !takenThatDay.contains($0) }) {
                    mealType = free
                }
            }
        )
        let timeBinding = Binding<Date>(
            get: { mealTime },
            set: { mealTime = $0; mealTimeEdited = true }
        )
        let snackSlot = [mealType].filter(\.isSnack) + [MealType.snack1, .snack2, .snack3]
        let freeSnack = snackSlot.first { !taken.contains($0) }

        return NavigationStack {
            Form {
                Section {
                    DatePicker("날짜", selection: dayBinding, in: ...Date(), displayedComponents: .date)
                }

                Section("끼니") {
                    HStack(spacing: 8) {
                        ForEach([MealType.breakfast, .lunch, .dinner], id: \.self) { type in
                            mealChoice(type, title: mealName(type), selected: mealType == type,
                                       target: taken.contains(type) ? nil : type)
                        }
                        mealChoice(.snack1, title: mealName(.snack1), selected: mealType.isSnack, target: freeSnack)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    DatePicker("먹은 시각", selection: timeBinding, displayedComponents: .hourAndMinute)
                } footer: {
                    Text("바꾸지 않으면 끼니 시간으로 남아요")
                }
            }
            .navigationTitle("언제 먹었나요?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { showingTargetEditor = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // target 이 nil 이면 그 날 이미 남긴 끼니 — 누를 수 없고 "기록됨" 으로 보인다
    private func mealChoice(_ type: MealType, title: String, selected: Bool, target: MealType?) -> some View {
        Button {
            if let target { mealType = target }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: type.symbolName)
                    .font(.system(size: 20))
                    .foregroundColor(target == nil && !selected ? .secondary : type.symbolColor)
                Text(title)
                    .font(.system(size: 14, weight: selected ? .bold : .regular))
                if target == nil && !selected {
                    Text("기록됨")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? type.symbolColor.opacity(0.18) : Color(.tertiarySystemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? type.symbolColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(target == nil && !selected)
        .accessibilityLabel(target == nil && !selected ? "\(title), 이미 기록됨" : title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - 사진 없이 끝내기 버튼

    // 사진을 남기고 싶지 않은 순간을 위한 한 탭 기록. 토글 없이 바로 저장하고 닫는다.
    private var recordWithoutPhotoButton: some View {
        Button {
            mealStore.recordWithoutPhoto(date: date, mealType: mealType, capturedAt: capturedAt)
            // 사진 없이 마감했으므로 "다 드셨어요?" 리마인더는 필요 없다
            NotificationManager.shared.cancelAteAllReminder(date: date, mealType: mealType)
            dismiss()
        } label: {
            headerActionLabel("사진 없이 기록", systemImage: "square.and.pencil")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("사진 없이 기록")
        .accessibilityHint("두 번 탭하면 사진 없이 \(mealType.displayName)을 기록하고 닫습니다")
    }

    // 식전 사진은 남겼고 식후는 찍고 싶지 않을 때 — "다 먹음"으로 이 식사를 마친다
    private var finishWithoutAfterPhotoButton: some View {
        Button {
            mealStore.recordAteAll(date: date, mealType: mealType)
            NotificationManager.shared.cancelAteAllReminder(date: date, mealType: mealType)
            dismiss()
        } label: {
            headerActionLabel("식후 사진 없이 마치기", systemImage: "checkmark.circle")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("식후 사진 없이 마치기")
        .accessibilityHint("두 번 탭하면 식후 사진 없이 \(mealType.displayName)을 다 먹음으로 기록하고 닫습니다")
    }

    private func headerActionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
        }
        .foregroundColor(.blue)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemGroupedBackground))
    }

    // 자동 음식 분석 — 기기 안(Vision)에서 무료로
    private func autoAnalyzeFood(image: UIImage, date: Date, mealType: MealType) {
        guard SettingsManager.shared.autoFoodAnalysis else {
            print("ℹ️ [AutoAnalysis] 자동 분석 설정 꺼짐 - 건너뜀")
            return
        }
        autoAnalyzeWithVisionFramework(image: image, date: date, mealType: mealType)
    }

    // Vision Framework로 자동 분석
    private func autoAnalyzeWithVisionFramework(image: UIImage, date: Date, mealType: MealType) {
        VisionAnalyzer.shared.analyzeFoodImage(image) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let analysis):
                    let visionData = VisionAnalysisData(
                        foodItems: analysis.foodItems,
                        extractedText: analysis.extractedText,
                        confidence: analysis.confidence,
                        analyzedDate: Date(),
                        isOpenAI: false,
                        description: nil
                    )
                    self.mealStore.updateVisionAnalysis(date: date, mealType: mealType, analysis: visionData)
                    print("✅ Vision 자동 분석 완료: \(mealType.rawValue)")
                case .failure(let error):
                    print("❌ 자동 분석 실패: \(error)")
                }
            }
        }
    }
}

// 사진 상세보기 화면
