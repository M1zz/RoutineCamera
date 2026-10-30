//
//  PhotoDetailView.swift
//  RoutineCamera
//

import SwiftUI
import LeeoKit
import RoutineCameraCore
import AVFoundation
import Photos

struct PhotoDetailView: View {
    let date: Date
    let mealType: MealType
    let mealRecord: MealRecord?
    @ObservedObject var mealStore: MealRecordStore
    @Environment(\.foldLayout) private var fold
    // 모달(sheet)로 열 땐 자체 NavigationView로 감싸고, 네비게이션 스택에 push할 땐 감싸지 않는다.
    var embedInNavigation: Bool = true
    @Environment(\.dismiss) var dismiss

    @State private var currentPage = 0 // 0: 식전, 1: 식후
    @State private var showingMemoEditor = false
    @State private var showingDeleteAlert = false
    @State private var showingAddPhotoSheet = false
    @State private var selectedPhotoType: MealPhotoView.PhotoType = .before
    @State private var showingSaveSuccessAlert = false
    @State private var showingSaveErrorAlert = false
    @State private var analyzingFood = false // 식단 분석 중
    @State private var analysisResult: FoodAnalysisResult? = nil // 분석 결과
    @State private var showingAnalysisResult = false // 결과 표시
    @State private var showFullAnalysis = false // 전체 분석 보기
    @State private var feedbacks: [MealFeedback] = [] // 받은 피드백 목록
    @State private var isLoadingFeedbacks = false // 피드백 로딩 중

    // 화면에 그릴 때 푸는 사진의 긴 변 (예전에 저장된 48MP 사진을 원본 크기로 풀면 한 장에 수백 MB)
    static let displayMaxPixel: CGFloat = 1600

    // "식후 사진 없이 마치기"처럼 이 화면에서 기록을 바꾸면 바로 보이도록, 넘겨받은 값보다 저장소의 최신 기록을 우선한다
    private var currentRecord: MealRecord? {
        mealStore.getMeals(for: date)[mealType] ?? mealRecord
    }

