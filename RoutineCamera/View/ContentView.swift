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

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                // 배경색 (safe area까지 확장)
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                // 메인 콘텐츠
                VStack(spacing: 0) {
                    // 상단 헤더 (날짜 · 모드 전환 · 통계/친구/설정 · 목표 진행률)
                    HomeHeaderView(
                        date: currentVisibleDate,
                        mealStore: mealStore,
                        goalManager: goalManager,
                        settingsManager: settingsManager,
                        onStatisticsTap: { showingStatistics = true },
                        onFriendsTap: { showingFriends = true },
                        onSettingsTap: { showingSettings = true },
                        onTodayTap: {
                            withAnimation {
                                proxy.scrollTo(todayDate, anchor: .top)
                            }
                        }
                    )

                    // 기록 유도 배너: 식사 시간이 지났는데 미기록이면 표시, 탭하면 카메라
                    if let pending = pendingMealType {
                        RecordNowBanner(mealType: pending) {
                            autoOpenPhotoType = .before
                            autoOpenMealType = pending
                        }
                    }

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
                }

                // 과거를 보고 있을 때 오늘로 바로 돌아가는 플로팅 버튼
                if !Calendar.current.isDate(currentVisibleDate, inSameDayAs: todayDate) {
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
struct HomeHeaderView: View {
    let date: Date // 현재 보이는 날짜
    @ObservedObject var mealStore: MealRecordStore
    @ObservedObject var goalManager: GoalManager
    @ObservedObject var settingsManager: SettingsManager
    let onStatisticsTap: () -> Void
    let onFriendsTap: () -> Void
    let onSettingsTap: () -> Void
    let onTodayTap: () -> Void

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter.string(from: date)
    }

    private var isToday: Bool {
        Calendar.current.isDate(date, inSameDayAs: Date())
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                // 날짜 (탭하면 오늘로 이동)
                HStack(spacing: 6) {
                    Text(dateString)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if isToday {
                        Text("오늘")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.blue))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onTodayTap() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("현재 \(dateString)\(isToday ? ", 오늘" : "")")
                .accessibilityHint("두 번 탭하여 오늘 날짜로 이동")
                .accessibilityAddTraits(.isButton)

                Spacer()

                // 앨범 타입 전환 (설정에서 켠 경우에만)
                if settingsManager.showAlbumSwitcher {
                    Button(action: {
                        withAnimation {
                            settingsManager.albumType = settingsManager.albumType == .diet ? .exercise : .diet
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: settingsManager.albumType.symbolName)
                                .font(.system(size: 12))
                            Text(settingsManager.albumType.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(.systemGray6)))
                    }
                    .accessibilityLabel("기록 모드 전환")
                    .accessibilityValue("현재 \(settingsManager.albumType.rawValue) 모드")
                    .accessibilityHint("두 번 탭하여 \(settingsManager.albumType == .diet ? "운동" : "식단") 모드로 전환")
                }

                // 통계 버튼
                Button(action: onStatisticsTap) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 19))
                        .foregroundColor(.gray)
                }
                .accessibilityLabel("통계")
                .accessibilityHint("나의 기록 통계를 봅니다")

                // 친구 버튼
                Button(action: onFriendsTap) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 19))
                        .foregroundColor(.gray)
                }
                .accessibilityLabel("친구")
                .accessibilityHint("친구 목록과 친구의 기록을 봅니다")

                // 설정 버튼
                Button(action: onSettingsTap) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 19))
                        .foregroundColor(.gray)
                }
                .accessibilityLabel("설정")
            }

            // 목표 진행률 (켠 경우에만, 한 줄)
            if goalManager.goalEnabled {
                let currentStreak = mealStore.getCurrentStreak()
                let progress = goalManager.getProgress(currentStreak: currentStreak)
                let achieved = goalManager.isGoalAchieved(currentStreak: currentStreak)

                HStack(spacing: 10) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.systemGray5))
                                .frame(height: 6)

                            Capsule()
                                .fill(achieved ? Color.green : Color.blue)
                                .frame(width: geometry.size.width * CGFloat(progress), height: 6)
                        }
                    }
                    .frame(height: 6)

                    Text("\(currentStreak)/\(goalManager.goalDays)일")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("목표 진행률")
                .accessibilityValue("\(goalManager.goalDays)일 목표 중 \(currentStreak)일 연속 기록, \(Int((progress * 100).rounded()))퍼센트 달성\(achieved ? ", 목표 달성 완료" : "")")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .bottom)
    }
}

