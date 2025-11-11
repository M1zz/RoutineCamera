//
//  ContentView.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/11/25.
//

import SwiftUI
import AVFoundation
import Photos

struct ContentView: View {
    @StateObject private var mealStore = MealRecordStore()
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var goalManager = GoalManager.shared
    @State private var showingSettings = false
    @State private var showingStatistics = false
    @State private var showingGoalAchieved = false

    // 오늘 날짜와 날짜 리스트 초기화
    @State private var todayDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var dateList: [Date] = []
    @State private var isTodayVisible = true // 오늘 셀이 화면에 보이는지 추적
    @State private var loadedPastDays = 30 // 로드된 과거 일수
    @State private var loadedFutureDays = 30 // 로드된 미래 일수
    @State private var isLoadingPast = false // 과거 날짜 로딩 중인지
    @State private var isLoadingFuture = false // 미래 날짜 로딩 중인지

    private func initializeDateList() {
        print("📅 [ContentView] 날짜 리스트 초기화 시작")
        let calendar = Calendar.current
        todayDate = calendar.startOfDay(for: Date())

        // 과거에 기록이 있는지 확인
        let hasPastRecords = mealStore.records.contains { record in
            record.date < todayDate
        }

        if hasPastRecords {
            // 과거 기록이 있으면 -30...30 범위 로드
            loadedPastDays = 30
            dateList = (-loadedPastDays...loadedFutureDays).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: todayDate)
            }
            print("📅 [ContentView] 과거 기록 있음 - 날짜 리스트 초기화 완료: \(dateList.count)개 날짜 로드")
        } else {
            // 과거 기록이 없으면 오늘부터만 로드 (0...30)
            loadedPastDays = 0
            dateList = (0...loadedFutureDays).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: todayDate)
            }
            print("📅 [ContentView] 과거 기록 없음 - 오늘부터만 로드: \(dateList.count)개 날짜 로드")
        }
    }

    private func loadMorePastDates() {
        guard !isLoadingPast else {
            print("⬆️ [ContentView] 이미 과거 날짜 로딩 중 - 스킵")
            return
        }

        isLoadingPast = true
        print("⬆️ [ContentView] 과거 날짜 추가 로드 시작")

        let calendar = Calendar.current
        let oldCount = dateList.count
        // 30일씩 추가로 로드
        let newPastDays = loadedPastDays + 30
        let additionalDates = ((-newPastDays)...(-loadedPastDays-1)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: todayDate)
        }
        dateList = additionalDates + dateList
        loadedPastDays = newPastDays
        print("⬆️ [ContentView] 과거 날짜 추가 완료: \(oldCount)개 → \(dateList.count)개")

        // 로딩 완료 후 플래그 해제
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isLoadingPast = false
        }
    }

    private func loadMoreFutureDates() {
        guard !isLoadingFuture else {
            print("⬇️ [ContentView] 이미 미래 날짜 로딩 중 - 스킵")
            return
        }

        isLoadingFuture = true
        print("⬇️ [ContentView] 미래 날짜 추가 로드 시작")

        let calendar = Calendar.current
        let oldCount = dateList.count
        // 30일씩 추가로 로드
        let newFutureDays = loadedFutureDays + 30
        let additionalDates = ((loadedFutureDays+1)...newFutureDays).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: todayDate)
        }
        dateList = dateList + additionalDates
        loadedFutureDays = newFutureDays
        print("⬇️ [ContentView] 미래 날짜 추가 완료: \(oldCount)개 → \(dateList.count)개")

        // 로딩 완료 후 플래그 해제
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isLoadingFuture = false
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                // 메인 콘텐츠
                VStack(spacing: 0) {
                    // 상단 헤더 (Streak 표시)
                    StreakHeaderView(
                        mealStore: mealStore,
                        goalManager: goalManager,
                        onStatisticsTap: { showingStatistics = true },
                        onSettingsTap: { showingSettings = true },
                        onHeaderTap: {
                            withAnimation {
                                proxy.scrollTo(todayDate, anchor: .top)
                            }
                        }
                    )

                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: []) {
                            ForEach(dateList, id: \.self) { date in
                                DailySectionView(date: date, mealStore: mealStore)
                                    .id(date)
                                    .onAppear {
                                        if Calendar.current.isDate(date, inSameDayAs: todayDate) {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                isTodayVisible = true
                                            }
                                        }

                                        // 첫 번째 날짜가 보이면 더 과거 날짜 로드 (과거 기록이 있는 경우에만)
                                        if date == dateList.first && loadedPastDays > 0 {
                                            loadMorePastDates()
                                        }

                                        // 마지막 날짜가 보이면 더 미래 날짜 로드
                                        if date == dateList.last {
                                            loadMoreFutureDates()
                                        }
                                    }
                                    .onDisappear {
                                        if Calendar.current.isDate(date, inSameDayAs: todayDate) {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                isTodayVisible = false
                                            }
                                        }
                                    }
                            }
                        }
                    }
                }
                .background(Color(.systemGroupedBackground))
                .zIndex(0)
                .onAppear {
                    // 날짜 리스트 초기화
                    if dateList.isEmpty {
                        initializeDateList()

                        // 즉시 오늘 날짜로 스크롤 (딜레이 없이)
                        DispatchQueue.main.async {
                            proxy.scrollTo(todayDate, anchor: .top)
                        }
                    }

                    // 알림 권한 요청
                    if !notificationManager.notificationsEnabled {
                        notificationManager.requestAuthorization { granted in
                            if granted {
                                notificationManager.scheduleMealNotifications()
                            }
                        }
                    }
                }

                // 플로팅 "오늘" 버튼 (오늘이 화면에 없을 때만 표시)
                if !isTodayVisible {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                withAnimation {
                                    proxy.scrollTo(todayDate, anchor: .top)
                                }
                            }) {
                                Text("오늘")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                                    .background(Color.blue)
                                    .clipShape(Capsule())
                                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                            }
                            .contentShape(Rectangle())
                            .padding(.trailing, 16)
                            .padding(.bottom, 16)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .allowsHitTesting(true)
                    .zIndex(999)
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(notificationManager: notificationManager, goalManager: goalManager, mealStore: mealStore)
            }
            .onChange(of: showingSettings) { oldValue, newValue in
                // 설정 창이 닫힐 때 dateList 재초기화
                if oldValue == true && newValue == false {
                    dateList = []
                    isLoadingPast = false
                    isLoadingFuture = false
                }
            }
            .sheet(isPresented: $showingStatistics) {
                StatisticsView(mealStore: mealStore)
            }
        }
    }
}

