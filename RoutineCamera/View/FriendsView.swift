//
//  FriendsView.swift
//  RoutineCamera
//
//  친구 목록 및 관리 화면
//

import SwiftUI

struct FriendsView: View {
    @ObservedObject var friendManager = FriendManager.shared
    @State private var showingAddFriend = false
    @State private var friendCode = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedFriend: Friend?
    @State private var showingAccountSettings = false
    @State private var showingDeleteConfirm = false
    @State private var showingGroups = false
    @State private var infoMessage = ""
    @State private var showingInfo = false

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

    private var friendsContentView: some View {
        VStack(spacing: 0) {
                // 내 코드 섹션
                VStack(spacing: 12) {
                    Text("내 친구 코드")
                        .font(.system(size: 14, weight: .semibold))
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
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("내 친구 코드")
                                .accessibilityValue(friendManager.myUserCode.map { String($0) }.joined(separator: " "))

                            Button(action: {
                                UIPasteboard.general.string = friendManager.myUserCode
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 20))
                                    .foregroundColor(.blue)
                            }
                            .accessibilityLabel("친구 코드 복사")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

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

                    Section("친구") {
                        if friendManager.friends.isEmpty {
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
                                    errorMessage = "샘플 친구가 생성되었습니다!\n코드 'ABCABC'로 추가할 수 있습니다."
                                    showingError = true
                                } catch {
                                    errorMessage = "샘플 데이터 생성 실패: \(error.localizedDescription)"
                                    showingError = true
                                }
                            }
                        }) {
                            Image(systemName: "testtube.2")
                                .font(.system(size: 20))
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
                                .font(.system(size: 20))
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
                                .font(.system(size: 20))
                        }
                        .accessibilityLabel("그룹")

                        Button(action: {
                            showingAddFriend = true
                        }) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 20))
                        }
                        .accessibilityLabel("친구 요청 보내기")
                    }
                }
            }
            .sheet(isPresented: $showingAddFriend) {
                AddFriendSheet(
                    friendCode: $friendCode,
                    onAdd: {
                        _Concurrency.Task {
                            // 쉼표/공백/줄바꿈으로 구분된 여러 코드 일괄 추가 (이벤트용)
                            let codes = parseFriendCodes(friendCode)
                            var addedCount = 0
                            var failures: [String] = []

                            for code in codes {
                                do {
                                    try await friendManager.sendFriendRequest(code: code)
                                    addedCount += 1
                                } catch {
                                    failures.append("\(code): \(error.localizedDescription)")
                                }
                            }

                            friendCode = ""
                            showingAddFriend = false

                            if !failures.isEmpty {
                                errorMessage = "\(addedCount)명에게 요청 전송, \(failures.count)개 실패\n\n" + failures.joined(separator: "\n")
                                showingError = true
                            } else if addedCount > 0 {
                                infoMessage = addedCount == 1
                                    ? "친구 요청을 보냈어요. 상대가 수락하면 서로의 기록을 볼 수 있어요."
                                    : "\(addedCount)명에게 친구 요청을 보냈어요. 상대가 수락하면 서로의 기록을 볼 수 있어요."
                                showingInfo = true
                            }
                        }
                    }
                )
            }
            .sheet(item: $selectedFriend) { friend in
                FriendMealsView(friend: friend)
            }
            .sheet(isPresented: $showingGroups) {
                GroupsView()
            }
            .alert("알림", isPresented: $showingInfo) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(infoMessage)
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
                            errorMessage = "회원 탈퇴 실패: \(error.localizedDescription)"
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
                // 화면 진입 시 받은 요청·수락 여부를 최신으로 (푸시를 탭해 들어온 경우 포함)
                await friendManager.refreshSocialGraph()
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.secondary)

            Text("친구 코드로 요청을 보내면\n상대가 수락한 뒤 서로의 기록을 볼 수 있어요")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showingAddFriend = true }) {
                Label("친구 요청 보내기", systemImage: "person.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
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
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(friend.code)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(friend.name)")
        .accessibilityHint("두 번 탭하여 이 친구의 기록 보기")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                _Concurrency.Task {
                    try? await friendManager.removeFriend(friendId: friend.id)
                }
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }
    }

