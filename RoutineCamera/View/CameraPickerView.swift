//
//  CameraPickerView.swift
//  RoutineCamera
//

import SwiftUI
import AVFoundation
import Photos

struct CameraPickerView: View {
    let date: Date
    let mealType: MealType
    @ObservedObject var mealStore: MealRecordStore
    @Binding var selectedPhotoType: MealPhotoView.PhotoType
    @Environment(\.dismiss) var dismiss

    @State private var selectedTab = 0 // 0: 카메라, 1: 사진앨범
    @State private var selectedImage: UIImage?
    @State private var localPhotoType: MealPhotoView.PhotoType

    init(date: Date, mealType: MealType, mealStore: MealRecordStore, selectedPhotoType: Binding<MealPhotoView.PhotoType>) {
        self.date = date
        self.mealType = mealType
        self.mealStore = mealStore
        self._selectedPhotoType = selectedPhotoType

        // 운동 모드일 때는 항상 before로 설정 (1장만 저장)
        if SettingsManager.shared.albumType == .exercise {
            self._localPhotoType = State(initialValue: .before)
            print("📸 [CameraPickerView] 운동 모드 - 사진 1장만 저장")
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

    var body: some View {
        VStack(spacing: 0) {
            // 상단 헤더 (ZStack으로 픽커를 정중앙에 고정)
            VStack(spacing: 0) {
                ZStack {
                    // 중앙: 식전/식후 선택 (식단 모드일 때만)
                    if SettingsManager.shared.albumType == .diet {
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

                // 사진 없이 기록 — 한 번 탭하면 바로 기록되고 닫힌다
                recordWithoutPhotoButton
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
                mealStore.addOrUpdateMeal(date: date, mealType: mealType, imageData: imageData, isBefore: localPhotoType == .before)

                // 식단 모드일 때 식전 사진만 자동으로 Vision 분석 실행
                if SettingsManager.shared.albumType == .diet && localPhotoType == .before {
                    autoAnalyzeFood(image: image, date: date, mealType: mealType)
                }

                // 식전만 남긴 "먹는 중" 상태면 잠시 후 "다 드셨어요?" 알림 예약 (앱 안 열고 원탭)
                if SettingsManager.shared.albumType == .diet, let saved = mealStore.getMeals(for: date)[mealType] {
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
    }

    // MARK: - 사진 없이 기록 버튼

    // 사진을 남기고 싶지 않은 순간을 위한 한 탭 기록. 토글 없이 바로 저장하고 닫는다.
    private var recordWithoutPhotoButton: some View {
        Button {
            mealStore.recordWithoutPhoto(date: date, mealType: mealType)
            // 사진 없이 마감했으므로 "다 드셨어요?" 리마인더는 필요 없다
            NotificationManager.shared.cancelAteAllReminder(date: date, mealType: mealType)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                Text("사진 없이 기록")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.systemGroupedBackground))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("사진 없이 기록")
        .accessibilityHint("두 번 탭하면 사진 없이 \(mealType.rawValue)을 기록하고 닫습니다")
    }

    // 자동 음식 분석 (무료 분석 우선, 소진 시 OpenAI 사용)
    private func autoAnalyzeFood(image: UIImage, date: Date, mealType: MealType) {
        // 자동 분석이 꺼져있으면 실행하지 않음
        guard SettingsManager.shared.autoFoodAnalysis else {
            print("ℹ️ [AutoAnalysis] 자동 분석 설정 꺼짐 - 건너뜀")
            return
        }

        // 무료 분석 횟수가 남아있으면 Vision Framework 사용 (무료)
        if SettingsManager.shared.freeAnalysisCount > 0 {
            print("✅ [AutoAnalysis] 무료 분석 사용 (잔여: \(SettingsManager.shared.freeAnalysisCount)회)")

            // 무료 횟수 차감
            SettingsManager.shared.freeAnalysisCount -= 1

            // Vision Framework로 분석
            autoAnalyzeWithVisionFramework(image: image, date: date, mealType: mealType)
            return
        }

        // 무료 횟수 소진 - OpenAI 사용 (코인 필요)
        print("ℹ️ [AutoAnalysis] 무료 분석 소진 - OpenAI 사용")

        // OpenAI가 설정되어 있는지 확인
        guard OpenAIFoodAnalyzer.shared.isConfigured else {
            print("❌ [AutoAnalysis] OpenAI 미설정, 무료 분석 소진 - 분석 건너뜀")
            return
        }

        // 코인 체크
        guard CoinManager.shared.hasEnoughCoins() else {
            print("❌ [AutoAnalysis] 코인 부족 - 분석 건너뜀")
            return
        }

        // OpenAI 분석 실행
        _Concurrency.Task {
            do {
                let result = try await OpenAIFoodAnalyzer.shared.analyzeFood(image: image)

                await MainActor.run {
                    // 분석 성공 - 코인 차감
                    if CoinManager.shared.consumeCoin() {
                        let visionData = VisionAnalysisData(
                            foodItems: [result.foodName] + result.ingredients,
                            extractedText: [],
                            confidence: 1.0,
                            analyzedDate: Date(),
                            isOpenAI: true,
                            description: result.description
                        )
                        self.mealStore.updateVisionAnalysis(date: date, mealType: mealType, analysis: visionData)
                        print("✅ OpenAI 자동 분석 완료: \(mealType.rawValue) - \(result.foodName) (코인 차감됨)")
                    }
                }
            } catch {
                print("❌ OpenAI 분석 실패: \(error)")
            }
        }
    }

    // Vision Framework로 자동 분석 (폴백)
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
