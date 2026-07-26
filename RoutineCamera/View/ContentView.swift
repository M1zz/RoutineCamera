//
//  ContentView.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/11/25.
//

import SwiftUI
import AVFoundation
import Photos
import LeeoKit

struct ContentView: View {
    @StateObject private var mealStore = MealRecordStore.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var goalManager = GoalManager.shared
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var friendManager = FriendManager.shared
    @State private var showingSettings = false
    @State private var showingFriends = false
    @State private var showingStatistics = false
    @State private var showingGoalAchieved = false
    @State private var showingCaredMealsPrompt = false // 첫 실행: 챙길 식사 물어보기
    @State private var autoOpenMealType: MealType? = nil // 자동으로 열 식사 타입
    @State private var autoOpenPhotoType: MealPhotoView.PhotoType = .before // 자동으로 열 사진 타입

    // 오늘 날짜와 날짜 리스트 초기화
    @State private var todayDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var dateList: [Date] = []
    @State private var loadedPastDays = 30 // 로드된 과거 일수
    @State private var isLoadingPast = false // 과거 날짜 로딩 중인지
    @State private var scrollToTodayTrigger = false // 오늘 날짜로 스크롤 트리거
    @State private var currentVisibleDate: Date = Calendar.current.startOfDay(for: Date()) // 현재 보이는 날짜

    // 보이스오버 커스텀 로터용 네임스페이스
    @Namespace private var rotorNamespace