// 받은 친구 요청 행 (수락/거절)
struct FriendRequestRow: View {
    let request: FriendRequest
    @ObservedObject var friendManager = FriendManager.shared
    @State private var isWorking = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 44, height: 44)
                Text(String(request.name.prefix(1)))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(request.name)
                    .font(.system(size: 16, weight: .semibold))
                Text(request.code)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isWorking {
                ProgressView()
            } else {
                Button("수락") {
                    perform { try await friendManager.acceptFriendRequest(request) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("거절") {
                    perform { try await friendManager.rejectFriendRequest(request) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(request.name)님의 친구 요청")
    }

    private func perform(_ work: @escaping () async throws -> Void) {
        isWorking = true
        _Concurrency.Task {
            try? await work()
            isWorking = false
        }
    }
}

// 내가 보낸 요청 행 (대기 중 / 거절됨)
struct PendingFriendRow: View {
    let pending: PendingFriend
    @ObservedObject var friendManager = FriendManager.shared

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
                    .font(.system(size: 16, weight: .semibold))
                Text(pending.isRejected ? "요청이 거절됐어요" : "수락 대기 중 · \(pending.code)")
                    .font(.system(size: 13))
                    .foregroundColor(pending.isRejected ? .red : .secondary)
            }

            Spacer()

            Button(pending.isRejected ? "지우기" : "요청 취소") {
                _Concurrency.Task {
                    try? await friendManager.cancelFriendRequest(pending)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
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

// 친구 추가 시트
struct AddFriendSheet: View {
    @Binding var friendCode: String
    let onAdd: () -> Void
    @Environment(\.dismiss) var dismiss

    private var parsedCodes: [String] {
        parseFriendCodes(friendCode)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    Text("친구 요청 보내기")
                        .font(.system(size: 24, weight: .bold))

                    Text("친구가 공유한 6자리 코드를 입력하세요.\n상대가 수락해야 서로의 기록을 볼 수 있어요.\n여러 명은 쉼표나 줄바꿈으로 구분해 한 번에 보낼 수 있습니다.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                // 코드 입력 필드 (여러 코드 붙여넣기 가능)
                TextField("예: ABC123, DEF456", text: $friendCode, axis: .vertical)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textCase(.uppercase)
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
                    .lineLimit(1...5)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                Button(action: onAdd) {
                    Text(parsedCodes.count > 1 ? "\(parsedCodes.count)명에게 요청" : "친구 요청 보내기")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(parsedCodes.isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(12)
                }
                .disabled(parsedCodes.isEmpty)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("친구 요청")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// 친구 식단 보기 뷰
struct FriendMealsView: View {
    let friend: Friend
    @ObservedObject var friendManager = FriendManager.shared
    @State private var viewMode: ViewMode = .timeline
    @State private var dateList: [Date] = []
    @State private var loadedPastDays = 7
    @State private var isLoadingPast = false
    @State private var allMeals: [Date: [MealType: MealRecord]] = [:]
    @State private var currentVisibleDate: Date = Calendar.current.startOfDay(for: Date())
    @Environment(\.dismiss) var dismiss

    enum ViewMode {
        case timeline
        case grid
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 뷰 모드 선택 탭
                Picker("보기 모드", selection: $viewMode) {
                    Label("타임라인", systemImage: "list.bullet")
                        .tag(ViewMode.timeline)
                    Label("그리드", systemImage: "square.grid.2x2")
                        .tag(ViewMode.grid)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                // 선택된 모드에 따라 다른 뷰 표시
                if viewMode == .timeline {
                    TimelineView(
                        friend: friend,
                        friendManager: friendManager,
                        dateList: $dateList,
                        loadedPastDays: $loadedPastDays,
                        isLoadingPast: $isLoadingPast,
                        allMeals: $allMeals,
                        currentVisibleDate: $currentVisibleDate,
                        loadMorePastDates: loadMorePastDates
                    )
                } else {
                    GridView(
                        friend: friend,
                        friendManager: friendManager,
                        allMeals: $allMeals
                    )
                }
            }
            .navigationTitle("\(friend.name)의 식단")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                initializeDateList()
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
        _Concurrency.Task {
            for date in dateList {
                do {
                    let meals = try await friendManager.loadFriendMeals(friendId: friend.id, date: date)
                    await MainActor.run {
                        if !meals.isEmpty {
                            allMeals[date] = meals
                        }
                    }
                } catch {
                    print("❌ 식단 로드 실패 (\(date)): \(error)")
                }
            }
        }
    }

    private func loadMorePastDates() {
        guard !isLoadingPast else { return }
        isLoadingPast = true

        let calendar = Calendar.current
        let newPastDays = loadedPastDays + 7
        let today = calendar.startOfDay(for: Date())

        let newDates = ((-newPastDays)...(-loadedPastDays - 1)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
        }.reversed()

        dateList.append(contentsOf: newDates)
        loadedPastDays = newPastDays

        // 새 날짜들의 식단 로드
        _Concurrency.Task {
            for date in newDates {
                do {
                    let meals = try await friendManager.loadFriendMeals(friendId: friend.id, date: date)
                    await MainActor.run {
                        if !meals.isEmpty {
                            allMeals[date] = meals
                        }
                    }
                } catch {
                    print("❌ 식단 로드 실패 (\(date)): \(error)")
                }
            }
            await MainActor.run {
                isLoadingPast = false
            }
        }
    }
}

// 타임라인 뷰 (ContentView와 유사)
struct TimelineView: View {
    let friend: Friend
    @ObservedObject var friendManager: FriendManager
    @Binding var dateList: [Date]
    @Binding var loadedPastDays: Int
    @Binding var isLoadingPast: Bool
    @Binding var allMeals: [Date: [MealType: MealRecord]]
    @Binding var currentVisibleDate: Date
    let loadMorePastDates: () -> Void

    @State private var loadingDates: Set<String> = []

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // 현재 보이는 날짜 헤더
                HStack {
                    Text(currentVisibleDate, style: .date)
                        .font(.headline)
                    Spacer()
                    Button(action: {
                        let today = Calendar.current.startOfDay(for: Date())
                        withAnimation {
                            proxy.scrollTo(today, anchor: .top)
                        }
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                }
                .padding()
                .background(Color(.systemBackground))

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        ForEach(dateList, id: \.self) { date in
                            let dateString = dateFormatter.string(from: date)
                            let isLoading = loadingDates.contains(dateString) && allMeals[date] == nil

                            FriendDailySectionView(
                                date: date,
                                friend: friend,
                                meals: allMeals[date] ?? [:],
                                isLoading: isLoading
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
                            .onAppear {
                                // 데이터 없으면 로드
                                if allMeals[date] == nil && !loadingDates.contains(dateString) {
                                    loadMealsForDate(date)
                                }

                                // 마지막 날짜면 더 로드
                                if date == dateList.last {
                                    loadMorePastDates()
                                }
                            }
                        }
                    }
                    .onPreferenceChange(DatePositionPreferenceKey.self) { positions in
                        if let topDate = positions.min(by: { abs($0.value) < abs($1.value) })?.key {
                            if currentVisibleDate != topDate {
                                currentVisibleDate = topDate
                            }
                        }
                    }
                }
                .coordinateSpace(name: "scroll")
            }
        }
    }

    private func loadMealsForDate(_ date: Date) {
        let dateString = dateFormatter.string(from: date)
        loadingDates.insert(dateString)

        _Concurrency.Task {
            do {
                // 캐시에서 먼저 로드 (빠름!)
                let meals = try await friendManager.loadFriendMeals(friendId: friend.id, date: date)
                await MainActor.run {
                    allMeals[date] = meals
                    _ = loadingDates.remove(dateString)
                }
            } catch {
                print("❌ 타임라인 식단 로드 실패 (\(dateString)): \(error)")
                await MainActor.run {
                    _ = loadingDates.remove(dateString)
                }
            }
        }
    }
}

// 그리드 뷰 (ContentView 스타일)
struct GridView: View {
    let friend: Friend
    @ObservedObject var friendManager: FriendManager
    @Binding var allMeals: [Date: [MealType: MealRecord]]

    @State private var loadingDates: Set<String> = []
    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                // 최근 30일간의 식단 표시 (최신순 - 위에서부터 오늘, 어제, 그제...)
                ForEach(datesForGrid, id: \.self) { date in
                    let dateString = dateFormatter.string(from: date)
                    let meals = allMeals[date] ?? [:]
                    let isLoading = loadingDates.contains(dateString)

                    if isLoading {
                        // 로딩 중
                        LoadingGridDayView(date: date)
                    } else if !meals.isEmpty {
                        // 데이터 있을 때만 표시
                        FriendGridDayView(
                            date: date,
                            meals: meals,
                            friend: friend
                        )
                    } else {
                        // 데이터 없음 - 한 번만 로드 시도
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                // 한 번도 로드 안 했으면 시도
                                if allMeals[date] == nil && !loadingDates.contains(dateString) {
                                    loadMealsForDate(date)
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
        .onAppear {
            // 초기 로드 (캐시된 데이터 우선)
            loadInitialGridData()
        }
    }

    private var datesForGrid: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (0..<30).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private func loadInitialGridData() {
        // 최근 7일만 미리 로드 (나머지는 스크롤 시 onAppear에서)
        let recentDates = Array(datesForGrid.prefix(7))
        for date in recentDates {
            if allMeals[date] == nil {
                loadMealsForDate(date)
            }
        }
    }

    private func loadMealsForDate(_ date: Date) {
        let dateString = dateFormatter.string(from: date)

        // 이미 로딩 중이거나 체크 완료면 스킵
        guard !loadingDates.contains(dateString), allMeals[date] == nil else { return }

        loadingDates.insert(dateString)

        _Concurrency.Task {
            do {
                // 캐시에서 먼저 로드 시도 (빠름!)
                let meals = try await friendManager.loadFriendMeals(friendId: friend.id, date: date)
                await MainActor.run {
                    // 결과가 있든 없든 저장 (빈 딕셔너리 = 체크 완료, 데이터 없음)
                    allMeals[date] = meals
                    _ = loadingDates.remove(dateString)

                    if meals.isEmpty {
                        print("ℹ️ [그리드] \(dateString): 데이터 없음")
                    } else {
                        print("✅ [그리드] \(dateString): \(meals.count)개 식단")
                    }
                }
            } catch {
                print("❌ 식단 로드 실패 (\(dateString)): \(error)")
                await MainActor.run {
                    // 에러 발생 시에도 빈 딕셔너리 저장 (재시도 방지)
                    allMeals[date] = [:]
                    _ = loadingDates.remove(dateString)
                }
            }
        }
    }
}

// 로딩 중 그리드 뷰
struct LoadingGridDayView: View {
    let date: Date

    private let calendar = Calendar.current

    private var isToday: Bool {
        calendar.isDateInToday(date)
    }

    private var photoSize: CGFloat {
        let screenWidth = UIScreen.appWidth
        let totalPadding: CGFloat = 16 + 16
        let spacing: CGFloat = 4 * 2
        return (screenWidth - totalPadding - spacing) / 3
    }

    var body: some View {
        VStack(spacing: 0) {
            // 날짜 헤더
            HStack {
                Text(date, format: .dateTime.month().day().weekday(.wide))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()

                ProgressView()
                    .scaleEffect(0.7)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))

            // 로딩 셀들
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    ZStack {
                        Color(.systemGray6)

                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    .frame(width: photoSize, height: photoSize)
                    .cornerRadius(8)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
            )
        }
        .padding(.vertical, 2)
    }
}

// 그리드용 날짜별 뷰 (ContentView의 DailySectionView 스타일)
struct FriendGridDayView: View {
    let date: Date
    let meals: [MealType: MealRecord]
    let friend: Friend

    private let calendar = Calendar.current

    private var isToday: Bool {
        calendar.isDateInToday(date)
    }

    private var photoSize: CGFloat {
        let screenWidth = UIScreen.appWidth
        let totalPadding: CGFloat = 16 + 16 // 좌우 패딩
        let spacing: CGFloat = 4 * 2 // 3개 사이 간격
        return (screenWidth - totalPadding - spacing) / 3
    }

    var body: some View {
        VStack(spacing: 0) {
            // 날짜 헤더
            HStack {
                Text(date, format: .dateTime.month().day().weekday(.wide))
                    .font(.subheadline)
                    .foregroundColor(isToday ? .blue : .secondary)
                    .fontWeight(isToday ? .semibold : .regular)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))

            // 식단 사진 행
            HStack(spacing: 4) {
                ForEach([MealType.breakfast, .lunch, .dinner], id: \.self) { mealType in
                    if let meal = meals[mealType] {
                        FriendMealPhotoCell(meal: meal, mealType: mealType, friend: friend, date: date)
                            .frame(width: photoSize, height: photoSize)
                    } else {
                        EmptyMealPhotoCell(mealType: mealType, friend: friend, date: date)
                            .frame(width: photoSize, height: photoSize)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isToday ? Color.blue.opacity(0.05) : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isToday ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 2)
            )
        }
        .padding(.vertical, 2)
    }
}

// 친구 식단 사진 셀
struct FriendMealPhotoCell: View {
    let meal: MealRecord
    let mealType: MealType
    let friend: Friend
    let date: Date

    @State private var showingDetail = false
    @State private var showingQuickFeedback = false

    var body: some View {
        Button(action: {
            showingDetail = true
        }) {
            ZStack {
                // 썸네일 이미지
                if let imageData = meal.thumbnailImageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    Color(.systemGray5)
                }

                // 좌상단 식사 타입 아이콘
                VStack {
                    HStack {
                        Image(systemName: mealType.symbolName)
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(4)
                            .background(mealType.symbolColor.opacity(0.8))
                            .clipShape(Circle())
                            .padding(4)
                        Spacer()
                    }
                    Spacer()
                }

                // 우하단 피드백 버튼
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            showingQuickFeedback = true
                        }) {
                            Image(systemName: "bubble.left.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.orange.opacity(0.8))
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }
                        .padding(4)
                        .accessibilityLabel("응원 남기기")
                        .accessibilityHint("\(friend.name)님의 \(mealType.rawValue)에 응원 메시지를 보냅니다")
                    }
                }
            }
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .accessibilityLabel("\(friend.name)님의 \(mealType.rawValue) 기록")
        .accessibilityHint("두 번 탭하여 상세 보기")
        .sheet(isPresented: $showingDetail) {
            FriendMealDetailView(meal: meal, mealType: mealType, friend: friend, date: date)
        }
        .sheet(isPresented: $showingQuickFeedback) {
            QuickFeedbackView(friend: friend, date: date, mealType: mealType)
        }
    }
}

// 빈 식단 셀 (탭하면 콕 찌르기 / 댓글 남기기)
struct EmptyMealPhotoCell: View {
    let mealType: MealType
    let friend: Friend
    let date: Date

    @State private var showingActions = false
    @State private var showingComment = false
    @State private var isPoking = false
    @State private var pokeSent = false

    var body: some View {
        Button(action: {
            showingActions = true
        }) {
            ZStack {
                Color(.systemGray6)

                // 기본 이미지
                VStack(spacing: 8) {
                    Image(systemName: defaultImageName)
                        .font(.system(size: 36))
                        .foregroundColor(mealType.symbolColor.opacity(0.35))

                    Text(mealType.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // 콕 찌른 후 표시
                if pokeSent {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("👉 콕!")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.orange))
                                .padding(4)
                        }
                    }
                } else if isPoking {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.7)
                                .padding(6)
                        }
                    }
                }
            }
            .cornerRadius(8)
        }
        .confirmationDialog(
            "\(friend.name)님이 아직 \(mealType.rawValue)을 기록하지 않았어요",
            isPresented: $showingActions,
            titleVisibility: .visible
        ) {
            Button("👉 콕 찌르기") {
                sendPoke()
            }
            Button("댓글 남기기") {
                showingComment = true
            }
            Button("취소", role: .cancel) { }
        }
        .sheet(isPresented: $showingComment) {
            QuickFeedbackView(friend: friend, date: date, mealType: mealType)
        }
        .accessibilityLabel("\(friend.name)님의 \(mealType.rawValue), 아직 기록 없음")
        .accessibilityHint("두 번 탭하여 콕 찌르기 또는 댓글 남기기")
    }

    private func sendPoke() {
        guard !isPoking, !pokeSent else { return }
        isPoking = true

        Task {
            do {
                try await FriendManager.shared.addFeedback(
                    to: friend.id,
                    date: date,
                    mealType: mealType,
                    content: "👉 콕! \(mealType.rawValue) 기록을 기다리고 있어요"
                )
                await MainActor.run {
                    isPoking = false
                    pokeSent = true
                }
            } catch {
                await MainActor.run {
                    isPoking = false
                }
                print("❌ [EmptyMealPhotoCell] 콕 찌르기 실패: \(error)")
            }
        }
    }

    private var defaultImageName: String {
        switch mealType {
        case .breakfast:
            return "cup.and.saucer.fill"
        case .lunch:
            return "fork.knife"
        case .dinner:
            return "takeoutbag.and.cup.and.straw.fill"
        default:
            return "birthday.cake.fill"
        }
    }
}

