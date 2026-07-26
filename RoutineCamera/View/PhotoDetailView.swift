//
//  PhotoDetailView.swift
//  RoutineCamera
//

import SwiftUI
import AVFoundation
import Photos

struct PhotoDetailView: View {
    let date: Date
    let mealType: MealType
    let mealRecord: MealRecord?
    @ObservedObject var mealStore: MealRecordStore
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
    @State private var sentFeedbacks: [SentFeedback] = [] // 보낸 피드백 목록
    @State private var isLoadingFeedbacks = false // 피드백 로딩 중

    @ViewBuilder
    private var detailBody: some View {
            VStack(spacing: 0) {
                if let record = mealRecord {
                    // 사진 영역
                    if SettingsManager.shared.albumType == .exercise {
                        // 운동 모드: 사진 1장만 표시
                        if let beforeData = record.beforeImageData, let beforeImage = UIImage(data: beforeData) {
                            Image(uiImage: beforeImage)
                                .resizable()
                                .scaledToFit()
                                .accessibilityLabel("\(mealType.rawValue) 기록 사진")
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "photo")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
                                    .accessibilityHidden(true)
                                Text("사진 없음")
                                    .font(.system(size: 18))
                                    .foregroundColor(.secondary)
                                Text("탭하여 사진 추가")
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemGray6))
                            .onTapGesture {
                                selectedPhotoType = .before
                                showingAddPhotoSheet = true
                            }
                        }
                    } else {
                        // 식단 모드: 식전/식후 TabView
                        TabView(selection: $currentPage) {
                            // 식전 사진
                            if let beforeData = record.beforeImageData, let beforeImage = UIImage(data: beforeData) {
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
                                        .font(.system(size: 18))
                                        .foregroundColor(.secondary)
                                    Text("탭하여 사진 추가")
                                        .font(.system(size: 14))
                                        .foregroundColor(.blue)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(.systemGray6))
                                .tag(0)
                                .onTapGesture {
                                    selectedPhotoType = .before
                                    showingAddPhotoSheet = true
                                }
                            }

                            // 식후 사진
                            if let afterData = record.afterImageData, let afterImage = UIImage(data: afterData) {
                                Image(uiImage: afterImage)
                                    .resizable()
                                    .scaledToFit()
                                    .tag(1)
                                    .accessibilityLabel("식후 사진")
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 60))
                                        .foregroundColor(.gray)
                                        .accessibilityHidden(true)
                                    Text("식후 사진 없음")
                                        .font(.system(size: 18))
                                        .foregroundColor(.secondary)
                                    Text("탭하여 사진 추가")
                                        .font(.system(size: 14))
                                        .foregroundColor(.blue)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(.systemGray6))
                                .tag(1)
                                .onTapGesture {
                                    selectedPhotoType = .after
                                    showingAddPhotoSheet = true
                                }
                            }
                        }
                        .tabViewStyle(.page)
                        .indexViewStyle(.page(backgroundDisplayMode: .always))
                    }

                    // 정보 영역
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: mealType.symbolName)
                                .foregroundColor(mealType.symbolColor)
                                .font(.system(size: 24))
                            Text(mealType.rawValue)
                                .font(.system(size: 24, weight: .bold))
                            // 식단 모드일 때만 식전/식후 표시
                            if SettingsManager.shared.albumType == .diet {
                                Text(currentPage == 0 ? "식전" : "식후")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }

                        if let memo = record.memo, !memo.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("메모")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Text(memo)
                                    .font(.system(size: 16))
                            }
                        }

                        // Vision 분석 결과 표시 (식단 모드일 때만)
                        if SettingsManager.shared.albumType == .diet {
                            if let analysis = record.visionAnalysis {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("식단 분석")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        // 다시 분석하기 버튼 (API 키 설정 시에만 표시, 식전 사진만)
                                        if currentPage == 0 {
                                            let canAnalyze = SettingsManager.shared.freeAnalysisCount > 0 || (OpenAIFoodAnalyzer.shared.isConfigured && CoinManager.shared.hasEnoughCoins())

                                            Button(action: {
                                                analyzeFoodWithVision()
                                            }) {
                                                HStack(spacing: 4) {
                                                    if analyzingFood {
                                                        ProgressView()
                                                            .scaleEffect(0.7)
                                                    } else {
                                                        Image(systemName: "arrow.clockwise")
                                                            .font(.system(size: 12))
                                                    }
                                                    Text(analyzingFood ? "분석 중" : "다시 분석")
                                                        .font(.system(size: 13))
                                                }
                                                .foregroundColor(canAnalyze ? .blue : .gray)
                                            }
                                            .disabled(analyzingFood || !canAnalyze)
                                        }
                                        // 식후 사진 또는 분석 불가 안내
                                        if currentPage == 1 {
                                            Text("(식후 사진)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        } else if SettingsManager.shared.freeAnalysisCount == 0 && (!OpenAIFoodAnalyzer.shared.isConfigured || !CoinManager.shared.hasEnoughCoins()) {
                                            Text(OpenAIFoodAnalyzer.shared.isConfigured ? "(코인 부족)" : "(설정 필요)")
                                                .font(.caption)
                                                .foregroundColor(.orange)
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
                                let canAnalyze = SettingsManager.shared.freeAnalysisCount > 0 || (OpenAIFoodAnalyzer.shared.isConfigured && CoinManager.shared.hasEnoughCoins())
                                let buttonText: String = {
                                    if analyzingFood {
                                        return "분석 중..."
                                    } else if SettingsManager.shared.freeAnalysisCount > 0 {
                                        return "식단 분석하기 (무료 \(SettingsManager.shared.freeAnalysisCount)회)"
                                    } else if OpenAIFoodAnalyzer.shared.isConfigured {
                                        return CoinManager.shared.hasEnoughCoins() ? "식단 분석하기 (코인 사용)" : "식단 분석하기 (코인 부족)"
                                    } else {
                                        return "식단 분석하기 (설정 필요)"
                                    }
                                }()

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
                                    .font(.system(size: 16))
                                    .foregroundColor(canAnalyze ? .blue : .gray)
                                }
                                .disabled(analyzingFood || !canAnalyze)
                            } else if currentPage == 1 {
                                // 식후 사진 안내
                                Text("식후 사진은 분석할 수 없습니다")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                            }
                        }

                        // 식단 모드이고 사진이 1장만 있을 때 토글 표시
                        if SettingsManager.shared.albumType == .diet {
                            let photoCount = (record.beforeImageData != nil ? 1 : 0) + (record.afterImageData != nil ? 1 : 0)
                            if photoCount == 1 {
                                Divider()
                                    .padding(.vertical, 8)

                                Toggle("식전/식후 사진 알림 가리기", isOn: Binding(
                                    get: { record.hidePhotoCountBadge },
                                    set: { newValue in
                                        mealStore.updateHidePhotoCountBadge(date: date, mealType: mealType, hide: newValue)
                                    }
                                ))
                                .font(.system(size: 16))

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
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                if isLoadingFeedbacks {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                            }

                            // 받은 피드백
                            if !feedbacks.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("받은 피드백")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.blue)

                                    ForEach(feedbacks) { feedback in
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text(feedback.authorNickname)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(.blue)
                                                Spacer()
                                                Text(feedback.createdAt, style: .relative)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.secondary)
                                                if !feedback.isRead {
                                                    Circle()
                                                        .fill(Color.red)
                                                        .frame(width: 6, height: 6)
                                                }
                                            }
                                            Text(feedback.content)
                                                .font(.system(size: 14))
                                                .padding(12)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color.blue.opacity(0.1))
                                                .cornerRadius(8)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }

                            // 보낸 피드백
                            if !sentFeedbacks.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("내가 보낸 피드백")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.green)

                                    ForEach(sentFeedbacks) { feedback in
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text("나")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(.green)
                                                Spacer()
                                                Text(feedback.createdAt, style: .relative)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.secondary)
                                            }
                                            Text(feedback.content)
                                                .font(.system(size: 14))
                                                .padding(12)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color.green.opacity(0.1))
                                                .cornerRadius(8)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }

                            // 피드백이 하나도 없을 때
                            if feedbacks.isEmpty && sentFeedbacks.isEmpty && !isLoadingFeedbacks {
                                Text("아직 피드백이 없습니다")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                }
            }
            .navigationTitle(dateFormatter.string(from: date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(embedInNavigation ? "닫기" : "뒤로") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        // 식단 분석 버튼 (식단 모드 + 식전 사진만)
                        if SettingsManager.shared.albumType == .diet && currentPage == 0 {
                            let canAnalyze = SettingsManager.shared.freeAnalysisCount > 0 || (OpenAIFoodAnalyzer.shared.isConfigured && CoinManager.shared.hasEnoughCoins())

                            Button(action: {
                                analyzeFoodWithVision()
                            }) {
                                Label(analyzingFood ? "분석 중..." : "식단 분석", systemImage: "sparkles")
                            }
                            .disabled(analyzingFood || !canAnalyze)
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
                            .font(.system(size: 20))
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

    // 식단 분석 (무료 분석 우선, 소진 시 OpenAI 사용)
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

        guard let data = imageData, let image = UIImage(data: data) else {
            return
        }

        analyzingFood = true

        // 무료 분석 횟수가 남아있으면 Vision Framework 사용 (무료)
        if SettingsManager.shared.freeAnalysisCount > 0 {
            print("✅ [FoodAnalysis] 무료 분석 사용 (잔여: \(SettingsManager.shared.freeAnalysisCount)회)")

            // 무료 횟수 차감
            SettingsManager.shared.freeAnalysisCount -= 1

            // Vision Framework로 분석
            fallbackToVisionFramework(image: image)
            return
        }

        // 무료 횟수 소진 - OpenAI 사용 (코인 필요)
        print("ℹ️ [FoodAnalysis] 무료 분석 소진 - OpenAI 사용")

        // OpenAI가 설정되어 있는지 확인
        guard OpenAIFoodAnalyzer.shared.isConfigured else {
            print("❌ [FoodAnalysis] OpenAI 미설정, 무료 분석 소진 - 분석 불가")
            analyzingFood = false
            return
        }

        // 코인 체크
        guard CoinManager.shared.hasEnoughCoins() else {
            print("❌ [FoodAnalysis] 코인 부족 - 분석 불가")
            analyzingFood = false
            return
        }

        // OpenAI 분석 실행
        _Concurrency.Task {
            do {
                let result = try await OpenAIFoodAnalyzer.shared.analyzeFood(image: image)

                await MainActor.run {
                    // 분석 성공 - 코인 차감
                    if CoinManager.shared.consumeCoin() {
                        // 분석 결과를 저장용 모델로 변환
                        let visionData = VisionAnalysisData(
                            foodItems: [result.foodName] + result.ingredients,
                            extractedText: [],
                            confidence: 1.0,
                            analyzedDate: Date(),
                            isOpenAI: true,
                            description: result.description
                        )

                        // 저장
                        self.mealStore.updateVisionAnalysis(date: self.date, mealType: self.mealType, analysis: visionData)

                        // 알림용으로도 설정
                        self.analysisResult = FoodAnalysisResult(
                            foodItems: [result.foodName],
                            extractedText: result.ingredients,
                            confidence: 1.0
                        )
                        self.showingAnalysisResult = true
                        print("✅ [FoodAnalysis] OpenAI 분석 완료 (코인 차감됨, 남은 코인: \(CoinManager.shared.currentCoins))")
                    }
                    self.analyzingFood = false
                }
            } catch {
                await MainActor.run {
                    print("❌ [FoodAnalysis] OpenAI 분석 실패: \(error)")
                    self.analyzingFood = false
                }
            }
        }
    }

    // Vision Framework로 분석 (폴백)
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
            do {
                // 받은 피드백과 보낸 피드백 동시에 로드
                async let receivedFeedbacks = FriendManager.shared.getMyFeedbacks(date: date, mealType: mealType)
                async let sentFeedbacks = FriendManager.shared.getMySentFeedbacks(date: date, mealType: mealType)

                let (loadedReceived, loadedSent) = try await (receivedFeedbacks, sentFeedbacks)

                await MainActor.run {
                    self.feedbacks = loadedReceived
                    self.sentFeedbacks = loadedSent
                    self.isLoadingFeedbacks = false
                    print("✅ [PhotoDetailView] 피드백 로드 완료: 받음 \(loadedReceived.count)개, 보냄 \(loadedSent.count)개")

                    // 자동으로 읽음 처리
                    markAllFeedbacksAsRead()
                }
            } catch {
                await MainActor.run {
                    self.isLoadingFeedbacks = false
                    print("❌ [PhotoDetailView] 피드백 로드 실패: \(error)")
                }
            }
        }
    }

    // 모든 피드백을 읽음으로 표시
    private func markAllFeedbacksAsRead() {
        Task {
            do {
                try await FriendManager.shared.markAllFeedbacksAsRead(date: date, mealType: mealType)
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
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter
    }

    private var albumName: String {
        switch SettingsManager.shared.albumType {
        case .diet:
            return "세끼식단"
        case .exercise:
            return "세끼운동"
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

        let currentAlbumName = albumName

        // 사진 라이브러리 접근 권한 확인
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    showingSaveErrorAlert = true
                }
                return
            }

            // 먼저 앨범이 있는지 확인
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "title = %@", currentAlbumName)
            let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)

            if let album = collection.firstObject {
                // 기존 앨범에 이미지 추가
                PHPhotoLibrary.shared().performChanges({
                    let assetRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
                    let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                    albumChangeRequest?.addAssets([assetRequest.placeholderForCreatedAsset!] as NSArray)
                }) { success, error in
                    DispatchQueue.main.async {
                        if success {
                            showingSaveSuccessAlert = true
                        } else {
                            showingSaveErrorAlert = true
                        }
                    }
                }
            } else {
                // 새 앨범 생성
                var albumPlaceholder: PHObjectPlaceholder?
                PHPhotoLibrary.shared().performChanges({
                    let createAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: currentAlbumName)
                    albumPlaceholder = createAlbumRequest.placeholderForCreatedAssetCollection
                }) { success, error in
                    if success, let placeholder = albumPlaceholder {
                        // 앨범이 생성되면 이미지 추가
                        let fetchResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [placeholder.localIdentifier], options: nil)
                        if let album = fetchResult.firstObject {
                            PHPhotoLibrary.shared().performChanges({
                                let assetRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
                                let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                                albumChangeRequest?.addAssets([assetRequest.placeholderForCreatedAsset!] as NSArray)
                            }) { success, error in
                                DispatchQueue.main.async {
                                    if success {
                                        showingSaveSuccessAlert = true
                                    } else {
                                        showingSaveErrorAlert = true
                                    }
                                }
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            showingSaveErrorAlert = true
                        }
                    }
                }
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
                    Text(mealType.rawValue)
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
                    Button("취소") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("저장") {
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