    @ViewBuilder
    private var detailBody: some View {
          // 메모·음식 태그·응원이 길어도 아래가 잘리지 않게 전체를 스크롤한다
          ScrollView {
            VStack(spacing: 0) {
                if let record = currentRecord {
                    // 사진 영역 — 정사각형 높이로 고정 (아래 정보가 많아도 사진이 찌그러지지 않게)
                    Group {
                    if SettingsManager.shared.albumType == .exercise {
                        // 운동 모드: 사진 1장만 표시
                        if let beforeData = record.beforeImageData, let beforeImage = MealImageResizer.downsampledImage(from: beforeData, maxPixel: Self.displayMaxPixel) {
                            Image(uiImage: beforeImage)
                                .resizable()
                                .scaledToFit()
                                .accessibilityLabel("\(mealType.displayName) 기록 사진")
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "photo")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
                                    .accessibilityHidden(true)
                                Text("사진 없음")
                                    .scaledFont(size: 18)
                                    .foregroundColor(.secondary)
                                Text("탭하여 사진 추가")
                                    .scaledFont(size: 14)
                                    .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemGray6))
                            .addPhotoTap {
                                selectedPhotoType = .before
                                showingAddPhotoSheet = true
                            }
                        }
                    } else if !SettingsManager.shared.useAfterPhoto {
                        // 식후 사진을 쓰지 않는 설정: 식전 한 장만 보여준다
                        if let beforeData = record.beforeImageData, let beforeImage = MealImageResizer.downsampledImage(from: beforeData, maxPixel: Self.displayMaxPixel) {
                            Image(uiImage: beforeImage)
                                .resizable()
                                .scaledToFit()
                                .accessibilityLabel("\(mealType.displayName) 기록 사진")
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "photo")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
                                    .accessibilityHidden(true)
                                Text("사진 없음")
                                    .scaledFont(size: 18)
                                    .foregroundColor(.secondary)
                                Text("탭하여 사진 추가")
                                    .scaledFont(size: 14)
                                    .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemGray6))
                            .addPhotoTap {
                                selectedPhotoType = .before
                                showingAddPhotoSheet = true
                            }
                        }
                    } else {
                        // 식단 모드: 식전/식후 TabView
                        TabView(selection: $currentPage) {
                            // 식전 사진
                            if let beforeData = record.beforeImageData, let beforeImage = MealImageResizer.downsampledImage(from: beforeData, maxPixel: Self.displayMaxPixel) {
                                Image(uiImage: beforeImage)
                                    .resizable()
                                    .scaledToFit()
                                    .tag(0)
                                    .accessibilityLabel("식전 사진")
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 60))
                                        .foregroundColor(.gray)
                                        .accessibilityHidden(true)
                                    Text("식전 사진 없음")
                                        .scaledFont(size: 18)
                                        .foregroundColor(.secondary)
                                    Text("탭하여 사진 추가")
                                        .scaledFont(size: 14)
                                        .foregroundColor(.blue)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(.systemGray6))
                                .tag(0)
                                .addPhotoTap {
                                    selectedPhotoType = .before
                                    showingAddPhotoSheet = true
                                }
                            }

                            // 식후 사진
                            if let afterData = record.afterImageData, let afterImage = MealImageResizer.downsampledImage(from: afterData, maxPixel: Self.displayMaxPixel) {
                                Image(uiImage: afterImage)
                                    .resizable()
                                    .scaledToFit()
                                    .tag(1)
                                    .accessibilityLabel("식후 사진")
                            } else if record.ateAll {
                                // 식후 사진 없이 "다 먹음"으로 마친 식사 — 비어 있다고 재촉하지 않는다
                                VStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 60))
                                        .foregroundColor(.green)
                                        .accessibilityHidden(true)
                                    Text("식후 사진 없이 마쳤어요")
                                        .scaledFont(size: 18)
                                        .foregroundColor(.secondary)
                                    Text("탭하여 식후 사진 추가")
                                        .scaledFont(size: 14)
                                        .foregroundColor(.blue)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(.systemGray6))
                                .tag(1)
                                .addPhotoTap {
                                    selectedPhotoType = .after
                                    showingAddPhotoSheet = true
                                }
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 60))
                                        .foregroundColor(.gray)
                                        .accessibilityHidden(true)
                                    Text("식후 사진 없음")
                                        .scaledFont(size: 18)
                                        .foregroundColor(.secondary)
                                    Text("탭하여 사진 추가")
                                        .scaledFont(size: 14)
                                        .foregroundColor(.blue)

                                    // 식후는 찍지 않고 이 식사를 마치고 싶을 때
                                    if record.beforeImageData != nil {
                                        Button(action: finishWithoutAfterPhoto) {
                                            Label("식후 사진 없이 마치기", systemImage: "checkmark.circle")
                                                .scaledFont(size: 15, weight: .semibold)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 10)
                                                .background(Capsule().fill(Color(.systemBackground)))
                                        }
                                        .padding(.top, 8)
                                        // 칸 전체가 '사진 추가' 버튼으로 읽히므로, 이 버튼은 그 칸의 동작으로 옮긴다
                                        .accessibilityHidden(true)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(.systemGray6))
                                .tag(1)
                                .addPhotoTap {
                                    selectedPhotoType = .after
                                    showingAddPhotoSheet = true
                                }
                                .accessibilityActions {
                                    if record.beforeImageData != nil {
                                        Button("식후 사진 없이 마치기", action: finishWithoutAfterPhoto)
                                    }
                                }
                            }
                        }
                        .tabViewStyle(.page)
                        .indexViewStyle(.page(backgroundDisplayMode: .always))
                    }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: fold.appWidth)

                    // 정보 영역
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            // 운동 모드에서는 저장 슬롯(아침/점심/…) 대신 "운동"으로 표시
                            let isExercise = SettingsManager.shared.albumType == .exercise
                            Image(systemName: isExercise ? "figure.run" : mealType.symbolName)
                                .foregroundColor(isExercise ? .green : mealType.symbolColor)
                                .scaledFont(size: 24)
                            Text(isExercise ? String(localized: "slot.workout", defaultValue: "운동", comment: "Slot label in workout mode") : mealType.displayName)
                                .scaledFont(size: 24, weight: .bold)
                                .lineLimit(1)
                            // 식단 모드 + 식후 사진을 쓸 때만 식전/식후 표시
                            if !isExercise && SettingsManager.shared.useAfterPhoto {
                                Text(currentPage == 0 ? "식전" : "식후")
                                    .scaledFont(size: 18, weight: .medium)
                                    .foregroundColor(.secondary)
                            }
                            Spacer(minLength: 8)

                            // 실제 기록 시각 (잘리지 않게 고정 폭)
                            if let captured = record.capturedAt {
                                Text(timeFormatter.string(from: captured))
                                    .scaledFont(size: 15, weight: .medium)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }

                        if let memo = record.memo, !memo.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("메모")
                                    .scaledFont(size: 14, weight: .semibold)
                                    .foregroundColor(.secondary)
                                Text(memo)
                                    .scaledFont(size: 16)
                            }
                        }

                        // Vision 분석 결과 표시 (식단 모드일 때만)
                        if SettingsManager.shared.albumType == .diet {
                            if let analysis = record.visionAnalysis {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("식단 분석")
                                            .scaledFont(size: 14, weight: .semibold)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        // 다시 분석하기 버튼 (식전 사진만 — 기기 안에서 무료로 분석)
                                        if currentPage == 0 {
                                            Button(action: {
                                                analyzeFoodWithVision()
                                            }) {
                                                HStack(spacing: 4) {
                                                    if analyzingFood {
                                                        ProgressView()
                                                            .scaleEffect(0.7)
                                                    } else {
                                                        Image(systemName: "arrow.clockwise")
                                                            .scaledFont(size: 12)
                                                    }
                                                    Text(analyzingFood ? "분석 중" : "다시 분석")
                                                        .scaledFont(size: 13)
                                                }
                                                .foregroundColor(.blue)
                                            }
                                            .disabled(analyzingFood)
                                        }
                                        // 식후 사진은 분석하지 않는다
                                        if currentPage == 1 {
                                            Text("(식후 사진)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    // 음식 태그 표시
                                    if !analysis.foodItems.isEmpty {
                                        FoodTagsView(
                                            foodItems: analysis.foodItems,
                                            description: analysis.description,
                                            showFullAnalysis: $showFullAnalysis
                                        )
                                    }
                                }
                            } else if (record.beforeImageData != nil || record.afterImageData != nil) && currentPage == 0 {
                                // 식전 사진만 분석 가능
                                let buttonText: LocalizedStringKey = analyzingFood ? "분석 중..." : "식단 분석하기"

                                Button(action: {
                                    analyzeFoodWithVision()
                                }) {
                                    HStack {
                                        if analyzingFood {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "sparkles")
                                        }
                                        Text(buttonText)
                                    }
                                    .scaledFont(size: 16)
                                    .foregroundColor(.blue)
                                }
                                .disabled(analyzingFood)
                            } else if currentPage == 1 {
                                // 식후 사진 안내
                                Text("식후 사진은 분석할 수 없습니다")
                                    .scaledFont(size: 14)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                            }
                        }

                        // 식단 모드이고 사진이 1장만 있을 때 토글 표시 (식후를 쓸 때만 의미가 있다)
                        if SettingsManager.shared.albumType == .diet && SettingsManager.shared.useAfterPhoto {
                            let photoCount = (record.beforeImageData != nil ? 1 : 0) + (record.afterImageData != nil ? 1 : 0)
                            // "다 먹음"으로 마친 식사엔 알림 뱃지 자체가 없으므로 토글도 필요 없다
                            if photoCount == 1 && !record.ateAll {
                                Divider()
                                    .padding(.vertical, 8)

                                Toggle("식전/식후 사진 알림 가리기", isOn: Binding(
                                    get: { record.hidePhotoCountBadge },
                                    set: { newValue in
                                        mealStore.updateHidePhotoCountBadge(date: date, mealType: mealType, hide: newValue)
                                    }
                                ))
                                .scaledFont(size: 16)

                                Text("이 식사의 빨간색 1 알림을 표시하지 않습니다.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // 피드백 섹션
                        Divider()
                            .padding(.vertical, 8)

                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("피드백")
                                    .scaledFont(size: 14, weight: .semibold)
                                    .foregroundColor(.secondary)
                                Spacer()
                                if isLoadingFeedbacks {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                            }

                            // 이 끼니에 달린 응원 전부 — 이모지 반응은 위에 모이고 글은 시간순으로 쌓인다
                            FeedbackThreadView(
                                feedbacks: feedbacks,
                                myUserId: FriendManager.shared.myUserId,
                                isLoading: isLoadingFeedbacks,
                                emptyText: String(localized: "아직 받은 응원이 없습니다", comment: "Empty state: no cheers received yet")
                            )
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                }
            }
          }
            .navigationTitle(dateFormatter.string(from: date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if embedInNavigation {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("닫기", systemImage: "xmark") {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        // 식단 분석 버튼 (식단 모드 + 식전 사진만)
                        if SettingsManager.shared.albumType == .diet && currentPage == 0 {
                            Button(action: {
                                analyzeFoodWithVision()
                            }) {
                                Label(analyzingFood ? "분석 중..." : "식단 분석", systemImage: "sparkles")
                            }
                            .disabled(analyzingFood)
                        }

                        Button(action: {
                            saveCurrentPhotoToAlbum()
                        }) {
                            Label("사진앱에 저장", systemImage: "arrow.down.circle")
                        }

                        Button(action: {
                            selectedPhotoType = currentPage == 0 ? .before : .after
                            showingAddPhotoSheet = true
                        }) {
                            Label("사진 추가/교체", systemImage: "photo.badge.plus")
                        }

                        Button(action: {
                            showingMemoEditor = true
                        }) {
                            Label("메모 작성", systemImage: "note.text")
                        }

                        Button(role: .destructive, action: {
                            showingDeleteAlert = true
                        }) {
                            Label("사진 삭제", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .scaledFont(size: 20)
                    }
                    .accessibilityLabel("더 보기")
                    .accessibilityHint("분석, 저장, 사진 추가, 메모, 삭제 메뉴를 엽니다")
                }
            }
    }

    var body: some View {
        Group {
            if embedInNavigation {
                NavigationView { detailBody }
            } else {
                detailBody
            }
        }
        .sheet(isPresented: $showingAddPhotoSheet) {
            CameraPickerView(
                date: date,
                mealType: mealType,
                mealStore: mealStore,
                selectedPhotoType: .constant(selectedPhotoType)
            )
        }
        .sheet(isPresented: $showingMemoEditor) {
            MemoEditorView(
                mealStore: mealStore,
                date: date,
                mealType: mealType,
                initialMemo: mealRecord?.memo ?? ""
            )
        }
        .alert("사진 삭제", isPresented: $showingDeleteAlert) {
            Button("취소", role: .cancel) { }
            Button("삭제", role: .destructive) {
                mealStore.deleteMeal(date: date, mealType: mealType)
                // alert가 닫힌 후 dismiss 실행
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    dismiss()
                }
            }
        } message: {
            Text("이 식사의 사진을 삭제하시겠습니까?\n메모도 함께 삭제됩니다.")
        }
        .alert("저장 완료", isPresented: $showingSaveSuccessAlert) {
            Button("확인", role: .cancel) { }
        } message: {
            Text("사진이 '\(albumName)' 앨범에 저장되었습니다.")
        }
        .alert("저장 실패", isPresented: $showingSaveErrorAlert) {
            Button("확인", role: .cancel) { }
        } message: {
            Text("사진 저장에 실패했습니다. 사진 접근 권한을 확인해주세요.")
        }
        .alert("식단 분석 결과", isPresented: $showingAnalysisResult) {
            Button("확인", role: .cancel) { }
            Button("메모에 추가") {
                addAnalysisResultToMemo()
            }
        } message: {
            if let result = analysisResult {
                Text(result.summary)
            } else {
                Text("분석 결과가 없습니다.")
            }
        }
        .onAppear {
            // 피드백 로드
            loadFeedbacks()
        }
    }

    // 식후는 찍지 않고 이 식사를 "다 먹음" 으로 마친다
    private func finishWithoutAfterPhoto() {
        mealStore.recordAteAll(date: date, mealType: mealType)
        NotificationManager.shared.cancelAteAllReminder(date: date, mealType: mealType)
    }

    // 식단 분석 — 기기 안(Vision)에서 무료로, 횟수 제한 없이
    private func analyzeFoodWithVision() {
        guard let record = mealRecord else { return }

        // 식단 모드일 때 식후 사진은 분석 불가
        if SettingsManager.shared.albumType == .diet && currentPage == 1 {
            print("⚠️ [FoodAnalysis] 식후 사진은 분석할 수 없습니다")
            return
        }

        // 현재 페이지의 이미지 가져오기
        let imageData: Data?
        if SettingsManager.shared.albumType == .exercise {
            imageData = record.beforeImageData
        } else {
            imageData = currentPage == 0 ? record.beforeImageData : record.afterImageData
        }

        // 분석에는 저장 크기면 충분하다 (예전 48MP 사진을 원본 크기로 풀지 않도록)
        guard let data = imageData, let image = MealImageResizer.downsampledImage(from: data, maxPixel: MealImageResizer.storedSide) else {
            return
        }

        analyzingFood = true
        fallbackToVisionFramework(image: image)
    }

    // Vision Framework로 분석
    private func fallbackToVisionFramework(image: UIImage) {
        VisionAnalyzer.shared.analyzeFoodImage(image) { result in
            DispatchQueue.main.async {
                self.analyzingFood = false

                switch result {
                case .success(let analysis):
                    // 분석 결과를 저장용 모델로 변환
                    let visionData = VisionAnalysisData(
                        foodItems: analysis.foodItems,
                        extractedText: analysis.extractedText,
                        confidence: analysis.confidence,
                        analyzedDate: Date(),
                        isOpenAI: false,
                        description: nil
                    )

                    // 저장
                    self.mealStore.updateVisionAnalysis(date: self.date, mealType: self.mealType, analysis: visionData)

                    // 알림용으로도 설정
                    self.analysisResult = analysis
                    self.showingAnalysisResult = true

                case .failure(let error):
                    print("❌ 식단 분석 실패: \(error)")
                    // 에러 발생 시에도 빈 결과 표시
                    self.analysisResult = FoodAnalysisResult(foodItems: [], extractedText: [], confidence: 0.0)
                    self.showingAnalysisResult = true
                }
            }
        }
    }

    // 피드백 로드
    private func loadFeedbacks() {
        isLoadingFeedbacks = true

        Task {
            // 내 식단에 달린 대화 전체를 시간순으로 가져온다.
            //
            // 예전에는 "받은 피드백"과 "내가 보낸 피드백"을 따로 불러왔는데, 뒤엣것은
            // `authorId == 나 AND 같은 날짜·끼니` 라서 **내가 그날 그 끼니에 남 아무에게나 보낸 글**이
            // 내 식단 밑에 딸려 나왔다. 이 식사와 아무 상관 없는 글이었다.
            let album = SettingsManager.shared.albumType
            let loaded = (try? await FriendManager.shared.getFeedbackThread(
                ownerId: FriendManager.shared.myUserId, date: date, mealType: mealType, album: album
            )) ?? []

            await MainActor.run {
                self.feedbacks = loaded
                self.isLoadingFeedbacks = false
                print("✅ [PhotoDetailView] 피드백 로드 완료: \(loaded.count)개")

                // 자동으로 읽음 처리
                markAllFeedbacksAsRead()
            }
        }
    }

    // 모든 피드백을 읽음으로 표시
    private func markAllFeedbacksAsRead() {
        Task {
            do {
                try await FriendManager.shared.markAllFeedbacksAsRead(
                    date: date, mealType: mealType, album: SettingsManager.shared.albumType)
                print("✅ [PhotoDetailView] 피드백 읽음 처리 완료")

                // 읽음 상태 업데이트
                await MainActor.run {
                    for index in feedbacks.indices {
                        feedbacks[index].isRead = true
                    }
                }
            } catch {
                print("❌ [PhotoDetailView] 피드백 읽음 처리 실패: \(error)")
            }
        }
    }

    // 분석 결과를 메모에 추가
    private func addAnalysisResultToMemo() {
        guard let result = analysisResult else { return }

        let currentMemo = mealRecord?.memo ?? ""
        var newMemo = currentMemo

        // 기존 메모가 있으면 줄바꿈 추가
        if !currentMemo.isEmpty {
            newMemo += "\n\n"
        }

        // 분석 결과 추가
        if !result.foodItems.isEmpty {
            newMemo += "🍽️ " + result.foodItems.joined(separator: ", ")
        }

        if !result.extractedText.isEmpty {
            if !result.foodItems.isEmpty {
                newMemo += "\n"
            }
            newMemo += "📝 " + result.extractedText.joined(separator: " ")
        }

        // 메모 업데이트
        mealStore.updateMemo(date: date, mealType: mealType, memo: newMemo)
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
        return formatter
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter
    }

    private var albumName: String {
        switch SettingsManager.shared.albumType {
        case .diet:
            return String(localized: "세끼식단", comment: "Photos album name for saved meal photos")
        case .exercise:
            return String(localized: "세끼운동", comment: "Photos album name for saved workout photos")
        }
    }

    private func saveCurrentPhotoToAlbum() {
        guard let record = mealRecord else { return }

        // 운동 모드일 때는 항상 beforeImageData 사용
        let imageData: Data?
        if SettingsManager.shared.albumType == .exercise {
            imageData = record.beforeImageData
        } else {
            // 식단 모드: 현재 페이지에 따라 식전/식후 사진 데이터 선택
            imageData = currentPage == 0 ? record.beforeImageData : record.afterImageData
        }

        guard let imageData = imageData, let image = UIImage(data: imageData) else {
            showingSaveErrorAlert = true
            return
        }

        MealAlbumSaver.save(image, toAlbum: albumName) { success in
            if success {
                showingSaveSuccessAlert = true
            } else {
                showingSaveErrorAlert = true
            }
        }
    }
}