// 친구 식단 상세 보기 (사진 크게 보기)
struct FriendMealDetailView: View {
    let meal: MealRecord
    let mealType: MealType
    let friend: Friend
    let date: Date
    @Environment(\.dismiss) var dismiss
    @State private var feedbackText: String = ""
    @State private var isSubmitting: Bool = false
    @State private var showSuccessAlert: Bool = false

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

                    // 피드백 작성
                    VStack(alignment: .leading, spacing: 12) {
                        Text("피드백 남기기")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 12) {
                            TextEditor(text: $feedbackText)
                                .frame(height: 100)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )

                            Button(action: submitFeedback) {
                                HStack {
                                    if isSubmitting {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "paperplane.fill")
                                        Text("피드백 보내기")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
                .padding(.vertical)
            }
            .navigationTitle("\(mealType.rawValue) - \(meal.date, style: .date)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
            .alert("피드백 전송 완료", isPresented: $showSuccessAlert) {
                Button("확인", role: .cancel) {
                    feedbackText = ""
                }
            } message: {
                Text("친구에게 피드백을 전송했습니다.")
            }
        }
    }

    private func submitFeedback() {
        let content = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        isSubmitting = true

        Task {
            do {
                try await FriendManager.shared.addFeedback(
                    to: friend.id,
                    date: date,
                    mealType: mealType,
                    content: content
                )

                await MainActor.run {
                    isSubmitting = false
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    print("❌ [FriendMealDetailView] 피드백 전송 실패: \(error)")
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
    var isLoading: Bool = false

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 날짜 구분선
            HStack {
                Text(date, format: .dateTime.month().day().weekday(.wide))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()

                // 로딩 인디케이터
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))

            if isLoading {
                // 로딩 중
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("로딩 중...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if meals.isEmpty {
                // 데이터 없음
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundColor(.gray)
                    Text("기록 없음")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                // 식단 카드들
                VStack(spacing: 16) {
                    ForEach(MealType.allCases, id: \.self) { mealType in
                        if let meal = meals[mealType] {
                            FriendMealCard(mealType: mealType, meal: meal)
                        }
                    }
                }
                .padding()
            }
        }
    }
}

// 친구 식단 카드 (읽기 전용)
struct FriendMealCard: View {
    let mealType: MealType
    let meal: MealRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 헤더
            HStack {
                Image(systemName: mealType.symbolName)
                    .foregroundColor(mealType.symbolColor)
                    .font(.system(size: 20))
                Text(mealType.rawValue)
                    .font(.system(size: 20, weight: .bold))
                Spacer()

                // 식사 시간
                Text(meal.date, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 이미지
            if let beforeData = meal.beforeImageData, let image = UIImage(data: beforeData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .clipped()
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

            // 메모
            if let memo = meal.memo, !memo.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("메모")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(memo)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                }
            } else {
                Text("메모 없음")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// 계정 설정 시트
struct AccountSettingsSheet: View {
    let onDeleteAccount: () -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject var friendManager = FriendManager.shared

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
                                .font(.system(size: 18, weight: .semibold))

                            Text(friendManager.myUserId.isEmpty ? "" : "연결됨")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 8)
                }

                // 내 친구 코드
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("내 친구 코드")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)

                            Text(friendManager.myUserCode)
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                        }

                        Spacer()

                        Button(action: {
                            UIPasteboard.general.string = friendManager.myUserCode
                        }) {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.blue)
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
                        dismiss()
                    }
                }
            }
        }
    }
}