// 설정 화면
struct SettingsView: View {
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject var goalManager: GoalManager
    @ObservedObject var mealStore: MealRecordStore
    @ObservedObject var settingsManager: SettingsManager
    @Environment(\.dismiss) var dismiss
    @State private var showingSampleDataAlert = false
    @State private var showingClearDataAlert = false
    @State private var openAIAPIKey: String = UserDefaults.standard.string(forKey: "OpenAI_API_Key") ?? ""
    @State private var showingAPIKeyInfo = false

    // 앱 버전 정보
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationView {
            Form {
                // 앨범 전환 버튼 표시 설정
                Section(header: Text("헤더 설정")) {
                    Toggle("운동/식단 전환 버튼 표시", isOn: $settingsManager.showAlbumSwitcher)

                    Text("헤더에 운동/식단 전환 버튼을 표시합니다. 빠르게 앨범 타입을 전환하며 기록할 수 있습니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                // 앨범 타입 선택
                Section(header: Text("앨범 타입")) {
                    Picker("앨범 타입", selection: $settingsManager.albumType) {
                        ForEach(AlbumType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.symbolName)
                                Text(type.rawValue)
                            }
                            .tag(type)
                        }
                    }

                    Text(settingsManager.albumType == .diet
                        ? "식사 사진을 식전/식후로 나눠서 기록합니다. 식단과 운동은 완전히 별도로 저장되어 언제든지 전환하며 기록할 수 있습니다."
                        : "운동 사진을 하루에 1장씩 기록합니다. 식단과 운동은 완전히 별도로 저장되어 언제든지 전환하며 기록할 수 있습니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                }

                // 친구 공유 설정
                Section(header: Text("친구 공유")) {
                    Toggle("내 식단 공유 가능", isOn: $settingsManager.shareMealsToCloud)

                    Text("이 기능을 켜면 내 식단 데이터가 iCloud에 자동으로 업로드되어 친구가 내 식단을 볼 수 있습니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)

                    if settingsManager.shareMealsToCloud {
                        Text("✓ 식단 공유가 활성화되었습니다")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                #if DEBUG
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
                #endif

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
                    Toggle("식사 업로드 리마인드", isOn: Binding(
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

                    Text("식사 시간이 지났는데도 기록하지 않았을 때 알림을 보내드립니다. (식사 시간 + 2시간 후)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)

                    if notificationManager.notificationsEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("식사 시간 설정")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)

                            // 아침 식사 시간
                            HStack {
                                Text("🌅 아침 식사 시간")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Spacer()
                                DatePicker("", selection: $notificationManager.breakfastTime, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .fixedSize()
                            }

                            Divider()

                            // 점심 식사 시간
                            HStack {
                                Text("☀️ 점심 식사 시간")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Spacer()
                                DatePicker("", selection: $notificationManager.lunchTime, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .fixedSize()
                            }

                            Divider()

                            // 저녁 식사 시간
                            HStack {
                                Text("🌙 저녁 식사 시간")
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

                    Divider()
                        .padding(.vertical, 8)

                    Toggle("기록 시간 배너 표시", isOn: $settingsManager.autoOpenCamera)

                    Text("식사 시간이 지났는데 아직 기록하지 않았을 때 홈 화면 상단에 배너를 보여드립니다. 배너를 탭하면 바로 카메라가 열립니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                }

                // 사진 저장 설정
                Section(header: Text("사진 저장")) {
                    Toggle("자동으로 사진앱에 저장", isOn: $settingsManager.autoSaveToPhotoLibrary)
                    let albumName = settingsManager.albumType == .diet ? "세끼식단" : "세끼운동"
                    Text(settingsManager.autoSaveToPhotoLibrary
                        ? "사진을 촬영하면 자동으로 사진앱의 '\(albumName)' 앨범에 저장됩니다."
                        : "사진을 앱 내부에만 저장합니다. 상세보기에서 다운로드 버튼으로 사진앱에 저장할 수 있습니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                }

                // 표시 설정
                Section(header: Text("표시 설정")) {
                    // 식단 모드일 때만 간식 표시 옵션
                    if settingsManager.albumType == .diet {
                        Toggle("간식 보이기", isOn: $settingsManager.writeSnack)

                        Text(settingsManager.writeSnack
                            ? "메인 화면에 간식 칸을 표시합니다."
                            : "간식 칸을 숨깁니다. 이미 기록한 간식도 화면에서 가려지며, 기록은 삭제되지 않습니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                    }

                    // 식단 모드일 때만 남은 장수 표시 옵션
                    if settingsManager.albumType == .diet {
                        Toggle("식후 사진 알림 표시", isOn: $settingsManager.showRemainingPhotoCount)

                        Text(settingsManager.showRemainingPhotoCount
                            ? "사진이 1장만 입력되었을 때 빨간색 원에 1을 표시합니다."
                            : "식후 사진 알림을 표시하지 않습니다. 2장 중 1장만 입력해도 알림이 나타나지 않습니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                    }

                    Toggle("메모 아이콘 표시", isOn: $settingsManager.showMemoIcon)

                    Text("메모가 있는 식사에 메모 아이콘을 표시합니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                // 코인 및 구독
                Section(header: Text("분석 코인")) {
                    HStack {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundColor(.orange)
                        Text("보유 코인")
                        Spacer()
                        Text("\(CoinManager.shared.currentCoins)개")
                            .font(.headline)
                            .foregroundColor(.orange)
                    }

                    if CoinManager.shared.isSubscribed {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("구독 상태")
                            Spacer()
                            Text("활성")
                                .foregroundColor(.green)
                        }

                        if let daysLeft = CoinManager.shared.daysUntilNextRecharge() {
                            Text("다음 충전까지 \(daysLeft)일 남음")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button(action: {
                            // 구독 구매
                            Task {
                                if let product = await SubscriptionManager.shared.monthlyProduct {
                                    do {
                                        let success = try await SubscriptionManager.shared.purchase(product)
                                        if success {
                                            print("✅ 구독 구매 성공")
                                        }
                                    } catch {
                                        print("❌ 구독 구매 실패: \(error)")
                                    }
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: "cart.fill")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("월간 구독")
                                        .fontWeight(.semibold)
                                    Text("매달 99코인 충전")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("$2.00/월")
                                    .fontWeight(.bold)
                            }
                            .padding(.vertical, 8)
                        }

                        Button(action: {
                            Task {
                                await SubscriptionManager.shared.restorePurchases()
                            }
                        }) {
                            Text("구매 복원")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }

                    #if DEBUG
                    Divider()
                    Button("🧪 테스트 코인 +10") {
                        CoinManager.shared.addTestCoins(10)
                    }
                    Button("🔄 테스트용 초기화") {
                        CoinManager.shared.resetForTesting()
                    }
                    #endif

                    Text("• 1회 OpenAI 분석 = 1코인 차감\n• 월 $2 구독으로 매달 99코인 자동 충전")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                }

                // 무료 식단 분석
                Section(header: Text("무료 식단 분석")) {
                    HStack {
                        Image(systemName: "gift.fill")
                            .foregroundColor(settingsManager.freeAnalysisCount > 0 ? .green : .orange)
                        Text("잔여 무료 분석")
                        Spacer()
                        Text("\(settingsManager.freeAnalysisCount)회")
                            .font(.headline)
                            .foregroundColor(settingsManager.freeAnalysisCount > 0 ? .green : .orange)
                    }

                    Text("• Vision Framework 사용 (Apple 기본 제공)\n• 정확도: 중간 수준\n• 무료 분석 소진 시 OpenAI API 사용 (코인 필요)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                        .minimumScaleFactor(0.8)
                }

                // OpenAI API 설정
                Section(header: Text("고급 음식 인식 (OpenAI)")) {
                    HStack {
                        Image(systemName: OpenAIFoodAnalyzer.shared.isConfigured ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundColor(OpenAIFoodAnalyzer.shared.isConfigured ? .green : .orange)
                        Text("상태")
                        Spacer()
                        Text(OpenAIFoodAnalyzer.shared.isConfigured ? "설정됨" : "미설정")
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 8) {
                        SecureField("API 키 입력", text: $openAIAPIKey)
                            .textContentType(.password)
                            .autocapitalization(.none)

                        HStack(spacing: 12) {
                            // 저장 버튼
                            Button(action: {
                                OpenAIFoodAnalyzer.shared.setAPIKey(openAIAPIKey)
                            }) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("저장")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .disabled(openAIAPIKey.isEmpty)

                            // 삭제 버튼
                            if OpenAIFoodAnalyzer.shared.isConfigured {
                                Button(action: {
                                    openAIAPIKey = ""
                                    OpenAIFoodAnalyzer.shared.setAPIKey("")
                                }) {
                                    HStack {
                                        Image(systemName: "trash.fill")
                                        Text("삭제")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }

                    // 자동 분석 토글 (API 키 설정 시에만)
                    if OpenAIFoodAnalyzer.shared.isConfigured {
                        Toggle("사진 촬영 시 자동 분석", isOn: $settingsManager.autoFoodAnalysis)

                        Text(settingsManager.autoFoodAnalysis
                            ? "⚠️ 켜짐: 사진 촬영 시 자동으로 분석 (API 비용 발생)\n💰 월 약 $2.7~8.1 예상"
                            : "✅ 꺼짐: 필요할 때만 수동으로 분석 (API 비용 절약)")
                            .font(.caption)
                            .foregroundColor(settingsManager.autoFoodAnalysis ? .orange : .green)
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                    }

                    Button(action: {
                        showingAPIKeyInfo = true
                    }) {
                        HStack {
                            Image(systemName: "questionmark.circle")
                            Text("API 키 받는 방법")
                        }
                    }

                    Text("OpenAI Vision API를 사용하면 음식을 훨씬 더 정확하게 인식합니다. API 키가 설정되면 자동으로 OpenAI를 사용합니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                        .minimumScaleFactor(0.8)
                }
                .alert("OpenAI API 키 받는 방법", isPresented: $showingAPIKeyInfo) {
                    Button("확인", role: .cancel) { }
                } message: {
                    Text("""
                    1. https://platform.openai.com 접속
                    2. 로그인 후 API Keys 메뉴
                    3. "Create new secret key" 클릭
                    4. 생성된 키를 복사해서 붙여넣기

                    ⚠️ 주의사항:
                    - 결제 수단 등록 필수
                    - 최소 $5 이상 빌링 충전 필요
                    - 충전하지 않으면 API 키 비활성화됨

                    💰 비용:
                    - 이미지 분석 1회당 약 $0.01~0.03
                    - 하루 3회 분석 시 월 $2.7~8.1

                    💡 효율적 활용법:
                    - 자동 분석 OFF (필요할 때만 수동)
                    - 중요한 식사만 선택적으로 분석
                    - 반복되는 음식은 메모 복사 활용
                    """)
                }

                // 닉네임 설정
                Section(header: Text("프로필")) {
                    HStack {
                        Text("닉네임")
                        Spacer()
                        TextField("닉네임 입력", text: $settingsManager.nickname)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                    }

                    Text("친구에게 피드백을 남길 때 표시되는 이름입니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // 정보
                Section(header: Text("정보")) {
                    HStack {
                        Text("버전")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                }

                // 개발자 문의
                DeveloperContactSection()

                // 지원
                Section {
                    LeeoSupportSection<RoutineCameraSpec>()
                } header: {
                    Text("지원")
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

// MARK: - 개발자 문의
struct DeveloperContactSection: View {
    var body: some View {
        Section {
            Link(destination: URL(string: "mailto:leeo@kakao.com")!) {
                Label("이메일로 문의하기", systemImage: "envelope")
            }
            Link(destination: URL(string: "https://instagram.com/lee25_ios")!) {
                Label("인스타그램 DM (@lee25_ios)", systemImage: "paperplane")
            }
        } header: {
            Text("개발자에게 문의")
        } footer: {
            Text("버그 제보와 기능 제안을 환영합니다.")
        }
    }
}

// PreferenceKey for tracking row positions
// 스크롤 오프셋을 추적하기 위한 PreferenceKey
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
struct DailySectionView: View {
    let date: Date
    @ObservedObject var mealStore: MealRecordStore
    @ObservedObject private var settingsManager = SettingsManager.shared // "간식 보이기" 등 표시 설정 즉시 반영

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
        let meals = mealStore.getMeals(for: date)
        let isPastDate = date < Calendar.current.startOfDay(for: Date())
        let isExerciseMode = SettingsManager.shared.albumType == .exercise
        let layout = calculateLayout(isExerciseMode: isExerciseMode, cardCount: getMealsToShow(meals: meals).count)

        VStack(spacing: 4) {
            mealPhotosRow(
                meals: meals,
                isPastDate: isPastDate,
                isExerciseMode: isExerciseMode,
                photoSize: layout.photoSize,
                spacing: layout.spacing,
                cardPadding: layout.cardPadding,
                cellHeight: layout.cellHeight
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: DatePositionPreferenceKey.self,
                    value: [date: geometry.frame(in: .named("scrollView")).minY]
                )
            }
        )
    }

    // 간식이 입력되어 있는지 확인
    private func hasSnacks(meals: [MealType: MealRecord]) -> Bool {
        return (meals[.snack1]?.isComplete ?? false) ||
               (meals[.snack2]?.isComplete ?? false) ||
               (meals[.snack3]?.isComplete ?? false)
    }

    // 현재 시간대에 맞는 식사 타입 3개 반환 (오늘 날짜용)
    // 순서: 아침 - 간식1 - 점심 - 저녁 - 간식2
    private func getMealsForCurrentTimeSlot() -> [MealType] {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let currentMinutes = hour * 60 + minute

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

        // 현재 시간이 어느 시간대인지 판별
        if currentMinutes < lunchMinutes {
            // 아침 시간대: [아침, 간식1, 점심]
            return [.breakfast, .snack1, .lunch]
        } else if currentMinutes < dinnerMinutes {
            // 점심 시간대: [간식1, 점심, 간식2]
            return [.snack1, .lunch, .snack2]
        } else {
            // 저녁 시간대: [간식2, 저녁, 간식3]
            return [.snack2, .dinner, .snack3]
        }
    }

    // 동적 간식 칸 계산: "간식 보이기"가 꺼져 있으면 기록된 간식까지 모두 숨기고(오늘 행과 동일),
    // 켜져 있으면 기록된 간식 + 빈 간식 칸(기록 초대) 1개를 노출
    private func getSnacksToShow(meals: [MealType: MealRecord]) -> [MealType] {
        guard SettingsManager.shared.writeSnack else { return [] }

        var snacks: [MealType] = []

        for snack in [MealType.snack1, .snack2, .snack3] {
            if meals[snack]?.isComplete ?? false {
                snacks.append(snack)
            } else {
                snacks.append(snack)
                break
            }
        }

        return snacks
    }

    // 표시할 식사 타입 배열 반환
    private func getMealsToShow(meals: [MealType: MealRecord]) -> [MealType] {
        if isToday {
            // 오늘: 모든 식사 타입 표시 (스크롤 가능)
            if SettingsManager.shared.writeSnack {
                return [.breakfast, .snack1, .lunch, .snack2, .dinner, .snack3]
            } else {
                return [.breakfast, .lunch, .dinner]
            }
        } else {
            // 과거/미래: 아침 점심 저녁 + 동적 간식
            return [.breakfast, .lunch, .dinner] + getSnacksToShow(meals: meals)
        }
    }

    // 현재 시간대에 맞는 주요 식사 타입 반환 (스크롤 위치용)
    private func getCurrentPrimaryMeal() -> MealType {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let currentMinutes = hour * 60 + minute

        let notificationManager = NotificationManager.shared
        let lunchHour = calendar.component(.hour, from: notificationManager.lunchTime)
        let lunchMinute = calendar.component(.minute, from: notificationManager.lunchTime)
        let dinnerHour = calendar.component(.hour, from: notificationManager.dinnerTime)
        let dinnerMinute = calendar.component(.minute, from: notificationManager.dinnerTime)

        let lunchMinutes = lunchHour * 60 + lunchMinute
        let dinnerMinutes = dinnerHour * 60 + dinnerMinute

        // 현재 시간이 어느 시간대인지 판별
        if currentMinutes < lunchMinutes {
            return .breakfast
        } else if currentMinutes < dinnerMinutes {
            return .lunch
        } else {
            return .dinner
        }
    }

    private func calculateLayout(isExerciseMode: Bool, cardCount: Int) -> (photoSize: CGFloat, spacing: CGFloat, cardPadding: CGFloat, cellHeight: CGFloat) {
        let screenWidth = UIScreen.main.bounds.width
        let horizontalPadding: CGFloat = 16
        let cardPadding: CGFloat = 12 // 오늘 테두리와 사진 사이 여백 (8은 너무 타이트)
        let spacing: CGFloat = 4

        // 4칸 이상이면 3.35칸 기준으로 크기를 잡아 4번째 칸이 살짝 보이게 함
        // (가로로 더 스크롤할 수 있음을 시각적으로 암시)
        let photoCount: CGFloat
        if isExerciseMode {
            photoCount = 1
        } else if cardCount > 3 {
            photoCount = 3.35
        } else {
            photoCount = 3
        }
        let availableWidth = screenWidth - horizontalPadding - (cardPadding * 2) - (spacing * (photoCount - 1))
        let photoSize = availableWidth / photoCount
        let cellHeight = photoSize + (cardPadding * 2) + 4

        return (photoSize, spacing, cardPadding, cellHeight)
    }

    @ViewBuilder
    private func mealPhotosRow(
        meals: [MealType: MealRecord],
        isPastDate: Bool,
        isExerciseMode: Bool,
        photoSize: CGFloat,
        spacing: CGFloat,
        cardPadding: CGFloat,
        cellHeight: CGFloat
    ) -> some View {
        // 표시할 칸이 3개보다 많으면 ScrollView 사용 (과거 날짜 포함)
        let mealsToShow = getMealsToShow(meals: meals)
        let shouldUseScrollView = !isExerciseMode && mealsToShow.count > 3

        Group {
            if shouldUseScrollView {
                // 칸이 3개보다 많으면 ScrollView 사용 (오늘 날짜 및 과거 날짜 포함)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: spacing) {
                            dietModePhotos(meals: meals, isPastDate: isPastDate, photoSize: photoSize, spacing: spacing)
                        }
                        // 세로 패딩이 없으면 카드가 오늘 테두리 위아래에 딱 붙음
                        .padding(.horizontal, cardPadding)
                        .padding(.vertical, cardPadding)
                    }
                    .onAppear {
                        // 오늘 날짜인 경우에만 자동 스크롤
                        if isToday {
                            let currentMeal = getCurrentPrimaryMeal()
                            // 약간의 딜레이를 주어 레이아웃이 완료된 후 스크롤
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    proxy.scrollTo(currentMeal, anchor: .center)
                                }
                            }
                        }
                    }
                }
            } else {
                // 운동 모드 또는 3칸 이하 (3칸 고정)
                HStack(spacing: spacing) {
                    if isExerciseMode {
                        exerciseModePhoto(meals: meals, isPastDate: isPastDate, photoSize: photoSize)
                    } else {
                        dietModePhotos(meals: meals, isPastDate: isPastDate, photoSize: photoSize, spacing: spacing)
                    }
                }
                .padding(cardPadding)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isToday ? Color.blue.opacity(0.04) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isToday ? Color.blue.opacity(0.35) : Color.clear, lineWidth: 1.5)
        )
        .frame(height: cellHeight)
    }

    @ViewBuilder
    private func exerciseModePhoto(meals: [MealType: MealRecord], isPastDate: Bool, photoSize: CGFloat) -> some View {
        MealPhotoView(
            date: date,
            mealType: .breakfast,
            mealRecord: meals[.breakfast],
            mealStore: mealStore,
            isToday: isToday,
            photoSize: photoSize
        )
        .frame(width: photoSize, height: photoSize)
    }

    @ViewBuilder
    private func dietModePhotos(meals: [MealType: MealRecord], isPastDate: Bool, photoSize: CGFloat, spacing: CGFloat) -> some View {
        let mealsToShow = getMealsToShow(meals: meals)

        ForEach(mealsToShow, id: \.self) { mealType in
            MealPhotoView(
                date: date,
                mealType: mealType,
                mealRecord: meals[mealType],
                mealStore: mealStore,
                isToday: isToday,
                photoSize: photoSize
            )
            .frame(width: photoSize, height: photoSize)
            .id(mealType) // ScrollViewReader가 스크롤할 수 있도록 ID 추가
        }
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

    // 색 이중 인코딩: 색만으로 구분되던 상태를 테두리 '패턴'으로도 표현
    // 미기록·끊김 모두 동일한 회색 점선으로 조용히 안내 (빨강 강조 없음)
    @ViewBuilder
    private var stateBorderOverlay: some View {
        if isSoftMissed || isStreakBreakDay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    Color.gray.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                )
        }
    }

    // 빈 상태의 내용
    @ViewBuilder
    private var emptyStateContent: some View {
        VStack(spacing: 6) {
            mainSymbolView
            // 미래가 아닌 빈 칸은 모두 탭해서 기록할 수 있음을 +로 표시
            // 오늘·유예 기간은 파란색 초대, 과거는 회색으로 조용히
            if isToday || (isWithinGracePeriod && isPastDateMissed) {
                plusIcon(color: .blue)
            } else if !isFutureDate {
                plusIcon(color: Color.gray.opacity(0.45))
            }
        }
    }

    // 미기록/예정은 음소거 회색, 유예·일반은 초대하는 식사 색
    private var symbolColor: Color {
        if isFutureDate { return .gray }
        if isSoftMissed || isStreakBreakDay { return Color.gray.opacity(0.7) }
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
struct CameraPickerView: View {
    let date: Date
    let mealType: MealType
    @ObservedObject var mealStore: MealRecordStore
    @Binding var selectedPhotoType: MealPhotoView.PhotoType
    @Environment(\.dismiss) var dismiss

    @State private var selectedTab = 0 // 0: 카메라, 1: 사진앨범
    @State private var selectedImage: UIImage?
    @State private var localPhotoType: MealPhotoView.PhotoType
    @State private var recordWithoutPhoto = false // 사진 없이 기록 토글

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
                    if SettingsManager.shared.albumType == .diet && !recordWithoutPhoto {
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

                        // 완료 버튼 (사진 없이 기록일 때만 표시)
                        if recordWithoutPhoto {
                            Button("완료") {
                                mealStore.recordWithoutPhoto(date: date, mealType: mealType)
                                dismiss()
                            }
                            .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 52)

                // 사진 없이 기록 토글
                Toggle("사진 없이 기록", isOn: $recordWithoutPhoto)
                    .font(.system(size: 15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemBackground))

            // 메인 컨텐츠
            if recordWithoutPhoto {
                // 사진 없이 기록 모드
                VStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.green)
                        Text("사진 없이 기록")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("상단 완료 버튼을 눌러 기록하세요")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else {
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
        }
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: selectedImage) { oldValue, newValue in
            // 사진 없이 기록 모드가 아닐 때만 사진 저장
            if !recordWithoutPhoto, let image = newValue, let imageData = image.jpegData(compressionQuality: 0.8) {
                mealStore.addOrUpdateMeal(date: date, mealType: mealType, imageData: imageData, isBefore: localPhotoType == .before)

                // 식단 모드일 때 식전 사진만 자동으로 Vision 분석 실행
                if SettingsManager.shared.albumType == .diet && localPhotoType == .before {
                    autoAnalyzeFood(image: image, date: date, mealType: mealType)
                }

                dismiss()
            }
        }
        .onChange(of: localPhotoType) { oldValue, newValue in
            selectedPhotoType = newValue
        }
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
    @State private var showingSaveSuccessAlert = false
    @State private var showingSaveErrorAlert = false
    @State private var analyzingFood = false // 식단 분석 중
    @State private var analysisResult: FoodAnalysisResult? = nil // 분석 결과
    @State private var showingAnalysisResult = false // 결과 표시
    @State private var showFullAnalysis = false // 전체 분석 보기
    @State private var feedbacks: [MealFeedback] = [] // 받은 피드백 목록
    @State private var sentFeedbacks: [SentFeedback] = [] // 보낸 피드백 목록
    @State private var isLoadingFeedbacks = false // 피드백 로딩 중

    var body: some View {
        NavigationView {
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
                    Button("닫기") {
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
struct CustomCameraView: View {
    @Binding var selectedImage: UIImage?
    let isActive: Bool
    @Environment(\.dismiss) var dismiss
    @State private var capturedImage: UIImage?
    @State private var showingPreview = false
    @StateObject private var cameraManager = CameraManager()
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

                    // 설정에 따라 사진을 "세끼" 앨범에 저장
                    if SettingsManager.shared.autoSaveToPhotoLibrary {
                        saveImageToAlbum(image)
                    }

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
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        // 정사각형 촬영 프레임 경계 표시 (배경과 같은 검정이라 테두리로 구분)
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .padding(.top, 8)

                    Spacer()

                    // 셔터 버튼 (취소는 상단 헤더에 있으므로 여기서는 셔터만 중앙에)
                    Button(action: capturePhoto) {
                        ZStack {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 3.5)
                                .frame(width: shutterSize(geometry), height: shutterSize(geometry))

                            Circle()
                                .fill(Color.white)
                                .frame(width: shutterSize(geometry) - 14, height: shutterSize(geometry) - 14)
                        }
                    }
                    .accessibilityLabel("사진 촬영")

                    Spacer()
                }
                .background(Color.black)
            }
            .ignoresSafeArea()
            .onReceive(timer) { _ in
                currentDateTime = Date()
            }
            .onChange(of: isActive) { oldValue, newValue in
                if newValue {
                    // 카메라 탭으로 돌아올 때 세션 시작
                    print("📸 [CustomCameraView] 카메라 활성화 - 세션 시작")
                    cameraManager.startSession()
                } else {
                    // 다른 탭으로 이동할 때 세션 중지
                    print("📸 [CustomCameraView] 카메라 비활성화 - 세션 중지")
                    cameraManager.stopSession()
                }
            }
            .onAppear {
                if isActive {
                    print("📸 [CustomCameraView] 초기 로드 - 세션 시작")
                    cameraManager.startSession()
                }
            }
            .onDisappear {
                print("📸 [CustomCameraView] 뷰 사라짐 - 세션 중지")
                cameraManager.stopSession()
            }
        }
    }

    // 셔터 버튼 크기 (화면 폭 비례, 최대 78)
    private func shutterSize(_ geometry: GeometryProxy) -> CGFloat {
        min(geometry.size.width * 0.2, 78)
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
    
    // 이미지를 앨범에 저장
    private func saveImageToAlbum(_ image: UIImage) {
        // 현재 앨범 타입에 따른 앨범 이름
        let albumName: String
        switch SettingsManager.shared.albumType {
        case .diet:
            albumName = "세끼식단"
        case .exercise:
            albumName = "세끼운동"
        }

        // 사진 라이브러리 접근 권한 확인
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                print("사진 라이브러리 접근 권한이 없습니다.")
                return
            }

            // 먼저 앨범이 있는지 확인
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
            let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
            
            if let album = collection.firstObject {
                // 기존 앨범에 이미지 추가
                PHPhotoLibrary.shared().performChanges({
                    let assetRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
                    let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                    albumChangeRequest?.addAssets([assetRequest.placeholderForCreatedAsset!] as NSArray)
                }) { success, error in
                    if success {
                        print("이미지가 \(albumName) 앨범에 저장되었습니다.")
                    } else {
                        print("이미지 저장 실패: \(error?.localizedDescription ?? "알 수 없는 오류")")
                    }
                }
            } else {
                // 새 앨범 생성
                var albumPlaceholder: PHObjectPlaceholder?
                PHPhotoLibrary.shared().performChanges({
                    let createAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
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
                                    print("이미지가 새로 생성된 \(albumName) 앨범에 저장되었습니다.")
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
            
            VStack(spacing: 0) {
                // 이미지 미리보기
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                Spacer()

                HStack(spacing: 12) {
                    // 다시 찍기 버튼
                    Button("다시 찍기") {
                        onRetake()
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.18)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                    // 확인 버튼
                    Button("사용하기") {
                        onConfirm()
                    }
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Color.blue))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
    }
}
import Combine

// 카메라 매니저
class CameraManager: NSObject, ObservableObject {
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
        guard !isSessionRunning else {
            print("📸 [CameraManager] 세션이 이미 실행 중 - 시작 요청 무시")
            return
        }

        print("📸 [CameraManager] 세션 시작 요청")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                print("📸 [CameraManager] 세션 시작 완료")
            }

            DispatchQueue.main.async {
                self.isSessionRunning = true
            }
        }
    }

    func stopSession() {
        guard isSessionRunning else {
            print("📸 [CameraManager] 세션이 이미 중지됨 - 중지 요청 무시")
            return
        }

        print("📸 [CameraManager] 세션 중지 요청")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                print("📸 [CameraManager] 세션 중지 완료")
            }

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

        // 세션은 CustomCameraView에서 관리하므로 여기서 시작하지 않음

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
        picker.allowsEditing = false  // 까만 화면 방지를 위해 비활성화
        picker.modalPresentationStyle = .fullScreen

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
            if let originalImage = info[.originalImage] as? UIImage {
                // 정사각형으로 크롭
                parent.selectedImage = cropToSquare(image: originalImage)
            }

            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }

        // 이미지를 정사각형으로 크롭
        private func cropToSquare(image: UIImage) -> UIImage {
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
}

// 음식 태그 표시 뷰
struct FoodTagsView: View {
    let foodItems: [String]
    let description: String?
    @Binding var showFullAnalysis: Bool

    private let maxPreviewTags = 5 // 미리보기에 표시할 최대 태그 수

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 음식 태그 (칩 형태)
            let tagsToShow = showFullAnalysis ? foodItems : Array(foodItems.prefix(maxPreviewTags))

            FlowLayout(spacing: 6) {
                ForEach(tagsToShow, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 14))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                }
            }

            // 설명 (있을 경우)
            if let desc = description, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(showFullAnalysis ? nil : 2)
            }

            // 전체보기/접기 버튼
            if foodItems.count > maxPreviewTags || (description != nil && !description!.isEmpty) {
                Button(action: {
                    withAnimation {
                        showFullAnalysis.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(showFullAnalysis ? "접기" : "전체보기")
                            .font(.system(size: 13))
                        Image(systemName: showFullAnalysis ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
        }
    }
}

// Flow Layout (태그를 자동으로 줄바꿈하는 레이아웃)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let subviewSize = subview.sizeThatFits(.unspecified)

                if x + subviewSize.width > maxWidth && x > 0 {
                    // 다음 줄로 넘어감
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, subviewSize.height)
                x += subviewSize.width + spacing
            }

            size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

#Preview {
    ContentView()
}

