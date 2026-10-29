//
//  FriendsView.swift
//  RoutineCamera
//
//  친구 목록 및 관리 화면
//

import SwiftUI
import RoutineCameraCore

struct FriendsView: View {
    @ObservedObject var friendManager = FriendManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared
    @State private var showingAddFriend = false
    @State private var friendCode = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedFriend: Friend?
    @State private var safetyTarget: SafetyTarget?   // 끊기·차단·신고
    @State private var showingNicknamePrompt = false  // 처음 한 번 — 친구에게 보일 이름
    @State private var nicknameDraft = ""
    @State private var showingAccountSettings = false
    @State private var showingDeleteConfirm = false
    @State private var showingGroups = false
    /// 오늘 친구들이 올린 식사 (친구 id → 끼니별 기록)
    @State private var todayMeals: [String: [MealType: MealRecord]] = [:]
    @State private var isLoadingTodayMeals = false

    var body: some View {
        NavigationView {
            if !friendManager.isSignedIn {
                // iCloud 로그인 안내 화면
                ICloudRequiredView()
            } else {
                // 친구 목록 화면
                friendsContentView
            }
        }
    }

    // 친구에게 보이는 내 이름. 이 화면을 열면 바로 확인되고, 수정은 계정 설정에서 한다.
    private var myNicknameRow: some View {
        Button {
            showingAccountSettings = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .scaledFont(size: 32)
                    .foregroundColor(.blue)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("친구에게 보이는 이름")
                        .scaledFont(size: 12)
                        .foregroundColor(.secondary)
                    Text(settingsManager.displayNickname)
                        .scaledFont(size: 17, weight: .semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                Spacer()

                Text("변경")
                    .scaledFont(size: 14, weight: .medium)
                    .foregroundColor(.blue)
                Image(systemName: "chevron.right")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("친구에게 보이는 이름, \(settingsManager.displayNickname)")
        .accessibilityHint("두 번 탭하여 이름 변경")
    }

    private var friendsContentView: some View {
        VStack(spacing: 0) {
                // 내 코드 섹션
                VStack(spacing: 12) {
                    myNicknameRow

                    Text("내 친구 코드")
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        if friendManager.myUserCode.isEmpty {
                            // 로딩 중 스켈레톤
                            HStack(spacing: 8) {
                                ForEach(0..<6, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 30, height: 40)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text(friendManager.myUserCode)
                                .scaledFont(size: 32, weight: .bold, design: .monospaced)
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("내 친구 코드")
                                .accessibilityValue(friendManager.myUserCode.map { String($0) }.joined(separator: " "))

                            Button(action: {
                                UIPasteboard.general.string = friendManager.myUserCode
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .scaledFont(size: 20)
                                    .foregroundColor(.blue)
                            }
                            .accessibilityLabel("친구 코드 복사")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // 앱이 없는 친구도 받아서 바로 연결할 수 있게 — 코드와 앱 받기 링크를 함께 보낸다
                    if !friendManager.myUserCode.isEmpty {
                        ShareLink(item: FriendInvite.message(code: friendManager.myUserCode)) {
                            Label("친구 초대하기", systemImage: "square.and.arrow.up")
                                .scaledFont(size: 15, weight: .semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }

                    Text(friendManager.myUserCode.isEmpty ? "친구 코드 생성 중..." : "이 코드를 친구에게 공유하세요")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // 내 코드가 서버에서 검색되지 않을 때 안내 (친구 쪽 "존재하지 않는 코드" 예방)
                    if let warning = friendManager.codeStatusWarning {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(warning)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Button("다시 확인") {
                                    _Concurrency.Task {
                                        await friendManager.verifyMyCodeRegistered()
                                    }
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(10)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding()
                .background(Color(.systemBackground))

                Divider()

                // 받은 요청 · 보낸 요청 · 친구
                List {
                    // 오늘 친구들이 무엇을 올렸는지 사진으로 한눈에
                    if !friendManager.friends.isEmpty {
                        Section {
                            FriendsTodayStrip(
                                friends: friendManager.friends,
                                mealsByFriend: todayMeals,
                                isLoading: isLoadingTodayMeals,
                                notifyFriendMeals: $friendManager.notifyFriendMeals,
                                onSelect: { selectedFriend = $0 }
                            )
                            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                        }
                    }

                    if !friendManager.incomingRequests.isEmpty {
                        Section("받은 친구 요청") {
                            ForEach(friendManager.incomingRequests) { request in
                                FriendRequestRow(request: request)
                            }
                        }
                    }

                    if !friendManager.pendingFriends.isEmpty {
                        Section("보낸 요청") {
                            ForEach(friendManager.pendingFriends) { pending in
                                PendingFriendRow(pending: pending)
                            }
                        }
                    }

                    if let error = friendManager.socialError {
                        Section {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("친구 목록을 새로 고치지 못했어요")
                                        .scaledFont(size: 14, weight: .semibold)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Button("다시 시도") {
                                        _Concurrency.Task { await friendManager.refreshSocialGraph() }
                                    }
                                    .font(.caption.weight(.semibold))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Section("친구") {
                        if friendManager.isLoadingSocial && friendManager.friends.isEmpty {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("친구 목록을 불러오는 중...")
                                    .scaledFont(size: 14)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        } else if friendManager.friends.isEmpty {
                            emptyFriendsRow
                        } else {
                            ForEach(friendManager.friends) { friend in
                                friendRow(friend)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await friendManager.refreshSocialGraph()
                    await friendManager.loadMyGroups()
                    await loadTodayMeals()
                }
            }
            .navigationTitle("친구")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 16) {
                        #if DEBUG
                        // 샘플 데이터 생성 버튼 (개발자 모드 전용)
                        Button(action: {
                            // 중복 클릭 방지
                            guard !friendManager.isLoading else { return }

                            _Concurrency.Task {
                                do {
                                    try await friendManager.createSampleFriend()
                                    errorMessage = String(localized: "샘플 친구가 생성되었습니다!\n코드 'ABCABC'로 추가할 수 있습니다.", comment: "Debug only: sample friend created")
                                    showingError = true
                                } catch {
                                    errorMessage = String(localized: "샘플 데이터 생성 실패: \(error.localizedDescription)", comment: "Debug only: sample data failed")
                                    showingError = true
                                }
                            }
                        }) {
                            Image(systemName: "testtube.2")
                                .scaledFont(size: 20)
                                .foregroundColor(friendManager.isLoading ? .gray : .orange)
                        }
                        .disabled(friendManager.isLoading)
                        .accessibilityLabel("샘플 친구 생성")
                        #endif

                        // 계정 설정 버튼
                        Button(action: {
                            showingAccountSettings = true
                        }) {
                            Image(systemName: "person.circle")
                                .scaledFont(size: 20)
                                .foregroundColor(.blue)
                        }
                        .accessibilityLabel("계정 설정")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: {
                            showingGroups = true
                        }) {
                            Image(systemName: "person.3")
                                .scaledFont(size: 20)
                        }
                        .accessibilityLabel("그룹")

                        Button(action: {
                            showingAddFriend = true
                        }) {
                            Image(systemName: "person.badge.plus")
                                .scaledFont(size: 20)
                        }
                        .accessibilityLabel("친구 요청 보내기")
                    }
                }
            }
            .sheet(isPresented: $showingAddFriend) {
                AddFriendSheet(friendCode: $friendCode) { code in
                    try await friendManager.sendFriendRequest(code: code)
                }
            }
            .sheet(item: $selectedFriend) { friend in
                FriendMealsView(friend: friend)
            }
            .userSafetyActions($safetyTarget)
            .alert("알림이 꺼져 있어요", isPresented: $friendManager.notificationsDenied) {
                Button("설정 열기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("닫기", role: .cancel) {}
            } message: {
                Text("설정 ▸ 세끼 ▸ 알림을 켜야 친구 소식을 받을 수 있어요.")
            }
            .sheet(isPresented: $showingGroups) {
                GroupsView()
            }
            .sheet(isPresented: $showingAccountSettings) {
                AccountSettingsSheet(
                    onDeleteAccount: {
                        showingDeleteConfirm = true
                    }
                )
            }
            .alert("회원 탈퇴", isPresented: $showingDeleteConfirm) {
                Button("취소", role: .cancel) { }
                Button("탈퇴", role: .destructive) {
                    _Concurrency.Task {
                        do {
                            try await friendManager.deleteAccount()
                            showingAccountSettings = false
                        } catch {
                            errorMessage = String(localized: "회원 탈퇴 실패: \(error.localizedDescription)", comment: "Error: deleting the account failed")
                            showingError = true
                        }
                    }
                }
            } message: {
                Text("회원 탈퇴 시 모든 데이터가 삭제되며 복구할 수 없습니다.\n정말 탈퇴하시겠습니까?")
            }
            .alert("오류", isPresented: $showingError) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .task {
                // 친구에게 "사용자" 로 요청이 가지 않도록, 이름을 정한 적 없으면 먼저 묻는다
                if friendManager.isSignedIn && !settingsManager.hasChosenNickname {
                    nicknameDraft = ""
                    showingNicknamePrompt = true
                }
                // 화면 진입 시 받은 요청·수락 여부를 최신으로 (푸시를 탭해 들어온 경우 포함)
                await friendManager.refreshSocialGraph()
                await loadTodayMeals()
            }
            .alert("친구에게 보일 이름", isPresented: $showingNicknamePrompt) {
                TextField("이름", text: $nicknameDraft)
                Button("저장") { settingsManager.commitNickname(nicknameDraft) }
                Button("나중에", role: .cancel) {}
            } message: {
                Text("친구 요청과 응원에 이 이름이 보여요. 설정에서 언제든 바꿀 수 있어요.")
            }
        }

    /// 친구가 없을 때 보여줄 안내 행
    private var emptyFriendsRow: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 44))
                .foregroundColor(.gray)
                .accessibilityHidden(true)

            Text("아직 친구가 없어요")
                .scaledFont(size: 16, weight: .semibold)
                .foregroundColor(.secondary)

            Text("친구 코드로 요청을 보내면\n상대가 수락한 뒤 서로의 기록을 볼 수 있어요")
                .scaledFont(size: 13)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showingAddFriend = true }) {
                Label("친구 요청 보내기", systemImage: "person.badge.plus")
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .listRowSeparator(.hidden)
    }

    /// 친구 한 명 행
    private func friendRow(_ friend: Friend) -> some View {
        Button(action: {
            selectedFriend = friend
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 50, height: 50)

                    Text(String(friend.name.prefix(1)))
                        .scaledFont(size: 24, weight: .bold)
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.name)
                        .scaledFont(size: 17, weight: .semibold)
                        .foregroundColor(.primary)

                    // 오늘 어떤 끼니를 올렸는지 + 친구 코드
                    HStack(spacing: 8) {
                        MealDotsView(recorded: Set((todayMeals[friend.id] ?? [:]).keys))
                        Text(friend.code)
                            .scaledFont(size: 13, design: .monospaced)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .scaledFont(size: 14)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(friend.name), 오늘 \((todayMeals[friend.id] ?? [:]).count)끼 기록")
        .accessibilityHint("두 번 탭하여 이 친구의 기록 보기")
        // 바로 지우지 않고 끊기·차단·신고 중에서 고르게 한다 (실수로 밀어도 친구가 사라지지 않도록)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                safetyTarget = SafetyTarget(userId: friend.id, code: friend.code, name: friend.name, isFriend: true)
            } label: {
                Label("관리", systemImage: "ellipsis.circle")
            }
            .tint(.gray)
        }
        .contextMenu {
            Button {
                safetyTarget = SafetyTarget(userId: friend.id, code: friend.code, name: friend.name, isFriend: true)
            } label: {
                Label("끊기 · 차단 · 신고", systemImage: "hand.raised")
            }
        }
    }

    /// 친구마다 오늘 식단(음식)을 받아 온다. 오늘 기록은 계속 늘어나므로 캐시를 버리고 새로 받는다.
    /// 한 명씩 받는 대로 화면에 채워, 친구가 많아도 첫 카드가 금방 뜬다.
    private func loadTodayMeals() async {
        let friends = friendManager.friends
        guard !friends.isEmpty else { return }
        let today = Calendar.current.startOfDay(for: Date())

        isLoadingTodayMeals = true
        defer { isLoadingTodayMeals = false }

        for friend in friends {
            friendManager.invalidateCache(friendId: friend.id, date: today)
            do {
                let loaded = try await friendManager.loadFriendMealsBatch(friendId: friend.id, dates: [today], album: .diet)
                todayMeals[friend.id] = loaded[today] ?? [:]
            } catch {
                print("❌ [FriendsView] \(friend.name) 오늘 식단 조회 실패: \(error.localizedDescription)")
            }
        }
    }
    }

/// 아침·점심·저녁 세 칸 — 기록한 끼니는 끼니 색으로 채우고, 안 한 끼니는 빈 원. 간식은 개수로 덧붙인다.
struct MealDotsView: View {
    let recorded: Set<MealType>

    private let mainMeals: [MealType] = [.breakfast, .lunch, .dinner]
    private var snackCount: Int { recorded.filter { !mainMeals.contains($0) }.count }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(mainMeals, id: \.self) { meal in
                let done = recorded.contains(meal)
                Circle()
                    .fill(done ? meal.symbolColor : Color.clear)
                    .overlay(Circle().stroke(done ? meal.symbolColor : Color(.systemGray3), lineWidth: 1.2))
                    .frame(width: 8, height: 8)
            }
            if snackCount > 0 {
                Text("+\(snackCount)")
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recorded.isEmpty
                            ? String(localized: "오늘 기록 없음", comment: "VoiceOver: friend logged nothing today")
                            : String(localized: "오늘 기록: \(MealType.allCases.filter { recorded.contains($0) }.map(\.displayName).formatted(.list(type: .and)))", comment: "VoiceOver: meals a friend logged today, e.g. 'Logged today: breakfast and lunch'"))
    }
}

/// 친구 목록 맨 위 — 오늘 누가 무엇을 올렸는지 사진으로 한눈에
struct FriendsTodayStrip: View {
    let friends: [Friend]
    let mealsByFriend: [String: [MealType: MealRecord]]
    let isLoading: Bool
    @Binding var notifyFriendMeals: Bool
    let onSelect: (Friend) -> Void

    /// 오늘 가장 최근에 올린 기록
    private func latest(_ friend: Friend) -> MealRecord? {
        mealsByFriend[friend.id]?.values.max { ($0.capturedAt ?? $0.date) < ($1.capturedAt ?? $1.date) }
    }

    /// 올린 사람 먼저(최근 순), 아직 안 올린 사람은 이름순으로 뒤에
    private var sortedFriends: [Friend] {
        friends.sorted { lhs, rhs in
            let lhsTime = latest(lhs).map { $0.capturedAt ?? $0.date }
            let rhsTime = latest(rhs).map { $0.capturedAt ?? $0.date }
            switch (lhsTime, rhsTime) {
            case let (l?, r?): return l > r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private var recordedCount: Int {
        friends.filter { !(mealsByFriend[$0.id]?.isEmpty ?? true) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("오늘 친구들")
                    .scaledFont(size: 17, weight: .bold)
                Text("\(recordedCount)/\(friends.count)명 기록")
                    .scaledFont(size: 13)
                    .foregroundColor(.secondary)
                if isLoading {
                    ProgressView().scaleEffect(0.7)
                }
                Spacer()
                Button {
                    notifyFriendMeals.toggle()
                } label: {
                    Image(systemName: notifyFriendMeals ? "bell.fill" : "bell.slash")
                        .font(.system(size: 17))
                        .foregroundColor(notifyFriendMeals ? .orange : .secondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("친구 기록 알림")
                .accessibilityValue(notifyFriendMeals ? "켜짐" : "꺼짐")
                .accessibilityHint("두 번 탭하면 친구가 기록을 올릴 때 알림을 받을지 바꿉니다")
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(sortedFriends) { friend in
                        Button {
                            onSelect(friend)
                        } label: {
                            FriendTodayCard(friend: friend,
                                            meals: mealsByFriend[friend.id] ?? [:],
                                            latest: latest(friend))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// 친구 한 명의 오늘 — 가장 최근 사진, 올린 끼니, 마지막 기록 시각
struct FriendTodayCard: View {
    let friend: Friend
    let meals: [MealType: MealRecord]
    let latest: MealRecord?

    private let size: CGFloat = 112

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter
    }()

    private var hasRecord: Bool { latest != nil }

    private var timeText: String? {
        latest?.capturedAt.map { Self.timeFormatter.string(from: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                if let data = latest?.afterImageData ?? latest?.beforeImageData,
                   let image = MealImageResizer.downsampledImage(from: data, maxPixel: size * 3) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(hasRecord ? Color.green.opacity(0.15) : Color(.systemGray6))
                        .frame(width: size, height: size)
                        .overlay(
                            VStack(spacing: 4) {
                                Text(String(friend.name.prefix(1)))
                                    .scaledFont(size: 30, weight: .bold)
                                    .foregroundColor(hasRecord ? .green : .secondary)
                                Text(hasRecord ? String(localized: "friend.loggedNoPhoto", defaultValue: "사진 없이 기록", comment: "Friend status: logged a meal without a photo") : String(localized: "아직 기록 전"))
                                    .scaledFont(size: 11)
                                    .foregroundColor(.secondary)
                            }
                        )
                }

                // 가장 최근 끼니
                if let latest {
                    HStack(spacing: 3) {
                        Image(systemName: latest.mealType.symbolName)
                        Text(latest.mealType.displayName)
                    }
                        .scaledFont(size: 11, weight: .semibold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(hasRecord ? Color.green.opacity(0.6) : Color.clear, lineWidth: 2)
            )

            Text(friend.name)
                .scaledFont(size: 13, weight: .semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 6) {
                MealDotsView(recorded: Set(meals.keys))
                Spacer(minLength: 0)
                Text(timeText ?? " ")
                    .scaledFont(size: 11)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: size)
        .opacity(hasRecord ? 1 : 0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasRecord
                            ? (timeText.map { String(localized: "\(friend.name), 오늘 \(meals.count)끼 기록, 마지막 \($0)", comment: "VoiceOver: friend name, meals logged today, time of the last one") }
                               ?? String(localized: "\(friend.name), 오늘 \(meals.count)끼 기록", comment: "VoiceOver: friend name, meals logged today"))
                            : String(localized: "\(friend.name), 오늘 아직 기록 없음", comment: "VoiceOver: friend has not logged today"))
        .accessibilityHint("두 번 탭하여 \(friend.name)님의 기록 보기")
    }
}

/// 최근 7일 × 끼니 — 친구가 언제 무엇을 올렸는지 한 장으로. 기록 있는 날을 누르면 그 날로 이동한다.
struct FriendWeekOverview: View {
    let allMeals: [Date: [MealType: MealRecord]]
    let onSelectDay: (Date) -> Void

    private let rows: [MealType] = [.breakfast, .lunch, .dinner]

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    private static let accessibilityDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("최근 7일")
                    .scaledFont(size: 14, weight: .semibold)
                Spacer()
                Text("\(days.filter { !(allMeals[$0]?.isEmpty ?? true) }.count)일 기록")
                    .scaledFont(size: 12)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    dayColumn(day)
                }
            }

            // 색만으로 구분하지 않도록 칸의 줄마다 끼니 이름을 범례로 둔다
            HStack(spacing: 12) {
                ForEach(rows, id: \.self) { meal in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(meal.symbolColor)
                            .frame(width: 10, height: 8)
                        Text(meal.displayName)
                            .scaledFont(size: 11)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func dayColumn(_ day: Date) -> some View {
        let meals = allMeals[day] ?? [:]
        let isToday = Calendar.current.isDateInToday(day)
        let recordedNames = MealType.allCases.filter { meals[$0] != nil }.map(\.displayName)

        return Button {
            onSelectDay(day)
        } label: {
            VStack(spacing: 5) {
                Text(Self.weekdayFormatter.string(from: day))
                    .scaledFont(size: 11, weight: isToday ? .bold : .regular)
                    .foregroundColor(isToday ? .primary : .secondary)
                ForEach(rows, id: \.self) { meal in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(meals[meal] != nil ? meal.symbolColor : Color(.systemGray5))
                        .frame(width: 22, height: 14)
                }
                Text("\(Calendar.current.component(.day, from: day))")
                    .scaledFont(size: 10)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(isToday ? Color.blue.opacity(0.08) : Color.clear))
        }
        .buttonStyle(.plain)
        .disabled(meals.isEmpty)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recordedNames.isEmpty
                            ? String(localized: "\(Self.accessibilityDayFormatter.string(from: day)), 기록 없음", comment: "VoiceOver: day, nothing logged")
                            : String(localized: "\(Self.accessibilityDayFormatter.string(from: day)), \(recordedNames.formatted(.list(type: .and))) 기록", comment: "VoiceOver: day, meals logged that day"))
        .accessibilityHint(meals.isEmpty ? "" : "두 번 탭하여 이 날 기록으로 이동")
    }
}

// 받은 친구 요청 행 (수락/거절)
struct FriendRequestRow: View {
    let request: FriendRequest
    @ObservedObject var friendManager = FriendManager.shared
    @State private var isWorking = false
    @State private var workingLabel = ""
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 44, height: 44)
                Text(String(request.name.prefix(1)))
                    .scaledFont(size: 20, weight: .bold)
                    .foregroundColor(.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(request.name)
                    .scaledFont(size: 16, weight: .semibold)
                Text(request.code)
                    .scaledFont(size: 13, design: .monospaced)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isWorking {
                HStack(spacing: 6) {
                    ProgressView()
                    Text(workingLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Button("수락") {
                    perform(String(localized: "수락 중...", comment: "Accepting a friend request")) { try await friendManager.acceptFriendRequest(request) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("거절") {
                    perform(String(localized: "거절 중...", comment: "Declining a friend request")) { try await friendManager.rejectFriendRequest(request) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }

        if let errorText {
            Label(errorText, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(request.name)님의 친구 요청")
    }

    private func perform(_ label: String, _ work: @escaping () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        workingLabel = label
        errorText = nil

        _Concurrency.Task {
            do {
                try await work()
            } catch {
                errorText = String(localized: "처리하지 못했어요. \(error.localizedDescription)", comment: "Friend request action failed, with reason")
            }
            isWorking = false
        }
    }
}

// 내가 보낸 요청 행 (대기 중 / 거절됨)
struct PendingFriendRow: View {
    let pending: PendingFriend
    @ObservedObject var friendManager = FriendManager.shared
    @State private var isWorking = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: pending.isRejected ? "person.badge.minus" : "clock")
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(pending.name)
                    .scaledFont(size: 16, weight: .semibold)
                Text(pending.isRejected ? "요청이 거절됐어요" : "수락 대기 중 · \(pending.code)")
                    .scaledFont(size: 13)
                    .foregroundColor(pending.isRejected ? .red : .secondary)
            }

            Spacer()

            if isWorking {
                ProgressView()
            } else {
                Button(pending.isRejected ? "지우기" : "요청 취소") {
                    isWorking = true
                    _Concurrency.Task {
                        try? await friendManager.cancelFriendRequest(pending)
                        isWorking = false
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// 쉼표/공백/줄바꿈으로 구분된 여러 친구 코드 파싱 (6자리 영숫자, 중복 제거)
func parseFriendCodes(_ text: String) -> [String] {
    let tokens = text.uppercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
    var seen = Set<String>()
    return tokens.filter { $0.count == 6 && seen.insert($0).inserted }
}

// 친구 요청 시트 — 보내는 중/결과를 시트 안에서 끝까지 보여준다
// (예전에는 시트를 닫은 뒤 부모에서 알럿을 띄워, 닫히는 도중 알럿이 묻히면 아무 반응도 없어 보였다)
struct AddFriendSheet: View {
    @Binding var friendCode: String
    let onSend: (String) async throws -> Void

    @State private var phase: Phase = .input
    @Environment(\.dismiss) var dismiss

    enum Phase: Equatable {
        case input
        case working(done: Int, total: Int)
        case finished(sent: Int, failures: [String])
    }

    private var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    private var parsedCodes: [String] {
        parseFriendCodes(friendCode)
    }

    var body: some View {
        NavigationView {
            Group {
                if case .finished(let sent, let failures) = phase {
                    resultView(sent: sent, failures: failures)
                } else {
                    inputView
                }
            }
            .navigationTitle("친구 요청")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") { dismiss() }
                        .disabled(isWorking)
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    // 키보드가 올라와도 위가 잘리거나 버튼이 가리지 않게 스크롤 (그룹 만들기·참여 시트와 같은 방식)
    private var inputView: some View {
        ScrollView {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("친구 요청 보내기")
                    .scaledFont(size: 24, weight: .bold)

                Text("친구가 공유한 6자리 코드를 입력하세요.\n상대가 수락해야 서로의 기록을 볼 수 있어요.\n여러 명은 쉼표나 줄바꿈으로 구분해 한 번에 보낼 수 있습니다.")
                    .scaledFont(size: 14)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)

            TextField("예: ABC123, DEF456", text: $friendCode, axis: .vertical)
                .scaledFont(size: 20, weight: .bold, design: .monospaced)
                .multilineTextAlignment(.center)
                .textCase(.uppercase)
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
                .lineLimit(1...5)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                .disabled(isWorking)

            Button {
                send()
            } label: {
                HStack(spacing: 8) {
                    if case .working = phase {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(buttonTitle)
                        .scaledFont(size: 18, weight: .semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(parsedCodes.isEmpty || isWorking ? Color.gray : Color.blue)
                .cornerRadius(12)
            }
            .disabled(parsedCodes.isEmpty || isWorking)
            .padding(.horizontal)

            if isWorking {
                Text("iCloud에 요청을 등록하고 있어요. 잠시만 기다려주세요.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var buttonTitle: String {
        switch phase {
        case .working(let done, let total):
            return total > 1
                ? String(localized: "요청 보내는 중... (\(done)/\(total))", comment: "Sending friend requests, progress done/total")
                : String(localized: "요청 보내는 중...", comment: "Sending a friend request")
        default:
            return parsedCodes.count > 1
                ? String(localized: "\(parsedCodes.count)명에게 요청", comment: "Button: send requests to N people")
                : String(localized: "친구 요청 보내기", comment: "Button: send a friend request")
        }
    }

    private func resultView(sent: Int, failures: [String]) -> some View {
        VStack(spacing: 18) {
            Image(systemName: failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(failures.isEmpty ? .green : .orange)

            Text(headline(sent: sent, failures: failures))
                .scaledFont(size: 20, weight: .bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if sent > 0 {
                Text("상대가 수락하면 서로의 기록을 볼 수 있어요.\n보낸 요청은 친구 화면에서 확인할 수 있습니다.")
                    .scaledFont(size: 14)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if !failures.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(failures, id: \.self) { failure in
                            Text(failure)
                                .scaledFont(size: 13)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                .frame(maxHeight: 200)
            }

            Button {
                dismiss()
            } label: {
                Text("완료")
                    .scaledFont(size: 18, weight: .semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal)

            if !failures.isEmpty {
                Button("코드 다시 입력") {
                    phase = .input
                }
                .scaledFont(size: 15, weight: .semibold)
            }

            Spacer()
        }
        .padding(.top, 32)
    }

    private func headline(sent: Int, failures: [String]) -> String {
        if failures.isEmpty {
            return sent == 1
                ? String(localized: "친구 요청을 보냈어요", comment: "One friend request sent")
                : String(localized: "\(sent)명에게 친구 요청을 보냈어요", comment: "Friend requests sent to N people")
        }
        if sent == 0 {
            return String(localized: "요청을 보내지 못했어요", comment: "No friend request could be sent")
        }
        return String(localized: "\(sent)명 전송, \(failures.count)명 실패", comment: "N requests sent, M failed")
    }

    private func send() {
        let codes = parsedCodes
        guard !codes.isEmpty, !isWorking else { return }

        phase = .working(done: 0, total: codes.count)

        _Concurrency.Task {
            var sent = 0
            var failures: [String] = []

            for (index, code) in codes.enumerated() {
                phase = .working(done: index, total: codes.count)
                do {
                    try await onSend(code)
                    sent += 1
                } catch {
                    failures.append("\(code): \(error.localizedDescription)")
                }
            }

            if failures.isEmpty { friendCode = "" }
            phase = .finished(sent: sent, failures: failures)
        }
    }
}

// 친구 기록 보기 뷰 (음식 / 운동)
struct FriendMealsView: View {
    let friend: Friend
    @ObservedObject var friendManager = FriendManager.shared
    /// 음식 / 운동 — 무엇을 보여줄지. 예전에는 타임라인/그리드(보기 방식)였는데,
    /// 보기 방식보다 "무엇을 보는지"가 먼저 정해져야 할 선택이라 바꿨다.
    @State private var album: AlbumType = .diet
    @State private var dateList: [Date] = []
    @State private var loadedPastDays = 7
    @State private var isLoadingPast = false
    @State private var allMeals: [Date: [MealType: MealRecord]] = [:]
    @State private var currentVisibleDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var safetyTarget: SafetyTarget?
    /// 불러오기 실패 사유 — 실패한 날을 "기록 없음" 으로 치지 않고 다시 시도할 수 있게 보여 준다
    @State private var loadError: String?
    @Environment(\.dismiss) var dismiss

    /// 기록 없는 날은 건너뛰며 과거로 확장하되, 여기까지만 거슬러 올라간다
    static let maxLookbackDays = 365

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 무엇을 볼지 — 음식 / 운동
                Picker("보기", selection: $album) {
                    ForEach(AlbumType.allCases, id: \.self) { type in
                        Label(type.shareTitle, systemImage: type.symbolName)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                TimelineView(
                    friend: friend,
                    album: album,
                    friendManager: friendManager,
                    dateList: $dateList,
                    loadedPastDays: $loadedPastDays,
                    isLoadingPast: $isLoadingPast,
                    allMeals: $allMeals,
                    currentVisibleDate: $currentVisibleDate,
                    loadMorePastDates: loadMorePastDates,
                    onRefresh: refreshLoadedDates,
                    loadError: loadError,
                    onRetry: loadInitialMeals
                )
            }
            .navigationTitle(friend.name)   // 음식/운동은 바로 아래 선택에 보인다 — 긴 이름이 잘리지 않게
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("닫기") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        safetyTarget = SafetyTarget(userId: friend.id, code: friend.code, name: friend.name, isFriend: true)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("끊기, 차단, 신고")
                }
            }
            .userSafetyActions($safetyTarget)
            .onAppear {
                initializeDateList()
                loadInitialMeals()
            }
            .onChange(of: album) { _, _ in
                // 앨범이 바뀌면 보여줄 것이 통째로 달라진다 — 쌓아 둔 것을 비우고 다시 받는다
                allMeals = [:]
                loadInitialMeals()
            }
        }
    }

    private func initializeDateList() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        dateList = ((-loadedPastDays)...0).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
        }.reversed()
    }

    private func loadInitialMeals() {
        isLoadingPast = true
        _Concurrency.Task {
            await load(dates: dateList)
            await MainActor.run { isLoadingPast = false }
        }
    }

    private func loadMorePastDates() {
        guard !isLoadingPast, loadedPastDays < Self.maxLookbackDays else { return }
        isLoadingPast = true

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let newPastDays = min(loadedPastDays + 14, Self.maxLookbackDays)

        let newDates = ((-newPastDays)...(-loadedPastDays - 1)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
        }.reversed()

        dateList.append(contentsOf: newDates)
        loadedPastDays = newPastDays

        _Concurrency.Task {
            await load(dates: Array(newDates))
            await MainActor.run { isLoadingPast = false }
        }
    }

    /// 당겨서 새로고침: 이미 불러온 날짜의 캐시를 버리고 다시 받아온다.
    /// (지난 날짜 캐시는 만료되지 않으므로, 친구가 예전 기록을 고쳤을 때의 탈출구)
    private func refreshLoadedDates() async {
        let dates = dateList
        for date in dates {
            friendManager.invalidateCache(friendId: friend.id, date: date)
        }
        await load(dates: dates)
    }

    /// 날짜 묶음을 한 번에 조회. 기록 없는 날도 빈 값으로 남겨 같은 날을 다시 요청하지 않는다.
    private func load(dates: [Date]) async {
        guard !dates.isEmpty else { return }

        do {
            let loaded = try await friendManager.loadFriendMealsBatch(friendId: friend.id, dates: dates,
                                                                      album: album)
            await MainActor.run {
                for (date, meals) in loaded { allMeals[date] = meals }
                loadError = nil
            }
        } catch {
            // 실패한 날을 빈 날로 치면 "기록이 없어요" 로 보이고 과거로 계속 헛걸음한다 — 실패로 남긴다
            print("❌ 기록 로드 실패: \(error)")
            await MainActor.run {
                loadError = String(localized: "기록을 불러오지 못했어요. 인터넷 연결을 확인해 주세요.")
            }
        }
    }
}

// 타임라인 뷰 — 기록이 있는 날만 보여준다 (빈 날은 아예 숨김)
struct TimelineView: View {
    let friend: Friend
    /// 지금 보고 있는 탭 (음식/운동). 응원이 엉뚱한 기록에 달리지 않도록 끝까지 따라간다.
    var album: AlbumType = .diet
    @ObservedObject var friendManager: FriendManager
    @Binding var dateList: [Date]
    @Binding var loadedPastDays: Int
    @Binding var isLoadingPast: Bool
    @Binding var allMeals: [Date: [MealType: MealRecord]]
    @Binding var currentVisibleDate: Date
    let loadMorePastDates: () -> Void
    let onRefresh: () async -> Void
    var loadError: String? = nil
    var onRetry: () -> Void = {}

    /// 오늘 기록이 아직 하나도 없는지
    private var todayIsEmpty: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return (allMeals[today]?.isEmpty ?? true)
    }

    /// 기록이 남아 있는 날짜만
    private var recordedDates: [Date] {
        dateList.filter { !(allMeals[$0]?.isEmpty ?? true) }
    }

    private var canLoadMore: Bool {
        loadedPastDays < FriendMealsView.maxLookbackDays
    }

    /// 헤더에 표시할 날짜 (아직 스크롤 전이면 가장 최근 기록일)
    private var headerDate: Date {
        recordedDates.contains(currentVisibleDate) ? currentVisibleDate : (recordedDates.first ?? currentVisibleDate)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header(proxy: proxy)

                // 최근 일주일을 한 장으로 — 누르면 그 날로 이동
                FriendWeekOverview(allMeals: allMeals) { day in
                    withAnimation { proxy.scrollTo(day, anchor: .top) }
                }

                Divider()

                timeline
            }
        }
    }

    private func header(proxy: ScrollViewProxy) -> some View {
        HStack {
            Text(headerDate, style: .date)
                .font(.headline)

            Spacer()

            Button {
                if let latest = recordedDates.first {
                    withAnimation { proxy.scrollTo(latest, anchor: .top) }
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            .disabled(recordedDates.isEmpty)
            .accessibilityLabel("최신 기록으로")
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var timeline: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // 오늘 아직 아무것도 안 올렸으면 콕 찌를 자리를 준다.
                // 타임라인은 기록이 있는 날만 보여주므로, 이 줄이 없으면 "안 한 사람"을
                // 재촉할 방법이 아예 사라진다 (예전에는 그리드의 빈 칸이 그 역할을 했다).
                if todayIsEmpty && !isLoadingPast {
                    NudgeTodayRow(friend: friend, album: album)
                }

                if recordedDates.isEmpty && !isLoadingPast {
                    emptyState
                }

                ForEach(recordedDates, id: \.self) { date in
                    FriendDailySectionView(
                        date: date,
                        friend: friend,
                        meals: allMeals[date] ?? [:],
                        album: album   // 빠지면 운동 탭의 응원이 식단 기록에 달린다
                    )
                    .id(date)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: DatePositionPreferenceKey.self,
                                value: [date: geometry.frame(in: .named("scroll")).minY]
                            )
                        }
                    )
                }

                footer
            }
            .onPreferenceChange(DatePositionPreferenceKey.self) { positions in
                if let topDate = positions.min(by: { abs($0.value) < abs($1.value) })?.key,
                   currentVisibleDate != topDate {
                    currentVisibleDate = topDate
                }
            }
        }
        .coordinateSpace(name: "scroll")
        .refreshable {
            await onRefresh()
        }
        .onChange(of: isLoadingPast) { _, loading in
            // 불러온 구간이 통째로 비어 있으면 기록이 나올 때까지 계속 과거로 확장
            if !loading && recordedDates.isEmpty && canLoadMore && loadError == nil {
                loadMorePastDates()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: loadError == nil ? "photo.on.rectangle.angled" : "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(.gray)
                .accessibilityHidden(true)

            if let loadError {
                Text(loadError)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("다시 시도", action: onRetry)
                    .scaledFont(size: 15, weight: .semibold)
            } else {
                Text(album == .exercise ? "아직 운동 기록이 없어요" : "아직 음식 기록이 없어요")
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    @ViewBuilder
    private var footer: some View {
        Group {
            if isLoadingPast {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("이전 기록 불러오는 중...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if canLoadMore {
                Button("이전 기록 더 보기") {
                    loadMorePastDates()
                }
                .scaledFont(size: 14, weight: .semibold)
                .onAppear { loadMorePastDates() }
            } else if !recordedDates.isEmpty {
                Text("더 이상 기록이 없어요")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// 오늘 아직 기록이 없는 친구를 재촉하는 줄.
///
/// 예전에는 그리드의 빈 칸을 눌러 콕 찌르거나 응원을 남겼는데, 그리드를 없애면서
/// 그 길이 사라졌다. 타임라인은 기록이 있는 날만 그리기 때문이다.
struct NudgeTodayRow: View {
    let friend: Friend
    var album: AlbumType = .diet

    @State private var showingMealPicker = false
    @State private var commentTarget: MealType?
    @State private var pokingMeal: MealType?
    @State private var pokedMeals: Set<MealType> = []

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    /// 재촉할 끼니 — 운동은 끼니 개념이 흐리므로 정규 세 끼만 고르게 한다
    private var pokeTargets: [MealType] { [.breakfast, .lunch, .dinner] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hand.point.right.fill")
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)
                Text(album == .exercise
                     ? "\(friend.name)님이 오늘 아직 운동 기록이 없어요"
                     : "\(friend.name)님이 오늘 아직 음식 기록이 없어요")
                    .scaledFont(size: 14, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    showingMealPicker = true
                } label: {
                    Label("콕 찌르기", systemImage: "hand.point.right")
                        .scaledFont(size: 14, weight: .semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                        .foregroundColor(.orange)
                }
                .disabled(pokingMeal != nil)

                if !pokedMeals.isEmpty {
                    Text("보냈어요")
                        .scaledFont(size: 13)
                        .foregroundColor(.secondary)
                }

                if pokingMeal != nil {
                    ProgressView().scaleEffect(0.7)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.07))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.top, 12)
        .confirmationDialog(album == .exercise ? "어느 운동을 재촉할까요?" : "어느 음식을 재촉할까요?",
                            isPresented: $showingMealPicker, titleVisibility: .visible) {
            ForEach(pokeTargets, id: \.self) { mealType in
                Button("👉 \(mealType.displayName) 콕 찌르기") { sendPoke(mealType) }
                Button("\(mealType.displayName)에 응원 남기기") { commentTarget = mealType }
            }
            Button("취소", role: .cancel) { }
        }
        .sheet(item: $commentTarget) { mealType in
            QuickFeedbackView(friend: friend, date: today, mealType: mealType, album: album)
        }
        .accessibilityElement(children: .contain)
    }

    private func sendPoke(_ mealType: MealType) {
        guard pokingMeal == nil else { return }
        pokingMeal = mealType

        _Concurrency.Task {
            do {
                try await FriendManager.shared.addFeedback(
                    to: friend.id,
                    date: today,
                    mealType: mealType,
                    content: "👉 콕! \(mealType.displayName) 기록을 기다리고 있어요",
                    album: album
                )
                pokedMeals.insert(mealType)
            } catch {
                print("❌ [NudgeTodayRow] 콕 찌르기 실패: \(error)")
            }
            pokingMeal = nil
        }
    }
}
// 친구 식단 상세 보기 (사진 크게 보기)
struct FriendMealDetailView: View {
    let meal: MealRecord
    let mealType: MealType
    let friend: Friend
    let date: Date
    /// 지금 보고 있는 탭 (음식/운동). 응원이 엉뚱한 기록에 달리지 않도록 끝까지 따라간다.
    var album: AlbumType = .diet
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 식전 사진
                    if let beforeData = meal.beforeImageData,
                       let image = UIImage(data: beforeData) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("식전")
                                .font(.headline)
                                .padding(.horizontal)

                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(12)
                                .padding(.horizontal)
                        }
                    }

                    // 식후 사진
                    if let afterData = meal.afterImageData,
                       let image = UIImage(data: afterData) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("식후")
                                .font(.headline)
                                .padding(.horizontal)

                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(12)
                                .padding(.horizontal)
                        }
                    }

                    // 메모
                    if let memo = meal.memo, !memo.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("메모")
                                .font(.headline)
                                .padding(.horizontal)

                            Text(memo)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .padding(.horizontal)
                        }
                    }

                    // 응원 — 이모지 반응 + 지금까지의 대화 + 글 쓰기
                    FriendFeedbackSection(friendId: friend.id, date: date, mealType: mealType, album: album)
                        .padding(.horizontal)
                        .padding(.vertical)
                }
                .padding(.vertical)
            }
            .navigationTitle("\(mealType.displayName) - \(meal.date, style: .date)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// 친구 식단 날짜별 섹션
struct FriendDailySectionView: View {
    let date: Date
    let friend: Friend
    let meals: [MealType: MealRecord]
    /// 지금 보고 있는 탭 (음식/운동). 응원이 엉뚱한 기록에 달리지 않도록 끝까지 따라간다.
    var album: AlbumType = .diet

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 날짜 구분선
            HStack {
                Text(date, format: .dateTime.month().day().weekday(.wide))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))

            // 식단 카드들
            VStack(spacing: 16) {
                ForEach(MealType.allCases, id: \.self) { mealType in
                    if let meal = meals[mealType] {
                        FriendMealCard(mealType: mealType, meal: meal, friend: friend, date: date, album: album)
                    }
                }
            }
            .padding()
        }
    }
}

// 친구 식단 카드 (사진 원본 비율 유지 + 응원 남기기)
struct FriendMealCard: View {
    let mealType: MealType
    let meal: MealRecord
    // 그룹 피드에서도 같은 카드를 쓰는데 거기엔 대상 친구·날짜가 없다 →
    // 둘 다 있을 때만 응원 버튼을 붙인다
    var friend: Friend? = nil
    var date: Date? = nil
    /// 지금 보고 있는 탭 (음식/운동). 응원이 엉뚱한 기록에 달리지 않도록 끝까지 따라간다.
    var album: AlbumType = .diet

    @State private var showingFeedback = false

    // 친구가 실제로 기록한 시각. 없으면(예전 데이터) 시간 줄 자체를 감춘다.
    private var capturedTimeText: String? {
        guard let captured = meal.capturedAt else { return nil }
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("jmm")
        return fmt.string(from: captured)
    }

    // 정사각형으로 채운 사진 + 왼쪽 위 이름표 (식전·식후 나란히 볼 때)
    private func labeledPhoto(_ image: UIImage, label: LocalizedStringKey) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topLeading) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
                    .padding(6)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 헤더 — 끼니 이름이 길어져도 시간이 밀려 잘리지 않도록 시간에 고정 폭을 준다
            HStack(spacing: 8) {
                Image(systemName: mealType.symbolName)
                    .foregroundColor(mealType.symbolColor)
                    .scaledFont(size: 20)
                Text(mealType.displayName)
                    .scaledFont(size: 20, weight: .bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                // 식사 시간 (절대 잘리지 않게)
                if let timeText = capturedTimeText {
                    Text(timeText)
                        .scaledFont(size: 14, weight: .medium)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel("기록 시각 \(timeText)")
                }
            }

            // 식전·식후가 다 있으면 나란히 (예전엔 식전만 보여서 친구는 식후 사진을 볼 수 없었다)
            if let before = meal.beforeImageData.flatMap(UIImage.init(data:)),
               let after = meal.afterImageData.flatMap(UIImage.init(data:)) {
                HStack(spacing: 8) {
                    labeledPhoto(before, label: "식전")
                    labeledPhoto(after, label: "식후")
                }
            } else if let image = (meal.beforeImageData ?? meal.afterImageData).flatMap(UIImage.init(data:)) {
                // 이미지 — 원본 비율 그대로(잘라내지 않음)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 360)
                    .cornerRadius(12)
            } else {
                // 이미지 없을 때 플레이스홀더
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(height: 150)

                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("사진 없음")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // 메모 (길어도 잘리지 않고 전부 보이게)
            if let memo = meal.memo, !memo.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("메모")
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundColor(.secondary)
                    Text(memo)
                        .scaledFont(size: 14)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("메모 없음")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 응원 남기기 (타임라인에서도 바로 피드백 가능)
            if let friend {
                Button {
                    showingFeedback = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.fill")
                        Text("응원 남기기")
                    }
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.solidOrange)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("응원 남기기")
                .accessibilityHint("\(friend.name)님의 \(mealType.displayName)에 응원 메시지를 보냅니다")
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        .sheet(isPresented: $showingFeedback) {
            if let friend, let date {
                QuickFeedbackView(friend: friend, date: date, mealType: mealType, album: album)
            }
        }
    }
}

// 계정 설정 시트
struct AccountSettingsSheet: View {
    let onDeleteAccount: () -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject var friendManager = FriendManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared

    // 타이핑하는 동안은 로컬 값만 바꾸고, 편집을 마칠 때 한 번 반영한다
    @State private var nicknameDraft = ""
    @FocusState private var isNicknameFocused: Bool

    var body: some View {
        NavigationView {
            List {
                // 계정 정보 섹션
                Section {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("iCloud 계정")
                                .scaledFont(size: 18, weight: .semibold)

                            Text(friendManager.myUserId.isEmpty ? "" : "연결됨")
                                .scaledFont(size: 14)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 8)
                }

                // 친구에게 보이는 이름
                Section {
                    HStack {
                        Text("이름")
                        Spacer()
                        TextField("이름 입력", text: $nicknameDraft)
                            .multilineTextAlignment(.trailing)
                            .focused($isNicknameFocused)
                            .submitLabel(.done)
                            .onSubmit { commitNickname() }
                    }
                } header: {
                    Text("친구에게 보이는 이름")
                } footer: {
                    Text("친구·그룹 화면에서 상대에게 이 이름으로 보입니다. 최대 20자.")
                }

                // 내 친구 코드
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("내 친구 코드")
                                .scaledFont(size: 14)
                                .foregroundColor(.secondary)

                            Text(friendManager.myUserCode)
                                .scaledFont(size: 20, weight: .bold, design: .monospaced)
                                .foregroundColor(.blue)
                        }

                        Spacer()

                        Button(action: {
                            UIPasteboard.general.string = friendManager.myUserCode
                        }) {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("친구 코드 복사")
                    }

                    if !friendManager.myUserCode.isEmpty {
                        ShareLink(item: FriendInvite.message(code: friendManager.myUserCode)) {
                            Label("친구 초대하기", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                // 회원 탈퇴
                Section {
                    Button(action: {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onDeleteAccount()
                        }
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("회원 탈퇴")
                                .foregroundColor(.red)
                        }
                    }
                } footer: {
                    Text("회원 탈퇴 시 모든 친구 관계 및 공유 데이터가 삭제되며 복구할 수 없습니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("계정 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") {
                        commitNickname()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") {
                        commitNickname()
                        isNicknameFocused = false
                    }
                }
            }
            .onAppear { nicknameDraft = settingsManager.displayNickname }
            .onDisappear { commitNickname() }
        }
    }

    private func commitNickname() {
        settingsManager.commitNickname(nicknameDraft)
        nicknameDraft = settingsManager.displayNickname
    }
}

// iCloud 로그인 안내 화면 (별도 로그인 없이 기기의 iCloud 계정을 사용)
struct ICloudRequiredView: View {
    @ObservedObject private var friendManager = FriendManager.shared

    var body: some View {
        // 작은 화면에서 아래 버튼이 잘리지 않게 스크롤 (넉넉하면 가운데 정렬 그대로)
        ScrollView {
        VStack(spacing: 32) {
            Spacer(minLength: 40)

            // 아이콘
            Image(systemName: "person.2.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            // 제목
            VStack(spacing: 12) {
                Text("친구 기능")
                    .scaledFont(size: 32, weight: .bold)

                Text("친구와 식단을 공유하고\n서로의 식습관을 응원하세요")
                    .scaledFont(size: 16)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 16)

            VStack(spacing: 12) {
                Image(systemName: friendManager.accountCheckFailed ? "icloud.slash" : "icloud")
                    .scaledFont(size: 32)
                    .foregroundColor(.secondary)

                // 연결 문제와 로그인 안 됨을 구분한다 — 로그인한 사람에게 "로그인하세요" 라고 하지 않도록
                Text(friendManager.accountCheckFailed ? "iCloud에 연결하지 못했어요" : "iCloud 로그인이 필요해요")
                    .scaledFont(size: 16, weight: .semibold)

                Text(friendManager.accountCheckFailed
                     ? "인터넷 연결을 확인한 뒤 다시 시도해 주세요"
                     : "설정 앱에서 iCloud에 로그인하면\n친구 추가 및 식단 공유 기능을 사용할 수 있습니다")
                    .scaledFont(size: 13)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 16) {
                Button("다시 시도") { friendManager.recheckAccount() }
                    .scaledFont(size: 16, weight: .semibold)
                if !friendManager.accountCheckFailed, let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("설정 열기", destination: url)
                        .scaledFont(size: 16, weight: .semibold)
                }
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("친구")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// 타임라인에서 빠른 피드백 작성
struct QuickFeedbackView: View {
    let friend: Friend
    let date: Date
    let mealType: MealType
    /// 지금 보고 있는 탭 (음식/운동). 응원이 엉뚱한 기록에 달리지 않도록 끝까지 따라간다.
    var album: AlbumType = .diet

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 8) {
                        Text("\(friend.name)님의 \(mealType.displayName)")
                            .font(.headline)
                        Text(date, style: .date)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top)

                    FriendFeedbackSection(friendId: friend.id, date: date, mealType: mealType, album: album)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("응원하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 친구 초대

enum FriendInvite {
    /// 메시지·카톡으로 보낼 초대 문구 — 코드와 앱 받기 링크
    static func message(code: String) -> String {
        let link = RoutineCameraSpec.appStoreID.map { "https://apps.apple.com/app/id\($0)" } ?? ""
        return String(localized: "세끼에서 같이 식사 기록해요! 앱에서 친구 추가 ▸ 코드 \(code) 를 입력하면 서로의 식사를 볼 수 있어요.") + (link.isEmpty ? "" : "\n" + link)
    }
}