// Streak 헤더 뷰
struct StreakHeaderView: View {
    @ObservedObject var mealStore: MealRecordStore
    @ObservedObject var goalManager: GoalManager
    let onStatisticsTap: () -> Void
    let onSettingsTap: () -> Void
    let onHeaderTap: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                // 통계 버튼
                Button(action: onStatisticsTap) {
                    Image(systemName: "chart.bar.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                .padding(.leading, 16)

                Spacer()

                HStack(spacing: 12) {
                    // 현재 연속 기록
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Text("🔥")
                                .font(.system(size: 28))
                            Text("\(mealStore.getCurrentStreak())")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.orange)
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                        }
                        Text("연속 기록")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 50)

                    // 최고 기록
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Text("🏆")
                                .font(.system(size: 28))
                            Text("\(mealStore.getMaxStreak())")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.yellow)
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                        }
                        Text("최고 기록")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onHeaderTap()
                }

                Spacer()

                // 설정 버튼
                Button(action: onSettingsTap) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                .padding(.trailing, 16)
            }

            // 목표 진행률
            if goalManager.goalEnabled {
                let currentStreak = mealStore.getCurrentStreak()
                let progress = goalManager.getProgress(currentStreak: currentStreak)

                VStack(spacing: 8) {
                    HStack {
                        Text("목표: \(goalManager.goalDays)일 연속 기록")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer()
                        Text("\(currentStreak)/\(goalManager.goalDays)일")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(goalManager.isGoalAchieved(currentStreak: currentStreak) ? .green : .orange)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.systemGray5))
                                .frame(height: 10)

                            RoundedRectangle(cornerRadius: 6)
                                .fill(goalManager.isGoalAchieved(currentStreak: currentStreak) ? Color.green : Color.orange)
                                .frame(width: geometry.size.width * CGFloat(progress), height: 10)
                        }
                    }
                    .frame(height: 10)

                    if goalManager.isGoalAchieved(currentStreak: currentStreak) {
                        Text("🎉 목표 달성! 축하합니다!")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    onHeaderTap()
                }
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// 설정 화면
struct SettingsView: View {
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject var goalManager: GoalManager
    @ObservedObject var mealStore: MealRecordStore
    @Environment(\.dismiss) var dismiss
    @State private var showingSampleDataAlert = false
    @State private var showingClearDataAlert = false

