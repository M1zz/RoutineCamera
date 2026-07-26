//
//  SettingsView.swift
//  RoutineCamera
//
//  설정 화면 — 위계별로 정돈: 화면/기록 → 챙길 식사/알림 → 목표/저장 → 계정 →
//  고급(AI 분석은 하위 페이지) → 정보/지원 → 개발용.
//

import SwiftUI
import LeeoKit

struct SettingsView: View {
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject var goalManager: GoalManager
    @ObservedObject var mealStore: MealRecordStore
    @ObservedObject var settingsManager: SettingsManager
    @Environment(\.dismiss) var dismiss

    @State private var showingSampleDataAlert = false
    @State private var showingClearDataAlert = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationView {
            Form {
                screenSection
                displaySection
                caredMealsSection
                notificationSection
                goalSection
                photoSaveSection
                accountSection
                advancedSection
                infoSection
                DeveloperContactSection()
                supportSection
                #if DEBUG
                devSection
                #endif
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }

    // MARK: - 화면 & 기록 종류

    @ViewBuilder private var screenSection: some View {
        Section(header: Text("화면")) {
            Toggle("순간 피드", isOn: $settingsManager.useMomentsFeed)
            caption(settingsManager.useMomentsFeed
                    ? "빈 칸 없이 남긴 기록만 시간순으로 쌓이는 사진 일기 방식입니다."
                    : "아침·점심·저녁 칸이 있는 기존 격자 방식입니다.")

            Picker("기록 종류", selection: $settingsManager.albumType) {
                ForEach(AlbumType.allCases, id: \.self) { type in
                    HStack {
                        Image(systemName: type.symbolName)
                        Text(type.rawValue)
                    }
                    .tag(type)
                }
            }

            Toggle("헤더에 종류 전환 버튼", isOn: $settingsManager.showAlbumSwitcher)
        }
    }

    // MARK: - 표시

    @ViewBuilder private var displaySection: some View {
        Section(header: Text("표시")) {
            if settingsManager.albumType == .diet {
                Toggle("간식 보이기", isOn: $settingsManager.writeSnack)
                Toggle("식후 사진 알림 표시", isOn: $settingsManager.showRemainingPhotoCount)
            }
            Toggle("메모 아이콘 표시", isOn: $settingsManager.showMemoIcon)
        }
    }

    // MARK: - 챙길 식사

    @ViewBuilder private var caredMealsSection: some View {
        Section(header: Text("챙길 식사"),
                footer: Text(settingsManager.caredMeals.isEmpty
                    ? "선택한 식사가 없어 알림을 받지 않아요. 원할 때만 기록하세요."
                    : "고른 식사만 리마인드 알림을 받아요.")) {
            MealCareSelector()
                .padding(.vertical, 4)
        }
    }

    // MARK: - 알림

    @ViewBuilder private var notificationSection: some View {
        Section(header: Text("알림")) {
            Toggle("식사 기록 리마인드", isOn: Binding(
                get: { notificationManager.notificationsEnabled },
                set: { newValue in
                    if newValue {
                        notificationManager.requestAuthorization { granted in
                            if granted { notificationManager.scheduleMealNotifications() }
                        }
                    } else {
                        notificationManager.disableNotifications()
                    }
                }
            ))

            if notificationManager.notificationsEnabled {
                mealTimeRow("🌅 아침", $notificationManager.breakfastTime)
                mealTimeRow("☀️ 점심", $notificationManager.lunchTime)
                mealTimeRow("🌙 저녁", $notificationManager.dinnerTime)
            }

            Toggle("기록 시간 배너 표시", isOn: $settingsManager.autoOpenCamera)
        }
    }

    private func mealTimeRow(_ label: String, _ time: Binding<Date>) -> some View {
        HStack {
            Text(label).lineLimit(1).minimumScaleFactor(0.7)
            Spacer()
            DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .fixedSize()
        }
    }

    // MARK: - 목표

    @ViewBuilder private var goalSection: some View {
        Section(header: Text("목표")) {
            Toggle("목표 활성화", isOn: $goalManager.goalEnabled)
            if goalManager.goalEnabled {
                HStack {
                    Text("목표: \(goalManager.goalDays)일")
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer()
                    Stepper("", value: $goalManager.goalDays, in: 7...365, step: 1)
                        .labelsHidden()
                        .fixedSize()
                }
            }
        }
    }

    // MARK: - 사진 저장

    @ViewBuilder private var photoSaveSection: some View {
        Section(header: Text("사진 저장")) {
            Toggle("자동으로 사진앱에 저장", isOn: $settingsManager.autoSaveToPhotoLibrary)
            let albumName = settingsManager.albumType == .diet ? "세끼식단" : "세끼운동"
            caption(settingsManager.autoSaveToPhotoLibrary
                    ? "촬영하면 사진앱 '\(albumName)' 앨범에 저장됩니다."
                    : "앱 내부에만 저장합니다. 상세보기에서 개별 저장할 수 있어요.")
        }
    }

    // MARK: - 계정 · 공유

    @ViewBuilder private var accountSection: some View {
        Section(header: Text("계정 · 공유")) {
            Toggle("내 식단 공유", isOn: $settingsManager.shareMealsToCloud)
            caption("켜면 내 식단이 iCloud에 업로드되어 친구가 볼 수 있습니다.")

            HStack {
                Text("닉네임")
                Spacer()
                TextField("닉네임 입력", text: $settingsManager.nickname)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 고급 (AI 분석 하위 페이지)

    @ViewBuilder private var advancedSection: some View {
        Section(header: Text("고급")) {
            NavigationLink {
                AIAnalysisSettingsView(settingsManager: settingsManager)
            } label: {
                Label("AI 음식 분석", systemImage: "sparkles")
            }
        }
    }

    // MARK: - 정보 · 지원

    @ViewBuilder private var infoSection: some View {
        Section(header: Text("정보")) {
            HStack {
                Text("버전")
                Spacer()
                Text(appVersion).foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder private var supportSection: some View {
        Section(header: Text("지원")) {
            LeeoSupportSection<RoutineCameraSpec>()
        }
    }

    // MARK: - 개발용

    #if DEBUG
    @ViewBuilder private var devSection: some View {
        Section(header: Text("개발용")) {
            Button("샘플 데이터 생성") { showingSampleDataAlert = true }
                .alert("샘플 데이터 생성", isPresented: $showingSampleDataAlert) {
                    Button("취소", role: .cancel) { }
                    Button("생성") {
                        mealStore.generateSampleData()
                        dismiss()
                    }
                } message: {
                    Text("과거 30일간의 샘플 기록을 생성합니다.")
                }

            Button("모든 데이터 삭제", role: .destructive) { showingClearDataAlert = true }
                .alert("모든 데이터 삭제", isPresented: $showingClearDataAlert) {
                    Button("취소", role: .cancel) { }
                    Button("삭제", role: .destructive) {
                        mealStore.clearAllData()
                        dismiss()
                    }
                } message: {
                    Text("모든 기록이 삭제됩니다. 되돌릴 수 없습니다.")
                }
        }
    }
    #endif

    // MARK: - 공용

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(3)
            .minimumScaleFactor(0.8)
    }
}

// MARK: - AI 음식 분석 (설정 하위 페이지)

struct AIAnalysisSettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @State private var openAIAPIKey: String = UserDefaults.standard.string(forKey: "OpenAI_API_Key") ?? ""
    @State private var showingAPIKeyInfo = false

    var body: some View {
        Form {
            // 무료 분석
            Section(header: Text("무료 분석")) {
                HStack {
                    Image(systemName: "gift.fill")
                        .foregroundColor(settingsManager.freeAnalysisCount > 0 ? .green : .orange)
                    Text("잔여 무료 분석")
                    Spacer()
                    Text("\(settingsManager.freeAnalysisCount)회")
                        .font(.headline)
                        .foregroundColor(settingsManager.freeAnalysisCount > 0 ? .green : .orange)
                }
                Text("Vision Framework(Apple 기본) 사용 · 정확도 중간. 소진 시 OpenAI(코인) 사용.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 코인 & 구독
            Section(header: Text("분석 코인")) {
                HStack {
                    Image(systemName: "dollarsign.circle.fill").foregroundColor(.orange)
                    Text("보유 코인")
                    Spacer()
                    Text("\(CoinManager.shared.currentCoins)개")
                        .font(.headline).foregroundColor(.orange)
                }

                if CoinManager.shared.isSubscribed {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                        Text("구독 상태")
                        Spacer()
                        Text("활성").foregroundColor(.green)
                    }
                    if let daysLeft = CoinManager.shared.daysUntilNextRecharge() {
                        Text("다음 충전까지 \(daysLeft)일 남음")
                            .font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    Button {
                        Task {
                            if let product = await SubscriptionManager.shared.monthlyProduct {
                                _ = try? await SubscriptionManager.shared.purchase(product)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "cart.fill")
                            VStack(alignment: .leading, spacing: 4) {
                                Text("월간 구독").fontWeight(.semibold)
                                Text("매달 99코인 충전").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("$2.00/월").fontWeight(.bold)
                        }
                        .padding(.vertical, 8)
                    }

                    Button {
                        Task { await SubscriptionManager.shared.restorePurchases() }
                    } label: {
                        Text("구매 복원").font(.caption).foregroundColor(.blue)
                    }
                }

                #if DEBUG
                Button("🧪 테스트 코인 +10") { CoinManager.shared.addTestCoins(10) }
                Button("🔄 테스트용 초기화") { CoinManager.shared.resetForTesting() }
                #endif

                Text("1회 OpenAI 분석 = 1코인 · 월 $2 구독 시 매달 99코인 자동 충전")
                    .font(.caption).foregroundColor(.secondary)
            }

            // OpenAI 키
            Section(header: Text("고급 인식 (OpenAI)")) {
                HStack {
                    Image(systemName: OpenAIFoodAnalyzer.shared.isConfigured ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundColor(OpenAIFoodAnalyzer.shared.isConfigured ? .green : .orange)
                    Text("상태")
                    Spacer()
                    Text(OpenAIFoodAnalyzer.shared.isConfigured ? "설정됨" : "미설정")
                        .foregroundColor(.secondary)
                }

                SecureField("API 키 입력", text: $openAIAPIKey)
                    .textContentType(.password)
                    .autocapitalization(.none)

                HStack(spacing: 12) {
                    Button {
                        OpenAIFoodAnalyzer.shared.setAPIKey(openAIAPIKey)
                    } label: {
                        HStack { Image(systemName: "checkmark.circle.fill"); Text("저장") }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color.blue).foregroundColor(.white).cornerRadius(8)
                    }
                    .disabled(openAIAPIKey.isEmpty)

                    if OpenAIFoodAnalyzer.shared.isConfigured {
                        Button {
                            openAIAPIKey = ""
                            OpenAIFoodAnalyzer.shared.setAPIKey("")
                        } label: {
                            HStack { Image(systemName: "trash.fill"); Text("삭제") }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(Color.red).foregroundColor(.white).cornerRadius(8)
                        }
                    }
                }

                if OpenAIFoodAnalyzer.shared.isConfigured {
                    Toggle("사진 촬영 시 자동 분석", isOn: $settingsManager.autoFoodAnalysis)
                    Text(settingsManager.autoFoodAnalysis
                         ? "⚠️ 촬영 시 자동 분석 (API 비용 발생, 월 약 $2.7~8.1 예상)"
                         : "✅ 필요할 때만 수동 분석 (비용 절약)")
                        .font(.caption)
                        .foregroundColor(settingsManager.autoFoodAnalysis ? .orange : .green)
                }

                Button {
                    showingAPIKeyInfo = true
                } label: {
                    HStack { Image(systemName: "questionmark.circle"); Text("API 키 받는 방법") }
                }
            }
            .alert("OpenAI API 키 받는 방법", isPresented: $showingAPIKeyInfo) {
                Button("확인", role: .cancel) { }
            } message: {
                Text("""
                1. https://platform.openai.com 접속
                2. 로그인 후 API Keys 메뉴
                3. "Create new secret key" 클릭
                4. 생성된 키를 복사해서 붙여넣기

                ⚠️ 결제 수단 등록·최소 $5 충전 필요
                💰 이미지 1회 약 $0.01~0.03
                """)
            }
        }
        .navigationTitle("AI 음식 분석")
        .navigationBarTitleDisplayMode(.inline)
    }
}
