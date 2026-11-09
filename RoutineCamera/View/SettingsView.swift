//
//  SettingsView.swift
//  RoutineCamera
//
//  설정 화면 — 위계별로 정돈: 요금제와 응원(맨 위) → 화면/기록 → 챙길 식사/알림 → 목표/저장 →
//  계정 → 음식 분석 → 정보/지원 → 개발용. 섹션마다 머리말을 단다.
//

import SwiftUI
import LeeoKit
import StoreKit
import RoutineCameraCore

struct SettingsView: View {
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject var goalManager: GoalManager
    @ObservedObject var mealStore: MealRecordStore
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject private var friendManager = FriendManager.shared
    @AppStorage("showsDayCheckIn") private var showsDayCheckIn = true // 홈 맨 위 '오늘 챙긴 것' 카드 (MomentsView 와 같은 값)
    @ObservedObject private var subscription = SubscriptionManager.shared
    @ObservedObject private var locationProvider = MealLocationProvider.shared
    @Environment(\.dismiss) var dismiss
    @State private var showingPaywall = false
    @State private var paywallLead: ProFeature?
    @State private var showingManageSubscription = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    @State private var showingSampleDataAlert = false
    @State private var showingClearDataAlert = false
    // 타이핑 중에는 로컬 값만 바꾸고 편집을 마칠 때 반영 (한 글자마다 iCloud에 올리지 않도록)
    @State private var nicknameDraft = ""
    @FocusState private var isNicknameFocused: Bool

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationView {
            Form {
                // 요금제 · 응원 · 선물을 한 칸에. 돈 이야기는 맨 위 여기에만 있다.
                planSection
                screenSection
                displaySection
                caredMealsSection
                notificationSection
                goalSection
                photoSaveSection
                photoStampSection
                ICloudBackupSection()
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
                    Button("완료", systemImage: "checkmark") {
                        commitNickname()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료", systemImage: "checkmark") {
                        commitNickname()
                        isNicknameFocused = false
                    }
                }
            }
            .onAppear { nicknameDraft = settingsManager.displayNickname }
            .proPaywall(isPresented: $showingPaywall, lead: paywallLead)
            .manageSubscriptionsSheet(isPresented: $showingManageSubscription)
            .alert("알림이 꺼져 있어요", isPresented: $friendManager.notificationsDenied) {
                Button("설정 열기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("닫기", role: .cancel) {}
            } message: {
                Text("설정 ▸ 세끼 ▸ 알림을 켜야 친구 소식을 받을 수 있어요.")
            }
            .onDisappear { commitNickname() }
        }
    }

    private func commitNickname() {
        settingsManager.commitNickname(nicknameDraft)
        nicknameDraft = settingsManager.displayNickname
    }

    // MARK: - 화면 & 기록 종류

    @ViewBuilder private var screenSection: some View {
        Section(header: Text("화면")) {
            Toggle("순간 피드", isOn: $settingsManager.useMomentsFeed)
            caption(settingsManager.useMomentsFeed
                    ? Text("빈 칸 없이 남긴 기록만 시간순으로 쌓이는 사진 일기 방식입니다.")
                    : Text("아침·점심·저녁 칸이 있는 기존 격자 방식입니다."))

            Toggle("운동 모드로 기록", isOn: Binding(
                get: { settingsManager.albumType == .exercise },
                set: { settingsManager.albumType = $0 ? .exercise : .diet }
            ))
            caption(settingsManager.albumType == .exercise
                    ? Text("운동 사진을 기록합니다. 식단과 운동은 별도로 저장돼요.")
                    : Text("식단 사진을 기록합니다. 켜면 운동 기록으로 전환돼요."))

            if settingsManager.albumType == .diet {
                Toggle("식후 사진 남기기", isOn: $settingsManager.useAfterPhoto)
                caption(settingsManager.useAfterPhoto
                        ? Text("식전·식후 두 장으로 기록합니다. 다 먹은 뒤 \"다 드셨어요?\" 알림을 받아요.")
                        : Text("식전 사진 한 장으로 기록이 끝납니다. 식후 촬영 안내와 알림을 받지 않아요."))
            }

            Toggle("헤더에 종류 전환 버튼", isOn: $settingsManager.showAlbumSwitcher)

            // 앱 잠금 — 프로가 아니면 켜려 할 때 페이월
            Toggle(isOn: Binding(
                get: { settingsManager.appLockEnabled && subscription.allows(.appLock) },
                set: { on in
                    if on && !subscription.allows(.appLock) {
                        paywallLead = .appLock
                        showingPaywall = true
                    } else {
                        settingsManager.appLockEnabled = on
                    }
                }
            )) {
                Label("\(AppLockAuthenticator.biometryName) 잠금", systemImage: "lock.fill")
            }
        }
    }

    // MARK: - 표시

    @ViewBuilder private var displaySection: some View {
        Section(header: Text("표시")) {
            if settingsManager.albumType == .diet {
                Toggle("간식 보이기", isOn: $settingsManager.writeSnack)
                // 오늘 챙긴 것 카드는 순간 피드에만 있다
                if settingsManager.useMomentsFeed {
                    Toggle("오늘 챙긴 것", isOn: $showsDayCheckIn)
                    caption("홈 맨 위에서 스탬프와 물 · 카페인을 바로 찍어요.")
                }
                if settingsManager.useAfterPhoto {
                    Toggle("식후 사진 알림 표시", isOn: $settingsManager.showRemainingPhotoCount)
                }
            }
            Toggle("메모 아이콘 표시", isOn: $settingsManager.showMemoIcon)
        }
    }

    // MARK: - 챙길 식사

    @ViewBuilder private var caredMealsSection: some View {
        Section(header: Text("챙길 식사"),
                footer: settingsManager.caredMeals.isEmpty
                    ? Text("선택한 식사가 없어 알림을 받지 않아요. 원할 때만 기록하세요.")
                    : Text("고른 식사만 리마인드 알림을 받아요.")) {
            MealCareSelector()
                .padding(.vertical, 4)
        }
    }

    // MARK: - 알림

    @ViewBuilder private var notificationSection: some View {
        Section(header: Text("알림")) {
            Toggle("식사 전 촬영 알림", isOn: Binding(
                get: { notificationManager.notificationsEnabled && notificationManager.mealRemindersEnabled },
                set: { newValue in
                    if newValue {
                        notificationManager.requestAuthorization { granted in
                            guard granted else { return }
                            notificationManager.mealRemindersEnabled = true
                            notificationManager.scheduleMealNotifications()
                        }
                    } else {
                        notificationManager.mealRemindersEnabled = false
                    }
                }
            ))

            if notificationManager.notificationsEnabled && notificationManager.mealRemindersEnabled {
                Picker("알림 시점", selection: $notificationManager.reminderLeadMinutes) {
                    ForEach(NotificationManager.leadMinuteOptions, id: \.self) { minutes in
                        (minutes == 0 ? Text("식사 시간 정각") : Text("\(minutes)분 전")).tag(minutes)
                    }
                }
                mealTimeRow("🌅 \(MealType.breakfast.displayName)", $notificationManager.breakfastTime)
                mealTimeRow("☀️ \(MealType.lunch.displayName)", $notificationManager.lunchTime)
                mealTimeRow("🌙 \(MealType.dinner.displayName)", $notificationManager.dinnerTime)
                caption("챙길 식사로 고른 끼니만, 먹기 전에 사진을 찍으라고 알려요. 이미 기록한 끼니는 알리지 않아요.")
            } else if !notificationManager.notificationsEnabled {
                caption("알림 권한이 꺼져 있어요. 설정 앱 → 세끼 → 알림에서 허용하면 켤 수 있어요.")
            }

            Toggle("기록 시간 배너 표시", isOn: $settingsManager.autoOpenCamera)

            friendPushRow

            friendMealPushRow
        }
    }

    /// 친구가 기록을 올리면 알림을 받을지. 켜면 친구마다 CloudKit 구독을 건다.
    @ViewBuilder private var friendMealPushRow: some View {
        Toggle("친구 기록 알림", isOn: $friendManager.notifyFriendMeals)
        if friendManager.notifyFriendMeals {
            switch friendManager.friendMealPushState {
            case .registering:
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    caption("친구마다 알림을 등록하는 중...")
                }
            case .failed(let reason):
                VStack(alignment: .leading, spacing: 6) {
                    caption(Text(reason))
                    Button("다시 등록") {
                        friendManager.syncFriendMealSubscriptions()
                    }
                    .scaledFont(size: 14)
                }
            case .ready, .unknown:
                caption("친구가 사진을 올리면 알려 드려요. 한 친구가 여러 끼를 한꺼번에 올려도 알림은 하나로 모아요.")
            }
        }
    }

    /// 친구 응원 푸시가 실제로 걸려 있는지 보여 주고, 안 걸렸으면 다시 시도하게 한다.
    ///
    /// 이 알림은 CloudKit 구독이 배달하는데, 등록이 실패해도 예전에는 아무 표시가 없어
    /// "왜 알림이 안 오지"를 확인할 방법이 없었다.
    @ViewBuilder private var friendPushRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("친구 응원 알림")
                Spacer()
                switch friendManager.pushSubscriptionState {
                case .ready:
                    Label("켜짐", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .scaledFont(size: 14)
                        .foregroundColor(.green)
                case .registering:
                    ProgressView().scaleEffect(0.7)
                case .failed:
                    Label("꺼짐", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.titleAndIcon)
                        .scaledFont(size: 14)
                        .foregroundColor(.orange)
                case .unknown:
                    Text("확인 중")
                        .scaledFont(size: 14)
                        .foregroundColor(.secondary)
                }
            }

            if case .failed(let reason) = friendManager.pushSubscriptionState {
                Text(reason)
                    .scaledFont(size: 12)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("다시 등록") {
                    friendManager.retryFeedbackSubscription()
                }
                .scaledFont(size: 14)
            }
        }
        .accessibilityElement(children: .combine)
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
            let albumName = settingsManager.albumType.photoAlbumName
            caption(settingsManager.autoSaveToPhotoLibrary
                    ? Text("촬영하면 사진앱 '\(albumName)' 앨범에 저장됩니다.")
                    : Text("앱 내부에만 저장합니다. 상세보기에서 개별 저장할 수 있어요."))

            Toggle("찍은 곳 함께 남기기", isOn: $settingsManager.recordPlace)
                .onChange(of: settingsManager.recordPlace) { _, isOn in
                    if isOn { locationProvider.requestAuthorizationIfNeeded() }
                }
            if settingsManager.recordPlace && locationProvider.isDenied {
                Text("위치 권한이 꺼져 있어 찍은 곳을 남기지 못해요.")
                    .font(.body)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("설정 앱에서 위치 허용하기") {
                    MealLocationProvider.openAppSettings()
                }
            } else {
                Text("카메라로 찍을 때 어디서 먹었는지 기록해요. 사진앱에 저장한 사진에도 위치가 들어가고, 친구에게는 보이지 않아요.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 사진 날짜 도장

    // 사진 왼쪽 아래에 새기는 날짜 · 시간. 기본값(켬 · 기본 글꼴 · 시간 포함)은 예전과 같은 모양이라
    // 아무것도 안 건드린 사용자의 사진은 그대로다. 바꾼 설정은 새로 찍는 사진부터 적용된다.
    @ViewBuilder private var photoStampSection: some View {
        Section(header: Text("사진 날짜 도장")) {
            Toggle("사진에 날짜 새기기", isOn: $settingsManager.photoStampEnabled)
            if settingsManager.photoStampEnabled {
                Toggle("시간도 함께 새기기", isOn: $settingsManager.photoStampShowsTime)
                Picker("글꼴", selection: $settingsManager.photoStampFont) {
                    ForEach(MealStampFont.allCases) { font in
                        Text(font.displayName).font(font.font(size: 17)).tag(font)
                    }
                }
                MealStampPreview(style: MealStampStyle(isEnabled: settingsManager.photoStampEnabled,
                                                       font: settingsManager.photoStampFont,
                                                       showsTime: settingsManager.photoStampShowsTime))
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            Text("새로 찍는 사진부터 적용돼요. 이미 찍은 사진은 상세 화면의 '날짜·시간 바꾸기'에서 다시 새길 수 있어요.")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 계정 · 공유

    @ViewBuilder private var accountSection: some View {
        Section(header: Text("계정 · 공유")) {
            Toggle("내 식단 공유", isOn: $settingsManager.shareMealsToCloud)
            caption("켜면 내 식단이 iCloud에 업로드되어 친구가 볼 수 있습니다.")

            HStack {
                Text("친구에게 보이는 이름")
                Spacer()
                TextField("이름 입력", text: $nicknameDraft)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
                    .focused($isNicknameFocused)
                    .submitLabel(.done)
                    .onSubmit { commitNickname() }
            }
            caption("친구·그룹 화면에서 상대에게 이 이름으로 보입니다.")

            NavigationLink {
                MealBackfillView()
            } label: {
                Label("예전 기록 공유", systemImage: "icloud.and.arrow.up")
            }
            caption("폰에만 있는 지난 기록을 iCloud에 올려 친구도 볼 수 있게 합니다.")
        }
    }

    // MARK: - 요금제와 응원

    /// 요금제 → 개발자 응원하기 → 선물하기 → 구매 복원. 돈 이야기는 이 한 칸에 모여 있다.
    @ViewBuilder private var planSection: some View {
        Section {
            planRows
            // 개발자 응원하기 — 팁 상품이 App Store 에서 와야 줄이 선다. 응원한 사람에게는 지금 단계가 줄 안에 보인다.
            if let tipJar = subscription.tipJar {
                LeeoTipJarLink<RoutineCameraSpec>(tipJar: tipJar)
            }
            // 선물하기 — 누르면 선물 화면으로 들어간다
            if let gift = subscription.gift {
                GiftRow(gift: gift)
            }
            restoreButton
        } header: {
            Text("요금제와 응원", comment: "Settings section header: plan, tip and gifts")
        } footer: {
            if !subscription.isPro {
                Text("기록, 위젯, 친구와 공유, 그룹 참여는 계속 무료예요.")
            }
        }
    }

    @ViewBuilder private var planRows: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                if let tier = subscription.tier {
                    Text("세끼 \(tier.name) 사용 중", comment: "Settings: current paid tier (tier name)")
                        .font(.headline)
                    caption(Text(subscription.isTopTier
                                 ? String(localized: "모든 기능을 쓸 수 있어요.")
                                 : String(localized: "프로로 올리면 식사 지도, 주간 리포트, 내보내기까지 써요.")))
                } else {
                    Text("세끼 플러스 · 프로")
                        .font(.headline)
                    caption("그룹 여러 개, 자세한 통계, Face ID 잠금, 식사 지도, 내보내기")
                }
            }
        } icon: {
            Image(systemName: "crown.fill").foregroundColor(.orange)
        }

        // 다음 칸이 있으면 꽉 찬 단추로 — 설정에서 가장 먼저 눈에 들어오는 길
        if !subscription.isTopTier {
            Button {
                paywallLead = nil
                showingPaywall = true
            } label: {
                Text(subscription.tier == nil
                     ? String(localized: "플러스 · 프로 보기", comment: "Settings: filled button opening the paywall (free user)")
                     : String(localized: "프로로 올리기"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .listRowSeparator(.hidden)
        }
        if subscription.tier != nil {
            Button("구독 관리") { showingManageSubscription = true }
        }
    }

    /// 구매 복원 — 다른 기기에서 샀거나 다시 설치했을 때 (심사 필수). 칸 끝에 둔다.
    @ViewBuilder private var restoreButton: some View {
        Button {
            Task {
                isRestoring = true
                let restored = await subscription.restore()
                isRestoring = false
                restoreMessage = restored
                    ? String(localized: "구매를 되찾았어요.", comment: "Settings: restore purchases succeeded")
                    : String(localized: "되찾을 구매가 없어요. 산 Apple 계정으로 로그인했는지 확인해 주세요.", comment: "Settings: restore purchases found nothing")
            }
        } label: {
            HStack {
                Label("구매 복원", systemImage: "arrow.clockwise")
                if isRestoring {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(isRestoring)
        if let restoreMessage {
            caption(Text(restoreMessage))
        }
    }

    // MARK: - 음식 분석 (기기 안에서 무료)

    @ViewBuilder private var advancedSection: some View {
        Section(header: Text("음식 분석")) {
            Toggle(isOn: $settingsManager.autoFoodAnalysis) {
                Label("찍으면 음식 자동 분석", systemImage: "sparkles")
            }
            caption("사진 속 음식을 휴대폰 안에서 알아보고 기록에 이름표를 붙입니다. 사진은 밖으로 나가지 않아요.")
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
            NavigationLink(LeeoRoadmapText.entry) { RoadmapScreen() }
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

    private func caption(_ key: LocalizedStringKey) -> some View {
        caption(Text(key))
    }

    private func caption(_ text: Text) -> some View {
        text
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)   // 길어도 줄여 자르지 않고 다 보이게
    }
}

// MARK: - 선물하기

/// 설정의 선물하기 한 줄. 누르면 선물 화면(`SettingsGiftView`)으로 들어간다.
/// ⚠️ 선물 엔진은 따로 관찰한다 — 상품은 앱이 뜬 뒤에 오는데 그 변화가 `SubscriptionManager` 로 전해지지 않는다.
private struct GiftRow: View {
    @ObservedObject var gift: LeeoGiftStore

    var body: some View {
        if SettingsGiftView.hasContent(gift) {
            NavigationLink {
                SettingsGiftView(gift: gift)
            } label: {
                Label(String(localized: "선물하기", comment: "Settings: gift entry opening the gift page"), systemImage: "gift.fill")
            }
        }
    }
}

/// 설정 ▸ 선물하기. 누르면 바로 프로를 선물하는 화면이다 (클립키보드와 같은 한 번 들어가기).
/// 받는 사람은 평생 프로를 산 것과 같아진다(`RoutineCameraSpec.monetization` 의 `gift`).
///
/// ⚠️ 상품이 App Store 에서 와야 보내기가 선다(`isAvailable`). 단, 이미 결제했거나 주고받은 선물이 있는 사람에게는
///    늘 보인다(코드를 다시 보거나 문의까지 갈 길이 있어야 한다).
/// ⚠️ 화면 문구는 LeeoKit 카탈로그(`LeeoGiftText`)에 24개 언어로 이미 있다.
private struct SettingsGiftView: View {
    @ObservedObject var gift: LeeoGiftStore
    @State private var showSupport = false

    /// 보내기 — 선물 판매가 열렸거나 보낸 · 보내는 중인 선물이 있을 때
    private static func showsSend(_ gift: LeeoGiftStore) -> Bool {
        gift.isAvailable || gift.pendingCount > 0 || !gift.sentGifts.isEmpty
    }
    /// 받은 선물 — 받는 사람은 보낸 링크를 누르면 끝이라 따로 받는 칸이 없다.
    /// 예전 방식(선물 코드)으로 이미 받은 사람에게만 그 기록을 보여 준다.
    private static func showsRedeem(_ gift: LeeoGiftStore) -> Bool { gift.redeemed != nil }

    /// 설정에 선물하기 줄을 세울지
    static func hasContent(_ gift: LeeoGiftStore) -> Bool { showsSend(gift) || showsRedeem(gift) }

    var body: some View {
        Group {
            // 선물이 안 되면 결제 번호·코드를 붙여 문의하게 한다 — 막힌 사람을 놓치지 않게.
            if Self.showsSend(gift) {
                LeeoGiftView<RoutineCameraSpec>(gift: gift, showsRedeemLink: Self.showsRedeem(gift),
                                                onContactSupport: { showSupport = true })
            } else {
                LeeoGiftRedeemView<RoutineCameraSpec>(gift: gift, onContactSupport: { showSupport = true })
            }
        }
        .sheet(isPresented: $showSupport) {
            NavigationStack {
                LeeoFeedbackView<RoutineCameraSpec>(initialType: .bug, extraInfo: gift.supportLines,
                                                    initialCategory: .purchase)
            }
        }
    }
}

// MARK: - AI 음식 분석 (설정 하위 페이지)

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

// MARK: - iCloud 백업

private struct ICloudBackupSection: View {
    @ObservedObject private var sync = MealCloudSync.shared

    var body: some View {
        Section(header: Text("iCloud 백업")) {
            Toggle("기록과 사진을 iCloud에 보관", isOn: $sync.isEnabled)
            Text("앱을 지우거나 기기를 바꿔도 같은 iCloud 계정이면 기록이 돌아와요. iCloud 저장 공간을 사용하며, 친구에게는 보이지 않아요.")
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let statusText {
                statusText
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusText: Text? {
        switch sync.status {
        case .off: return nil
        case .notSignedIn: return Text("iCloud에 로그인하면 백업이 시작돼요.")
        case .uploading(let count): return Text("백업할 기록 \(count)개")
        case .upToDate: return Text("모든 기록이 백업되었어요.")
        case .storageFull: return Text("iCloud 저장 공간이 부족해요. 공간을 확보하면 이어서 백업해요.")
        case .failed: return Text("지금은 백업하지 못했어요. 앱을 다시 열면 이어서 시도해요.")
        }
    }
}