    var body: some View {
        NavigationView {
            Form {
                // 개발용 섹션
                Section(header: Text("개발용")) {
                    Button("샘플 데이터 생성") {
                        showingSampleDataAlert = true
                    }
                    .alert("샘플 데이터 생성", isPresented: $showingSampleDataAlert) {
                        Button("취소", role: .cancel) { }
                        Button("생성") {
                            mealStore.generateSampleData()
                            // 설정 창 닫기 (데이터 재로드를 위해)
                            dismiss()
                        }
                    } message: {
                        Text("과거 30일간의 샘플 식사 기록을 생성합니다.\n앱을 다시 시작하면 데이터가 적용됩니다.")
                    }

                    Button("모든 데이터 삭제", role: .destructive) {
                        showingClearDataAlert = true
                    }
                    .alert("모든 데이터 삭제", isPresented: $showingClearDataAlert) {
                        Button("취소", role: .cancel) { }
                        Button("삭제", role: .destructive) {
                            mealStore.clearAllData()
                            // 설정 창 닫기
                            dismiss()
                        }
                    } message: {
                        Text("모든 식사 기록이 삭제됩니다. 이 작업은 되돌릴 수 없습니다.")
                    }
                }

                // 목표 설정
                Section(header: Text("목표 설정")) {
                    Toggle("목표 활성화", isOn: $goalManager.goalEnabled)

                    if goalManager.goalEnabled {
                        HStack {
                            Text("목표: \(goalManager.goalDays)일 연속")
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer()
                            Stepper("", value: $goalManager.goalDays, in: 7...365, step: 1)
                                .labelsHidden()
                                .fixedSize()
                        }

                        Text("현재 \(goalManager.goalDays)일 연속 기록을 목표로 하고 있습니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                }

                // 알림 설정
                Section(header: Text("알림 설정")) {
                    Toggle("식사 시간 알림", isOn: Binding(
                        get: { notificationManager.notificationsEnabled },
                        set: { newValue in
                            if newValue {
                                notificationManager.requestAuthorization { granted in
                                    if granted {
                                        notificationManager.scheduleMealNotifications()
                                    }
                                }
                            } else {
                                notificationManager.disableNotifications()
                            }
                        }
                    ))

                    if notificationManager.notificationsEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("알림 시간")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)

                            // 아침 알림 시간
                            HStack {
                                Text("🌅 아침")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Spacer()
                                DatePicker("", selection: $notificationManager.breakfastTime, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .fixedSize()
                            }

                            Divider()

                            // 점심 알림 시간
                            HStack {
                                Text("☀️ 점심")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Spacer()
                                DatePicker("", selection: $notificationManager.lunchTime, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .fixedSize()
                            }

                            Divider()

                            // 저녁 알림 시간
                            HStack {
                                Text("🌙 저녁")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Spacer()
                                DatePicker("", selection: $notificationManager.dinnerTime, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .fixedSize()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // 정보
                Section(header: Text("정보")) {
                    HStack {
                        Text("버전")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// 날짜별 섹션 뷰 (한 줄 형태)
struct DailySectionView: View {
    let date: Date
    @ObservedObject var mealStore: MealRecordStore

    private var isToday: Bool {
        Calendar.current.isDate(date, inSameDayAs: Date())
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")

        if isToday {
            formatter.dateFormat = "MM월 dd일 (E)"
        } else {
            formatter.dateFormat = "MM월 dd일 (E)"
        }
        return formatter.string(from: date)
    }

    private var completionRate: Double {
        let meals = mealStore.getMeals(for: date)
        let recordedCount = meals.values.filter { $0.isComplete }.count
        return Double(recordedCount) / 3.0
    }

    var body: some View {
        // getMeals 호출을 한 번만 하도록 캐싱
        let meals = mealStore.getMeals(for: date)

        let screenWidth = UIScreen.main.bounds.width
        let horizontalPadding: CGFloat = 16 // 좌우 8씩
        let cardPadding: CGFloat = 8 // 카드 안쪽 패딩
        let spacing: CGFloat = 6
        let availableWidth = screenWidth - horizontalPadding - (cardPadding * 2) - (spacing * 2)
        let photoSize = availableWidth / 3 // 3등분
        let cellHeight = photoSize + (cardPadding * 2) + 4 // 사진 + 패딩 + 여유

        VStack(spacing: 4) {
            // "오늘" 뱃지 (오늘 날짜일 때만)
            if isToday {
                HStack {
                    Text("오늘")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue)
                        .cornerRadius(8)
                    Spacer()
                }
                .padding(.horizontal, 8)
            }

            HStack(spacing: spacing) {
                // 3개 식사 사진 (아침, 점심, 저녁)
                ForEach(Array(MealType.allCases.enumerated()), id: \.element) { index, mealType in
                    ZStack(alignment: .topLeading) {
                        MealPhotoView(
                            date: date,
                            mealType: mealType,
                            mealRecord: meals[mealType],
                            mealStore: mealStore,
                            isToday: isToday,
                            photoSize: photoSize
                        )

                        // 첫 번째 사진(아침)에만 날짜 오버레이
                        if index == 0 {
                            Text(dateString)
                                .font(.system(size: 15, weight: isToday ? .bold : .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .padding(8)
                        }
                    }
                    .frame(width: photoSize, height: photoSize)
                }
            }
            .padding(cardPadding)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isToday ? Color.blue.opacity(0.05) : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isToday ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 2)
            )
            .frame(height: cellHeight)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}

// 식사 사진 뷰 (컴팩트한 정사각형)
struct MealPhotoView: View {
    let date: Date
    let mealType: MealType
    let mealRecord: MealRecord?
    @ObservedObject var mealStore: MealRecordStore
    let isToday: Bool
    let photoSize: CGFloat

    @State private var showingCameraPicker = false // 이미지 없을 때
    @State private var showingPhotoDetail = false // 이미지 있을 때
    @State private var selectedImage: UIImage?
    @State private var selectedPhotoType: PhotoType = .before // 식전/식후 선택

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

    var body: some View {
        // 기본 배경 (항상 고정 크기)
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.clear)
            .frame(width: photoSize, height: photoSize)
            .overlay(
                Group {
                    if let record = mealRecord, let imageData = record.thumbnailImageData, let uiImage = UIImage(data: imageData) {
                        // 사진이 있을 때
                        ZStack {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: photoSize, height: photoSize)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            // 뱃지들 (하단에 배치)
                            VStack {
                                Spacer()
                                HStack(alignment: .bottom) {
                                    // 메모 아이콘 (왼쪽 하단)
                                    if record.memo != nil && !record.memo!.isEmpty {
                                        Image(systemName: "note.text")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white)
                                            .frame(width: 26, height: 26)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(Circle())
                                    }

                                    Spacer()

                                    // 식전/식후 개수 뱃지 (오른쪽 하단)
                                    if record.beforeImageData != nil && record.afterImageData != nil {
                                        Text("2")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 26, height: 26)
                                            .background(Color.green)
                                            .clipShape(Circle())
                                    }
                                }
                                .padding(6)
                            }
                            .frame(width: photoSize, height: photoSize)
                        }
                    } else {
                        // 사진이 없을 때
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isFutureDate ? Color(.systemGray5) : Color(.systemGray6))
                            .overlay {
                                VStack(spacing: 6) {
                                    if isCurrentMeal {
                                        // 현재 시간대 식사 - 애니메이션 적용
                                        PulsingSymbolView(
                                            symbolName: mealType.symbolName,
                                            color: mealType.symbolColor,
                                            size: min(photoSize * 0.4, 36)
                                        )
                                    } else {
                                        // 일반 심볼
                                        Image(systemName: mealType.symbolName)
                                            .font(.system(size: min(photoSize * 0.4, 36)))
                                            .foregroundColor(isFutureDate ? .gray : mealType.symbolColor)
                                    }
                                    if !isFutureDate {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: min(photoSize * 0.25, 18)))
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                    }
                }
            )
        .onTapGesture {
            // 미래 날짜가 아닐 때만 화면 표시
            if !isFutureDate {
                if mealRecord != nil {
                    // 사진이 있으면 상세 보기
                    showingPhotoDetail = true
                } else {
                    // 사진이 없으면 카메라/앨범 선택
                    showingCameraPicker = true
                }
            }
        }
        .sheet(isPresented: $showingCameraPicker) {
            CameraPickerView(
                date: date,
                mealType: mealType,
                mealStore: mealStore,
                selectedPhotoType: $selectedPhotoType
            )
        }
        .sheet(isPresented: $showingPhotoDetail) {
            PhotoDetailView(
                date: date,
                mealType: mealType,
                mealRecord: mealRecord,
                mealStore: mealStore
            )
        }
    }
}

// 펄스 애니메이션이 적용된 심볼 뷰
struct PulsingSymbolView: View {
    let symbolName: String
    let color: Color
    let size: CGFloat

    @State private var isAnimating = false

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size))
            .foregroundColor(color)
            .scaleEffect(isAnimating ? 1.2 : 1.0)
            .opacity(isAnimating ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear {
                isAnimating = true
            }
    }
}

// 카메라/앨범 선택 화면
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
        self._localPhotoType = State(initialValue: selectedPhotoType.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 상단 헤더
            HStack {
                Button("취소") {
                    dismiss()
                }
                .font(.system(size: 17))
                .padding()

                Spacer()

                // 식전/식후 선택 Picker
                Picker("", selection: $localPhotoType) {
                    Text("식전").tag(MealPhotoView.PhotoType.before)
                    Text("식후").tag(MealPhotoView.PhotoType.after)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)

                Spacer()

                // 균형을 위한 투명 버튼
                Button("취소") {
                    dismiss()
                }
                .font(.system(size: 17))
                .padding()
                .opacity(0)
            }
            .background(Color(.systemBackground))

            // 메인 컨텐츠
            TabView(selection: $selectedTab) {
                // 카메라 탭
                CustomCameraView(selectedImage: $selectedImage)
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
                dismiss()
            }
        }
        .onChange(of: localPhotoType) { oldValue, newValue in
            selectedPhotoType = newValue
        }
    }
}

// 사진 상세보기 화면
struct PhotoDetailView: View {
    let date: Date
    let mealType: MealType
    let mealRecord: MealRecord?
    @ObservedObject var mealStore: MealRecordStore
    @Environment(\.dismiss) var dismiss

    @State private var currentPage = 0 // 0: 식전, 1: 식후
    @State private var showingMemoEditor = false
    @State private var showingDeleteAlert = false
    @State private var showingAddPhotoSheet = false
    @State private var selectedPhotoType: MealPhotoView.PhotoType = .before

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if let record = mealRecord {
                    // 사진 영역
                    TabView(selection: $currentPage) {
                        // 식전 사진
                        if let beforeData = record.beforeImageData, let beforeImage = UIImage(data: beforeData) {
                            Image(uiImage: beforeImage)
                                .resizable()
                                .scaledToFit()
                                .tag(0)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "photo")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
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
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "photo")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
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

                    // 정보 영역
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: mealType.symbolName)
                                .foregroundColor(mealType.symbolColor)
                                .font(.system(size: 24))
                            Text(mealType.rawValue)
                                .font(.system(size: 24, weight: .bold))
                            Text(currentPage == 0 ? "식전" : "식후")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.secondary)
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
                    }
                    .padding()
                    .background(Color(.systemBackground))
                }
            }
            .navigationTitle(dateFormatter.string(from: date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("닫기") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
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
                }
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
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter
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
struct CustomCameraView: View {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    @State private var capturedImage: UIImage?
    @State private var showingPreview = false
    @State private var cameraManager = CameraManager()
    @State private var currentDateTime = Date()

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        if showingPreview, let image = capturedImage {
            // 미리보기 화면
            PreviewView(
                image: image,
                onRetake: {
                    showingPreview = false
                    capturedImage = nil
                },
                onConfirm: {
                    // 이미 날짜/시간이 추가된 이미지 사용
                    selectedImage = image

                    // 사진을 "RoutineCamera" 앨범에 저장
                    saveImageToAlbum(image)

                    dismiss()
                }
            )
        } else {
            // 카메라 화면
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // 상단 정사각형 카메라 프리뷰
                    ZStack {
                        CameraPreview(cameraManager: cameraManager)

                        // 날짜/시간 오버레이
                        VStack {
                            Spacer()

                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(dateString)
                                        .font(.system(size: min(geometry.size.width * 0.06, 24), weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(color: .black, radius: 3, x: 0, y: 0)
                                        .shadow(color: .black, radius: 3, x: 0, y: 0)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)

                                    Text(timeString)
                                        .font(.system(size: min(geometry.size.width * 0.06, 24), weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(color: .black, radius: 3, x: 0, y: 0)
                                        .shadow(color: .black, radius: 3, x: 0, y: 0)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                }
                                .padding(.leading, min(geometry.size.width * 0.08, 30))
                                .padding(.bottom, min(geometry.size.width * 0.08, 30))

                                Spacer()
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.width)
                    .clipped()

                    Spacer()

                    // 하단 컨트롤
                    HStack {
                        // 취소 버튼
                        Button("취소") {
                            dismiss()
                        }
                        .foregroundColor(.white)
                        .frame(width: 60)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                        Spacer()

                        // 셔터 버튼
                        Button(action: capturePhoto) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: min(geometry.size.width * 0.2, 80), height: min(geometry.size.width * 0.2, 80))
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray, lineWidth: 2)
                                        .padding(5)
                                )
                        }

                        Spacer()

                        // 빈 공간 (대칭을 위해)
                        Color.clear.frame(width: 60)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 50)
                }
                .background(Color.black)
            }
            .ignoresSafeArea()
            .onReceive(timer) { _ in
                currentDateTime = Date()
            }
            .onDisappear {
                cameraManager.stopSession()
            }
        }
    }