// 메모 편집 뷰
struct MemoEditorView: View {
    @ObservedObject var mealStore: MealRecordStore
    let date: Date
    let mealType: MealType
    @State var initialMemo: String
    @Environment(\.dismiss) var dismiss

    @State private var memoText: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: mealType.symbolName)
                        .font(.title)
                        .foregroundColor(mealType.symbolColor)
                    Text(mealType.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                }
                .padding()

                TextEditor(text: $memoText)
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                Text("음식 이름이나 느낀 점을 간단히 메모해보세요")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("메모 작성")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소", systemImage: "xmark") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("저장", systemImage: "checkmark") {
                        mealStore.updateMemo(date: date, mealType: mealType, memo: memoText.isEmpty ? nil : memoText)
                        dismiss()
                    }
                }
            }
            .onAppear {
                memoText = initialMemo
            }
        }
    }
}

// 커스텀 카메라 뷰

private extension View {
    /// 빈 사진 칸: 탭하면 사진을 더한다. 보이스오버·음성 명령에서는 '사진 추가' 버튼 하나로 읽힌다
    /// (안에 '식후 사진 없이 마치기' 버튼이 있으면 그 버튼은 동작 목록으로 남는다)
    func addPhotoTap(_ action: @escaping () -> Void) -> some View {
        contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
            .accessibilityInputLabels([Text("사진 추가")])
    }
}
