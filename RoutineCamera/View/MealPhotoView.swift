//
//  MealPhotoView.swift
//  RoutineCamera
//

import SwiftUI
import AVFoundation
import Photos

struct MealPhotoView: View {
    let date: Date
    let mealType: MealType
    let mealRecord: MealRecord?
    @ObservedObject var mealStore: MealRecordStore
    let isToday: Bool
    let photoSize: CGFloat

    @State private var showingCameraPicker = false // 이미지 없을 때
    @State private var showingPhotoDetail = false // 이미지 있을 때
    @State private var showingFeedbackSheet = false // 기록 없는 칸에 온 피드백(콕/댓글) 열람
    @State private var selectedImage: UIImage?
    @State private var selectedPhotoType: PhotoType = .before // 식전/식후 선택
    @State private var unreadFeedbackCount: Int = 0 // 안읽은 피드백 개수

    enum PhotoType {
        case before // 식전
        case after  // 식후
    }

    // 미래 날짜 확인
    private var isFutureDate: Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDate = calendar.startOfDay(for: date)
        return targetDate > today
    }

    // 과거 날짜이면서 기록하지 않은 경우 (실패)
    // 간식은 선택사항이므로 제외
    private var isPastDateMissed: Bool {
        // 간식은 안 먹어도 괜찮음
        if mealType.isSnack {
            return false
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDate = calendar.startOfDay(for: date)
        // 시작일(첫 실행/최오래 기록) 이전 날짜는 "설치 전"이므로 실패로 판정하지 않음
        let startDay = calendar.startOfDay(for: mealStore.startDate)
        return targetDate < today && targetDate >= startDay && mealRecord == nil
    }

    // 시작 직후 유예 기간(첫 3일). 이 기간의 미기록은 "실패"로 강조하지 않고 부드럽게 안내
    private var graceDays: Int { 3 }
    private var isWithinGracePeriod: Bool {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: mealStore.startDate)
        guard let graceEnd = calendar.date(byAdding: .day, value: graceDays, to: startDay) else { return false }
        let targetDate = calendar.startOfDay(for: date)
        return targetDate < graceEnd
    }

    // "연속 끊김" 지점: 이 날 전체가 미기록이고 바로 이전 날은 기록이 있던 경우
    // (완화된 기준 isDayRecorded 사용). 시각적으로 빨강 강조는 하지 않고 접근성 안내에만 쓴다.
    private var isStreakBreakDay: Bool {
        guard isPastDateMissed, !isWithinGracePeriod else { return false }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        // 이 날에 아무 기록도 없어야 진짜 끊김
        guard !mealStore.isDayRecorded(day) else { return false }
        guard let prevDay = calendar.date(byAdding: .day, value: -1, to: day) else { return false }
        return mealStore.isDayRecorded(prevDay)
    }

    // 미기록이지만 강조하지 않는 "부드러운 미기록"
    private var isSoftMissed: Bool {
        isPastDateMissed && !isStreakBreakDay
    }

    // 배경 색상 계산 (색은 최소화 — 끊김도 빨강으로 '박제'하지 않고 전부 중립)
    private var backgroundColor: Color {
        if isFutureDate {
            return Color(.systemGray5)
        } else {
            return Color(.systemGray6)       // 미기록·끊김 모두 동일한 중립 배경
        }
    }

    // 현재 시간대에 맞는 식사인지 확인
    private var isCurrentMeal: Bool {
        guard isToday, mealRecord == nil else { return false }

        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let currentMinutes = hour * 60 + minute

        // NotificationManager의 시간 설정 가져오기
        let notificationManager = NotificationManager.shared
        let breakfastHour = calendar.component(.hour, from: notificationManager.breakfastTime)
        let breakfastMinute = calendar.component(.minute, from: notificationManager.breakfastTime)
        let lunchHour = calendar.component(.hour, from: notificationManager.lunchTime)
        let lunchMinute = calendar.component(.minute, from: notificationManager.lunchTime)
        let dinnerHour = calendar.component(.hour, from: notificationManager.dinnerTime)
        let dinnerMinute = calendar.component(.minute, from: notificationManager.dinnerTime)

        let breakfastMinutes = breakfastHour * 60 + breakfastMinute
        let lunchMinutes = lunchHour * 60 + lunchMinute
        let dinnerMinutes = dinnerHour * 60 + dinnerMinute

        // 오늘의 모든 식사 기록 확인
        let meals = mealStore.getMeals(for: date)
        let hasBreakfast = meals[.breakfast]?.isComplete ?? false
        let hasLunch = meals[.lunch]?.isComplete ?? false
        let hasDinner = meals[.dinner]?.isComplete ?? false

        // 가장 가까운 다음 식사 결정
        if !hasBreakfast && currentMinutes < breakfastMinutes + 120 {
            // 아침 식사 시간 전후 2시간 이내이고 아직 기록 안 함
            return mealType == .breakfast
        } else if !hasLunch && currentMinutes < lunchMinutes + 120 {
            // 점심 식사 시간 전후 2시간 이내이고 아직 기록 안 함
            return mealType == .lunch
        } else if !hasDinner && currentMinutes < dinnerMinutes + 120 {
            // 저녁 식사 시간 전후 2시간 이내이고 아직 기록 안 함
            return mealType == .dinner
        } else {
            // 모든 식사를 다 했거나, 다음 식사 시간이 아직 멀면 다음 미완료 식사 표시
            if !hasBreakfast {
                return mealType == .breakfast
            } else if !hasLunch {
                return mealType == .lunch
            } else if !hasDinner {
                return mealType == .dinner
            }
        }

        return false
    }

    // 사진이 있을 때 표시할 뷰
    @ViewBuilder
    private func photoContentView(record: MealRecord, image: UIImage) -> some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: photoSize, height: photoSize)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))

            badgeOverlayView(for: record)
        }
    }

    // 뱃지 오버레이 뷰
    @ViewBuilder
    private func badgeOverlayView(for record: MealRecord) -> some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                memoBadge(for: record)
                Spacer()
                photoCountBadge(for: record)
            }
            .padding(6)
        }
        .frame(width: photoSize, height: photoSize)
    }

    // 메모 뱃지
    @ViewBuilder
    private func memoBadge(for record: MealRecord) -> some View {
        if SettingsManager.shared.showMemoIcon && record.memo != nil && !record.memo!.isEmpty {
            Image(systemName: "note.text")
                .font(.system(size: 12))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
        }
    }

    // 사진 개수 뱃지
    @ViewBuilder
    private func photoCountBadge(for record: MealRecord) -> some View {
        // 사진 없이 기록한 경우에는 뱃지를 표시하지 않음
        // 개별 식사의 숨기기 설정이나 전역 설정이 꺼져있으면 표시하지 않음
        if !record.recordedWithoutPhoto && !record.hidePhotoCountBadge && SettingsManager.shared.albumType == .diet && SettingsManager.shared.showRemainingPhotoCount {
            let photoCount = (record.beforeImageData != nil ? 1 : 0) + (record.afterImageData != nil ? 1 : 0)
            if photoCount == 1 {
                Text("1")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.red)
                    .clipShape(Circle())
            }
        }
    }

    // 피드백 뱃지 (오른쪽 위)
    @ViewBuilder
    private func feedbackBadgeOverlay() -> some View {
        if unreadFeedbackCount > 0 {
            VStack {
                HStack {
                    Spacer()
                    Text("\(unreadFeedbackCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.orange)
                        .clipShape(Circle())
                        .padding(6)
                }
                Spacer()
            }
            .frame(width: photoSize, height: photoSize)
        }
    }

    // 사진이 없을 때 표시할 뷰
    @ViewBuilder
    private var emptyStateView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(backgroundColor)
            .overlay {
                emptyStateContent
            }
            .overlay {
                stateBorderOverlay
            }
    }

    // 과거 미기록 칸은 테두리 없이 조용한 빈 공간으로 둔다.
    // (점선 '미기록' 표시가 지나간 날마다 벽처럼 쌓여 완벽주의를 자극하던 것을 제거)
    @ViewBuilder
    private var stateBorderOverlay: some View {
        EmptyView()
    }

    // 빈 상태의 내용
    @ViewBuilder
    private var emptyStateContent: some View {
        VStack(spacing: 6) {
            mainSymbolView
            // + 초대는 '지금 기록할 수 있는' 오늘·유예 기간에만.
            // 과거 미기록 칸은 +를 빼서 "못 채운 칸"이 아니라 조용한 빈 공간으로 둔다.
            if isToday || (isWithinGracePeriod && isPastDateMissed) {
                plusIcon(color: .blue)
            }
        }
    }

    // 미래·과거 미기록은 옅은 회색, 유예·일반은 초대하는 식사 색
    private var symbolColor: Color {
        if isFutureDate { return .gray }
        if isWithinGracePeriod && isPastDateMissed { return mealType.symbolColor }  // 유예는 초대 톤 유지
        if isSoftMissed || isStreakBreakDay { return Color.gray.opacity(0.35) }     // 과거 미기록은 더 옅게 물러남
        return mealType.symbolColor
    }

    // 메인 심볼 뷰 (누적 빨간 숫자 제거, 상태별 톤만 조절)
    @ViewBuilder
    private var mainSymbolView: some View {
        if isCurrentMeal {
            PulsingSymbolView(
                symbolName: mealType.symbolName,
                color: mealType.symbolColor,
                size: min(photoSize * 0.4, 36)
            )
        } else {
            Image(systemName: mealType.symbolName)
                .font(.system(size: min(photoSize * 0.4, 36)))
                .foregroundColor(symbolColor)
        }
    }

    // 플러스 아이콘 뷰
    private func plusIcon(color: Color) -> some View {
        Image(systemName: "plus.circle.fill")
            .font(.system(size: min(photoSize * 0.25, 18)))
            .foregroundColor(color)
    }

    // 랜덤 음식 심볼 가져오기 (날짜와 식사 타입으로 시드 생성)
    private func getRandomFoodSymbol() -> (icon: String, color: Color) {
        let foodSymbols: [(String, Color)] = [
            ("fork.knife", .orange),
            ("cup.and.saucer.fill", .brown),
            ("leaf.fill", .green),
            ("carrot.fill", .orange),
            ("birthday.cake.fill", .pink),
            ("takeoutbag.and.cup.and.straw.fill", .red),
            ("fish.fill", .blue),
            ("cooktop.fill", .gray),
            ("wineglass.fill", .purple),
            ("mug.fill", .brown)
        ]

        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        let mealIndex = MealType.allCases.firstIndex(of: mealType) ?? 0

        let seed = (day + month * 31 + mealIndex * 100) % foodSymbols.count
        return foodSymbols[seed]
    }

    // 안읽은 피드백 개수 로드
    private func loadUnreadFeedbackCount() {
        Task {
            do {
                let count = try await FriendManager.shared.getUnreadFeedbackCount(date: date, mealType: mealType)
                await MainActor.run {
                    self.unreadFeedbackCount = count
                }
            } catch {
                print("❌ [MealPhotoView] 안읽은 피드백 개수 로드 실패: \(error)")
            }
        }
    }

    // 사진 없이 기록했을 때 표시할 뷰
    @ViewBuilder
    private func recordedWithoutPhotoView() -> some View {
        let (icon, color) = getRandomFoodSymbol()
        RoundedRectangle(cornerRadius: 12)
            .fill(color.opacity(0.2))
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: min(photoSize * 0.4, 36)))
                        .foregroundColor(color)

                    if let record = mealRecord, SettingsManager.shared.showMemoIcon && record.memo != nil && !record.memo!.isEmpty {
                        Image(systemName: "note.text")
                            .font(.system(size: 12))
                            .foregroundColor(color.opacity(0.7))
                    }
                }
            }
    }

    // 메인 오버레이 컨텐츠
    @ViewBuilder
    private var overlayContent: some View {
        if let record = mealRecord {
            if let imageData = record.thumbnailImageData, let uiImage = UIImage(data: imageData) {
                // 사진이 있는 경우
                photoContentView(record: record, image: uiImage)
            } else if record.recordedWithoutPhoto {
                // 사진 없이 기록한 경우
                recordedWithoutPhotoView()
            } else {
                // 기록이 없는 경우
                emptyStateView
            }
        } else {
            // 기록이 없는 경우
            emptyStateView
        }
    }

    // 보이스오버용 상태 문장 (색·애니메이션·뱃지로만 주던 정보를 청각 위계로 번역)
    private var accessibilityStatus: String {
        if let record = mealRecord, record.isComplete {
            var parts: [String] = []
            parts.append(record.recordedWithoutPhoto ? "사진 없이 기록 완료" : "기록 완료")
            if let memo = record.memo, !memo.isEmpty { parts.append("메모 있음") }
            if unreadFeedbackCount > 0 { parts.append("안 읽은 피드백 \(unreadFeedbackCount)개") }
            return parts.joined(separator: ", ")
        }
        if isFutureDate { return "예정된 끼니, 아직 기록할 수 없음" }

        let baseStatus: String
        if isWithinGracePeriod && isPastDateMissed { baseStatus = "아직 기록 전, 지금 기록할 수 있어요" }
        else if isStreakBreakDay { baseStatus = "미기록, 다음 기록부터 다시 이어져요" }
        else if isSoftMissed { baseStatus = "미기록" }
        else if isCurrentMeal { baseStatus = "지금 기록할 차례" }
        else { baseStatus = "아직 기록 안 함" }

        // 기록 없는 칸에도 콕/댓글 수신 상태 안내
        if unreadFeedbackCount > 0 {
            return "안 읽은 피드백 \(unreadFeedbackCount)개, \(baseStatus)"
        }
        return baseStatus
    }

    // 보이스오버 힌트 (액션 안내)
    private var accessibilityActionHint: String {
        if isFutureDate { return "" }
        if mealRecord?.isComplete == true { return "두 번 탭하여 상세 보기" }
        if unreadFeedbackCount > 0 { return "두 번 탭하여 피드백 보기" }
        return "두 번 탭하여 기록"
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.clear)
            .frame(width: photoSize, height: photoSize)
            .overlay(overlayContent)
            .overlay(feedbackBadgeOverlay()) // 기록 유무와 관계없이 안 읽은 피드백(콕/댓글) 배지 표시
            .onTapGesture {
                handleTap()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(mealType.rawValue)
            .accessibilityValue(accessibilityStatus)
            .accessibilityHint(accessibilityActionHint)
            .accessibilityAddTraits(isFutureDate ? [] : .isButton)
            .sheet(isPresented: $showingCameraPicker) {
                cameraPickerSheet
            }
            .sheet(isPresented: $showingPhotoDetail) {
                loadUnreadFeedbackCount()
            } content: {
                photoDetailSheet
            }
            .sheet(isPresented: $showingFeedbackSheet) {
                loadUnreadFeedbackCount()
            } content: {
                EmptyMealFeedbackSheet(date: date, mealType: mealType) {
                    // "지금 기록하기": 시트 닫고 카메라 열기
                    showingFeedbackSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showingCameraPicker = true
                    }
                }
            }
            .onAppear {
                loadUnreadFeedbackCount()
            }
    }

    // 탭 제스처 핸들러
    private func handleTap() {
        if !isFutureDate {
            if mealRecord != nil {
                showingPhotoDetail = true
            } else if unreadFeedbackCount > 0 {
                // 기록 없는 칸에 콕/댓글이 와 있으면 먼저 보여줌
                showingFeedbackSheet = true
            } else {
                showingCameraPicker = true
            }
        }
    }

    // 카메라 피커 시트
    private var cameraPickerSheet: some View {
        CameraPickerView(
            date: date,
            mealType: mealType,
            mealStore: mealStore,
            selectedPhotoType: $selectedPhotoType
        )
    }

    // 사진 상세 시트
    private var photoDetailSheet: some View {
        PhotoDetailView(
            date: date,
            mealType: mealType,
            mealRecord: mealRecord,
            mealStore: mealStore
        )
    }
}