    var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 MM월 dd일 EEEE"
        return formatter.string(from: currentDateTime)
    }

    var timeString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: currentDateTime)
    }
    
    private func capturePhoto() {
        // 카메라에서 사진 캡처
        cameraManager.capturePhoto { image in
            DispatchQueue.main.async {
                // 캡처 즉시 날짜/시간 추가
                if let image = image {
                    self.capturedImage = self.addDateTimeToImage(image)
                }
                self.showingPreview = true
            }
        }
    }
    
    // 이미지를 RoutineCamera 앨범에 저장
    private func saveImageToAlbum(_ image: UIImage) {
        // 사진 라이브러리 접근 권한 확인
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                print("사진 라이브러리 접근 권한이 없습니다.")
                return
            }
            
            // 먼저 앨범이 있는지 확인
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "title = %@", "RoutineCamera")
            let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
            
            if let album = collection.firstObject {
                // 기존 앨범에 이미지 추가
                PHPhotoLibrary.shared().performChanges({
                    let assetRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
                    let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                    albumChangeRequest?.addAssets([assetRequest.placeholderForCreatedAsset!] as NSArray)
                }) { success, error in
                    if success {
                        print("이미지가 RoutineCamera 앨범에 저장되었습니다.")
                    } else {
                        print("이미지 저장 실패: \(error?.localizedDescription ?? "알 수 없는 오류")")
                    }
                }
            } else {
                // 새 앨범 생성
                var albumPlaceholder: PHObjectPlaceholder?
                PHPhotoLibrary.shared().performChanges({
                    let createAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "RoutineCamera")
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
                                if success {
                                    print("이미지가 새로 생성된 RoutineCamera 앨범에 저장되었습니다.")
                                } else {
                                    print("새 앨범에 이미지 저장 실패: \(error?.localizedDescription ?? "알 수 없는 오류")")
                                }
                            }
                        }
                    } else {
                        print("앨범 생성 실패: \(error?.localizedDescription ?? "알 수 없는 오류")")
                    }
                }
            }
        }
    }
    
    // 이미지에 날짜와 시간을 추가하는 함수
    private func addDateTimeToImage(_ image: UIImage) -> UIImage {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ko_KR")

        // 날짜 포맷 (년 월 일 요일)
        dateFormatter.dateFormat = "yyyy년 MM월 dd일 EEEE"
        let dateString = dateFormatter.string(from: now)

        // 시간 포맷
        dateFormatter.dateFormat = "HH:mm:ss"
        let timeString = dateFormatter.string(from: now)

        // 이미지에 텍스트 추가
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)

        // 원본 이미지 그리기
        image.draw(in: CGRect(origin: CGPoint.zero, size: image.size))

        // 텍스트 속성 설정 (프리뷰와 동일하게)
        let fontSize = min(image.size.width, image.size.height) * 0.06
        let font = UIFont.boldSystemFont(ofSize: fontSize)

        let textAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white,
            .font: font
        ]

        // 텍스트 크기 계산
        let dateSize = dateString.size(withAttributes: textAttributes)
        let timeSize = timeString.size(withAttributes: textAttributes)

        // 텍스트 위치 계산 (왼쪽 아래) - 이미지 크기에 비례하도록 margin 계산
        let margin = min(image.size.width, image.size.height) * 0.08
        let lineSpacing: CGFloat = 6
        let dateRect = CGRect(
            x: margin,
            y: image.size.height - dateSize.height - timeSize.height - lineSpacing - margin,
            width: dateSize.width,
            height: dateSize.height
        )

        let timeRect = CGRect(
            x: margin,
            y: image.size.height - timeSize.height - margin,
            width: timeSize.width,
            height: timeSize.height
        )

        // Context의 그림자 설정 (프리뷰와 동일한 shadow 효과)
        guard let context = UIGraphicsGetCurrentContext() else {
            return image
        }

        // 그림자 효과 적용 (프리뷰의 두 번 shadow와 동일)
        context.setShadow(offset: CGSize(width: 0, height: 0), blur: 3, color: UIColor.black.cgColor)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        // 흰색 텍스트 그리기
        dateString.draw(in: dateRect, withAttributes: textAttributes)
        timeString.draw(in: timeRect, withAttributes: textAttributes)

        // 최종 이미지 생성
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage ?? image
    }
}