// iCloud 로그인 안내 화면 (별도 로그인 없이 기기의 iCloud 계정을 사용)
struct ICloudRequiredView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // 아이콘
            Image(systemName: "person.2.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            // 제목
            VStack(spacing: 12) {
                Text("친구 기능")
                    .font(.system(size: 32, weight: .bold))

                Text("친구와 식단을 공유하고\n서로의 식습관을 응원하세요")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "icloud")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)

                Text("iCloud 로그인이 필요해요")
                    .font(.system(size: 16, weight: .semibold))

                Text("설정 앱에서 iCloud에 로그인하면\n친구 추가 및 식단 공유 기능을 사용할 수 있습니다")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("설정 열기", destination: url)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.bottom, 40)
            }
        }
        .navigationTitle("친구")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// 타임라인에서 빠른 피드백 작성
struct QuickFeedbackView: View {
    let friend: Friend
    let date: Date
    let mealType: MealType

    @Environment(\.dismiss) private var dismiss
    @State private var feedbackText: String = ""
    @State private var isSubmitting: Bool = false
    @State private var showSuccessAlert: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 헤더
                VStack(spacing: 8) {
                    Text("\(friend.name)님의 \(mealType.rawValue)")
                        .font(.headline)
                    Text(date, style: .date)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top)

                // 피드백 입력
                VStack(alignment: .leading, spacing: 8) {
                    Text("피드백")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextEditor(text: $feedbackText)
                        .frame(height: 150)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                }

                // 전송 버튼
                Button(action: submitFeedback) {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text("피드백 보내기")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)

                Spacer()
            }
            .padding()
            .navigationTitle("빠른 피드백")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                }
            }
            .alert("전송 완료", isPresented: $showSuccessAlert) {
                Button("확인", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("피드백을 성공적으로 보냈습니다!")
            }
            .alert("전송 실패", isPresented: $showErrorAlert) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func submitFeedback() {
        let content = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        isSubmitting = true

        Task {
            do {
                try await FriendManager.shared.addFeedback(
                    to: friend.id,
                    date: date,
                    mealType: mealType,
                    content: content
                )

                await MainActor.run {
                    isSubmitting = false
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
}