// 기록 없는 끼니로 온 피드백(콕/댓글) 열람 시트
struct EmptyMealFeedbackSheet: View {
    let date: Date
    let mealType: MealType
    let onRecord: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var feedbacks: [MealFeedback] = []
    @State private var isLoading = true

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if feedbacks.isEmpty {
                    Text("받은 피드백이 없습니다")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(feedbacks) { feedback in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(feedback.authorNickname)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(feedback.createdAt, style: .relative)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Text(feedback.content)
                                .font(.system(size: 15))
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(feedback.authorNickname)님의 피드백: \(feedback.content)")
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("\(dateString) \(mealType.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onRecord) {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("지금 기록하기")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
            }
            .task {
                feedbacks = (try? await FriendManager.shared.getMyFeedbacks(date: date, mealType: mealType)) ?? []
                isLoading = false
                // 열람했으므로 읽음 처리 (배지 해제)
                try? await FriendManager.shared.markAllFeedbacksAsRead(date: date, mealType: mealType)
            }
        }
    }
}

// 펄스 애니메이션이 적용된 심볼 뷰
struct PulsingSymbolView: View {
    let symbolName: String
    let color: Color
    let size: CGFloat

    @State private var isAnimating = false
    // 동작 줄이기(Reduce Motion) 설정 시 펄스 대신 정적 강조로 대체
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size))
            .foregroundColor(color)
            .scaleEffect(!reduceMotion && isAnimating ? 1.2 : 1.0)
            .opacity(!reduceMotion && isAnimating ? 0.6 : 1.0)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// 카메라/앨범 선택 화면