// 미리보기 화면
struct PreviewView: View {
    let image: UIImage
    let onRetake: () -> Void
    let onConfirm: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                // 이미지 미리보기
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .aspectRatio(1, contentMode: .fit)
                    .cornerRadius(12)
                    .padding()
                
                Spacer()
                
                HStack(spacing: 20) {
                    // 다시 찍기 버튼
                    Button("다시 찍기") {
                        onRetake()
                    }
                    .font(.title3)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                    // 확인 버튼
                    Button("사용하기") {
                        onConfirm()
                    }
                    .font(.title3)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
            }
        }
    }
}
import Combine

// 카메라 매니저
class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()
    
    let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var captureCompletion: ((UIImage?) -> Void)?
    private var isSessionRunning = false
    
    override init() {
        super.init()
        setupCamera()
    }
    
    private func setupCamera() {
        captureSession.sessionPreset = .photo
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("카메라를 찾을 수 없습니다.")
            return
        }
        
        do {
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            
            if captureSession.canAddInput(cameraInput) {
                captureSession.addInput(cameraInput)
            }
            
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            }
            
            // 정사각형 출력을 위한 설정
            photoOutput.isHighResolutionCaptureEnabled = true
            
        } catch {
            print("카메라 설정 오류: \(error)")
        }
    }
    
    func startSession() {
        guard !isSessionRunning else { return }
        
        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = true
            }
        }
    }
    
    func stopSession() {
        guard isSessionRunning else { return }
        
        DispatchQueue.global(qos: .background).async {
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }
    
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        captureCompletion = completion
        
        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = true
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            captureCompletion?(nil)
            return
        }
        
        // 1:1 비율로 크롭
        let croppedImage = cropToSquare(image: image)
        captureCompletion?(croppedImage)
    }
    
    private func cropToSquare(image: UIImage) -> UIImage {
        // CGImage를 사용하여 정확하게 크롭
        guard let cgImage = image.cgImage else { return image }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let minDimension = min(width, height)

        // 중앙에서 정사각형 크롭
        let cropRect = CGRect(
            x: (width - minDimension) / 2,
            y: (height - minDimension) / 2,
            width: minDimension,
            height: minDimension
        )

        // CGImage로 크롭
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return image }

        // 원본 이미지의 orientation을 유지하여 UIImage 생성
        let croppedImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)

        return croppedImage
    }
}

// 카메라 프리뷰
struct CameraPreview: UIViewRepresentable {
    let cameraManager: CameraManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.clipsToBounds = true

        let previewLayer = AVCaptureVideoPreviewLayer(session: cameraManager.captureSession)
        previewLayer.videoGravity = .resizeAspectFill

        view.layer.addSublayer(previewLayer)

        DispatchQueue.main.async {
            cameraManager.startSession()
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            DispatchQueue.main.async {
                // 정사각형 뷰에 맞춰서 프리뷰 레이어를 설정
                // resizeAspectFill을 사용하여 캡처와 동일한 중앙 크롭 효과
                previewLayer.frame = uiView.bounds
            }
        }
    }
}

// ImagePicker wrapper for UIImagePickerController (사진 보관함용)
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    let sourceType: UIImagePickerController.SourceType
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        picker.allowsEditing = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.selectedImage = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.selectedImage = originalImage
            }
            
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

#Preview {
    ContentView()
}