    // 한글 날짜 라벨 (로터 항목 낭독용)
    private func rotorDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: date)
    }

    // 거른 날 목록 (과거 + 필수 끼니 미기록) — "거른 날" 로터에 사용
    private var missedDates: [Date] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startDay = calendar.startOfDay(for: mealStore.startDate)
        let isExerciseMode = SettingsManager.shared.albumType == .exercise
        return dateList.filter { date in
            guard date < startOfToday, date >= startDay else { return false }
            let meals = mealStore.getMeals(for: date)
            if isExerciseMode {
                return meals[.breakfast] == nil
            } else {
                return MealType.allCases.contains { !$0.isSnack && meals[$0] == nil }
            }
        }
    }

    private func initializeDateList() {
        print("📅 [ContentView] 날짜 리스트 초기화 시작")
        let calendar = Calendar.current
        todayDate = calendar.startOfDay(for: Date())

        // 항상 최소 7일의 과거 날짜 표시 (과거 기록 가능하도록)
        loadedPastDays = 7
        dateList = ((-loadedPastDays)...0).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: todayDate)
        }.reversed() // 최신순 정렬 (오늘 -> 과거)
        print("📅 [ContentView] 날짜 리스트 초기화 완료: \(dateList.count)개 날짜 로드 (최신순)")
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
        }.reversed() // 최신순 정렬
        dateList = dateList + additionalDates // 배열 끝에 추가 (과거 방향)
        loadedPastDays = newPastDays
        print("⬆️ [ContentView] 과거 날짜 추가 완료: \(oldCount)개 → \(dateList.count)개")

        // 로딩 완료 후 플래그 해제
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isLoadingPast = false
        }
    }

    // 식사 시간이 지났는데 아직 기록하지 않은 가장 최근 끼니 (기록 유도 배너용, 식단 모드 전용)
    // 카메라를 강제로 열지 않고, 배너를 탭했을 때만 연다
    private var pendingMealType: MealType? {
        guard settingsManager.autoOpenCamera, settingsManager.albumType == .diet else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let currentMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let todayMeals = mealStore.getMeals(for: calendar.startOfDay(for: now))

        func minutes(of time: Date) -> Int {
            calendar.component(.hour, from: time) * 60 + calendar.component(.minute, from: time)
        }

        if currentMinutes >= minutes(of: notificationManager.dinnerTime), todayMeals[.dinner] == nil {
            return .dinner
        }
        if currentMinutes >= minutes(of: notificationManager.lunchTime), todayMeals[.lunch] == nil {
            return .lunch
        }
        if currentMinutes >= minutes(of: notificationManager.breakfastTime), todayMeals[.breakfast] == nil {
            return .breakfast
        }
        return nil
    }

    // 네이티브 내비게이션 바 타이틀
    private var navTitle: String {
        if settingsManager.useMomentsFeed {
            return settingsManager.albumType == .exercise ? "운동" : "식단"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E)"
        return f.string(from: currentVisibleDate)
    }

    // 내비게이션 바 트레일링: 모드 전환 + 통계/친구/설정 메뉴
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if settingsManager.showAlbumSwitcher {
                Button {
                    withAnimation {
                        settingsManager.albumType = settingsManager.albumType == .diet ? .exercise : .diet
                    }
                } label: {
                    Label(settingsManager.albumType.rawValue, systemImage: settingsManager.albumType.symbolName)
                }
            }
            Menu {
                Button { showingStatistics = true } label: { Label("통계", systemImage: "chart.bar.fill") }
                Button { showingFriends = true } label: { Label("친구", systemImage: "person.2.fill") }
                Button { showingSettings = true } label: { Label("설정", systemImage: "gearshape.fill") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // 목표 진행률 바 (켠 경우에만, 네이티브 바 아래 얇게)
    @ViewBuilder
    private var goalProgressBar: some View {
        if goalManager.goalEnabled {
            let recordedDays = mealStore.getTotalRecordedDays()
            let progress = goalManager.getProgress(currentStreak: recordedDays)
            let achieved = goalManager.isGoalAchieved(currentStreak: recordedDays)
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5)).frame(height: 6)
                        Capsule().fill(achieved ? Color.green : Color.blue)
                            .frame(width: geo.size.width * CGFloat(progress), height: 6)
                    }
                }
                .frame(height: 6)
                Text("\(recordedDays)/\(goalManager.goalDays)일")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("목표 진행률")
            .accessibilityValue("\(goalManager.goalDays)일 목표 중 \(recordedDays)일 기록")
        }
    }

    var body: some View {
        NavigationStack {
        ScrollViewReader { proxy in
            ZStack {
                // 배경색 (safe area까지 확장)
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                // 메인 콘텐츠 (상단은 네이티브 내비게이션 바)
                VStack(spacing: 0) {
                    // 기록 유도 배너: 식사 시간이 지났는데 미기록이면 표시 (격자 모드에서만)
                    if !settingsManager.useMomentsFeed, let pending = pendingMealType {
                        RecordNowBanner(mealType: pending) {
                            autoOpenPhotoType = .before
                            autoOpenMealType = pending
                        }
                    }

                    if settingsManager.useMomentsFeed {
                        // 순간 컬렉션 피드 (슬롯 없는 사진 일기)
                        MomentsView(mealStore: mealStore)
                    } else {
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: []) {
                            ForEach(dateList, id: \.self) { date in
                                DailySectionView(
                                    date: date,
                                    mealStore: mealStore
                                )
                                .id(date)
                                .accessibilityRotorEntry(id: date, in: rotorNamespace)
                                .background(
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: DatePositionPreferenceKey.self,
                                            value: [date: geometry.frame(in: .named("scroll")).minY]
                                        )
                                    }
                                )
                                .onAppear {
                                    // 마지막 날짜(가장 과거)가 보이면 더 과거 날짜 로드
                                    if date == dateList.last && loadedPastDays > 0 {
                                        loadMorePastDates()
                                    }
                                }
                            }
                        }
                        .onPreferenceChange(DatePositionPreferenceKey.self) { positions in
                            // 최상단에 가장 가까운 날짜 찾기 (Y 값이 0에 가까운 것)
                            if let topDate = positions.min(by: { abs($0.value) < abs($1.value) })?.key {
                                if currentVisibleDate != topDate {
                                    currentVisibleDate = topDate
                                }
                            }
                        }
                    }
                    .coordinateSpace(name: "scroll")
                    // 보이스오버 커스텀 로터: 긴 스크롤에서 바로 점프
                    .modifier(MealListRotors(
                        todayDate: todayDate,
                        missedDates: missedDates,
                        namespace: rotorNamespace,
                        dateLabel: rotorDateLabel
                    ))
                    .onChange(of: scrollToTodayTrigger) { _, _ in
                        // 설정 창에서 돌아올 때 오늘 날짜로 스크롤
                        withAnimation {
                            proxy.scrollTo(todayDate, anchor: .top)
                        }
                    }
                    } // end else (격자 모드)
                }
                .zIndex(0)
                .onAppear {
                    #if DEBUG
                    // UI 검증용: 환경변수로 카메라 시트 자동 오픈 (시뮬레이터 스크린샷 검증에 사용)
                    if ProcessInfo.processInfo.environment["OPEN_CAMERA_SHEET_FOR_TEST"] == "1" {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            autoOpenMealType = .lunch
                        }
                    }
                    #endif

                    // 날짜 리스트 초기화
                    if dateList.isEmpty {
                        initializeDateList()

                        // 즉시 오늘 날짜로 스크롤 (딜레이 없이)
                        DispatchQueue.main.async {
                            proxy.scrollTo(todayDate, anchor: .top)
                        }

                        // 알림 상태 갱신 (dateList 초기화와 스크롤이 완료된 후)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            // 날짜 변경 확인 및 알림 재설정
                            self.notificationManager.checkAndRescheduleIfNeeded()

                            // 오늘 식사 기록 확인 후 알림 업데이트
                            let todayMeals = self.mealStore.getMeals(for: self.todayDate)
                            self.notificationManager.updateNotificationsBasedOnRecords(meals: todayMeals)
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

                    // 첫 실행: "챙길 식사"를 아직 안 골랐으면 물어보기 (삼시세끼 전부 알림 스트레스 완화)
                    if !settingsManager.hasConfiguredCaredMeals {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            showingCaredMealsPrompt = true
                        }
                    }
                }

                // 과거를 보고 있을 때 오늘로 바로 돌아가는 플로팅 버튼 (격자 모드 전용)
                if !settingsManager.useMomentsFeed && !Calendar.current.isDate(currentVisibleDate, inSameDayAs: todayDate) {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                withAnimation {
                                    proxy.scrollTo(todayDate, anchor: .top)
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("오늘")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Color.blue))
                                .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, 24)
                            .accessibilityLabel("오늘로 이동")
                            .accessibilityHint("두 번 탭하여 오늘 날짜로 스크롤")
                        }
                    }
                    .zIndex(1)
                    .transition(.opacity)
                }
            }
            .safeAreaInset(edge: .top) { goalProgressBar }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .animation(.easeInOut(duration: 0.2), value: Calendar.current.isDate(currentVisibleDate, inSameDayAs: todayDate))
            .sheet(isPresented: $showingSettings) {
                SettingsView(notificationManager: notificationManager, goalManager: goalManager, mealStore: mealStore, settingsManager: settingsManager)
            }
            .sheet(isPresented: $showingFriends) {
                FriendsView()
            }
            .onChange(of: showingSettings) { oldValue, newValue in
                // 설정 창이 닫힐 때 dateList 재초기화
                if oldValue == true && newValue == false {
                    // 상태 초기화
                    isLoadingPast = false
                    dateList = []

                    // 다시 초기화
                    DispatchQueue.main.async {
                        initializeDateList()
                        // dateList가 업데이트된 후 스크롤 (약간의 딜레이)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            scrollToTodayTrigger.toggle()
                        }
                    }
                }
            }
            .onChange(of: settingsManager.albumType) { oldType, newType in
                print("🔄 [AlbumType] 변경됨: \(oldType.rawValue) → \(newType.rawValue)")
                // UI 업데이트만 트리거 (날짜 리스트는 유지)
                // mealStore.records가 자동으로 변경되므로 별도 처리 불필요
            }
            .onChange(of: dateList.count) { oldCount, newCount in
                // dateList가 초기화된 직후 스크롤
                if oldCount == 0 && newCount > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToTodayTrigger.toggle()
                    }
                }
            }
            .sheet(isPresented: $showingStatistics) {
                StatisticsView(mealStore: mealStore)
            }
            .sheet(isPresented: $showingCaredMealsPrompt) {
                CaredMealsPromptView()
            }
            .sheet(item: $autoOpenMealType, onDismiss: {
                // sheet가 닫힐 때 상태 리셋
                print("📸 [AutoCamera] Sheet 닫힘 - 상태 리셋")
            }) { mealType in
                CameraPickerView(
                    date: todayDate,
                    mealType: mealType,
                    mealStore: mealStore,
                    selectedPhotoType: $autoOpenPhotoType
                )
                .onAppear {
                    print("📸 [AutoCamera] CameraPickerView 표시됨 - mealType: \(mealType.rawValue)")
                }
            }
        }
        }
    }
}

// 보이스오버 커스텀 로터 (타입 체크 부담 분리를 위해 별도 ViewModifier로 추출)
struct MealListRotors: ViewModifier {
    let todayDate: Date
    let missedDates: [Date]
    let namespace: Namespace.ID
    let dateLabel: (Date) -> String

    func body(content: Content) -> some View {
        content
            .accessibilityRotor("오늘") {
                AccessibilityRotorEntry(Text("오늘, \(dateLabel(todayDate))"), id: todayDate, in: namespace)
            }
            .accessibilityRotor("거른 날") {
                ForEach(missedDates, id: \.self) { date in
                    AccessibilityRotorEntry(Text(dateLabel(date)), id: date, in: namespace)
                }
            }
    }
}

// 기록 유도 배너: 식사 시간이 지났는데 미기록일 때 홈 상단에 표시.
// 카메라를 강제로 열지 않고, 탭했을 때만 연다.
struct RecordNowBanner: View {
    let mealType: MealType
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(mealType.rawValue) 기록할 시간이에요")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityLabel("\(mealType.rawValue) 기록할 시간이에요")
        .accessibilityHint("두 번 탭하여 카메라 열기")
    }
}

// 홈 상단 헤더: 날짜 · 오늘 뱃지 · (옵션) 모드 전환 · 통계/친구/설정
// 목표가 켜져 있으면 아래에 얇은 진행률 바 한 줄
struct ScrollOffsetPreferenceKey: PreferenceKey {
    typealias Value = CGFloat
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DatePositionPreferenceKey: PreferenceKey {
    typealias Value = [Date: CGFloat]

    static var defaultValue: [Date: CGFloat] = [:]

    static func reduce(value: inout [Date: CGFloat], nextValue: () -> [Date: CGFloat]) {
        value.merge(nextValue()) { (_, new) in new }
    }
}

// 날짜별 섹션 뷰 (한 줄 형태)
