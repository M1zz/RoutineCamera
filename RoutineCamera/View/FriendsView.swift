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
    @State private var showingAccountSettings = false
    @State private var showingDeleteConfirm = false
    @State private var showingGroups = false

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
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("친구에게 보이는 이름")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(settingsManager.displayNickname)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                Spacer()

                Text("변경")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
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

                    if let error = friendManager.socialError {
                        Section {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("친구 목록을 새로 고치지 못했어요")
                                        .font(.system(size: 14, weight: .semibold))
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
                                    .font(.system(size: 14))
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
                AddFriendSheet(friendCode: $friendCode) { code in
                    try await friendManager.sendFriendRequest(code: code)
                }
            }
            .sheet(item: $selectedFriend) { friend in
                FriendMealsView(friend: friend)
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
                HStack(spacing: 6) {
                    ProgressView()
                    Text(workingLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Button("수락") {
                    perform("수락 중...") { try await friendManager.acceptFriendRequest(request) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("거절") {
                    perform("거절 중...") { try await friendManager.rejectFriendRequest(request) }
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
                errorText = "처리하지 못했어요. \(error.localizedDescription)"
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
                    .font(.system(size: 16, weight: .semibold))
                Text(pending.isRejected ? "요청이 거절됐어요" : "수락 대기 중 · \(pending.code)")
                    .font(.system(size: 13))
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

    private var inputView: some View {
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
                        .font(.system(size: 18, weight: .semibold))
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
            }

            Spacer()
        }
    }

    private var buttonTitle: String {
        switch phase {
        case .working(let done, let total):
            return total > 1 ? "요청 보내는 중... (\(done)/\(total))" : "요청 보내는 중..."
        default:
            return parsedCodes.count > 1 ? "\(parsedCodes.count)명에게 요청" : "친구 요청 보내기"
        }
    }

    private func resultView(sent: Int, failures: [String]) -> some View {
        VStack(spacing: 18) {
            Image(systemName: failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(failures.isEmpty ? .green : .orange)

            Text(headline(sent: sent, failures: failures))
                .font(.system(size: 20, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if sent > 0 {
                Text("상대가 수락하면 서로의 기록을 볼 수 있어요.\n보낸 요청은 친구 화면에서 확인할 수 있습니다.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if !failures.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(failures, id: \.self) { failure in
                            Text(failure)
                                .font(.system(size: 13))
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
                    .font(.system(size: 18, weight: .semibold))
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
                .font(.system(size: 15, weight: .semibold))
            }

            Spacer()
        }
        .padding(.top, 32)
    }

    private func headline(sent: Int, failures: [String]) -> String {
        if failures.isEmpty {
            return sent == 1 ? "친구 요청을 보냈어요" : "\(sent)명에게 친구 요청을 보냈어요"
        }
        if sent == 0 {
            return "요청을 보내지 못했어요"
        }
        return "\(sent)명 전송, \(failures.count)명 실패"
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
                    onRefresh: refreshLoadedDates
                )
            }
            .navigationTitle("\(friend.name)의 \(album.shareTitle)")
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
            }
        } catch {
            print("❌ 기록 로드 실패: \(error)")
            await MainActor.run {
                for date in dates where allMeals[date] == nil { allMeals[date] = [:] }
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
                        meals: allMeals[date] ?? [:]
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
            if !loading && recordedDates.isEmpty && canLoadMore {
                loadMorePastDates()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundColor(.gray)
                .accessibilityHidden(true)

            Text("아직 \(album.shareTitle) 기록이 없어요")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
        }
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
                .font(.system(size: 14, weight: .semibold))
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
                Text("\(friend.name)님이 오늘 아직 \(album.shareTitle) 기록이 없어요")
                    .font(.system(size: 14, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    showingMealPicker = true
                } label: {
                    Label("콕 찌르기", systemImage: "hand.point.right")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                        .foregroundColor(.orange)
                }
                .disabled(pokingMeal != nil)

                if !pokedMeals.isEmpty {
                    Text("보냈어요")
                        .font(.system(size: 13))
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
        .confirmationDialog("어느 \(album.shareTitle)을 재촉할까요?",
                            isPresented: $showingMealPicker, titleVisibility: .visible) {
            ForEach(pokeTargets, id: \.self) { mealType in
                Button("👉 \(mealType.rawValue) 콕 찌르기") { sendPoke(mealType) }
                Button("\(mealType.rawValue)에 응원 남기기") { commentTarget = mealType }
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
                    content: "👉 콕! \(mealType.rawValue) 기록을 기다리고 있어요",
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
            .navigationTitle("\(mealType.rawValue) - \(meal.date, style: .date)")
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
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "a h:mm"
        return fmt.string(from: captured)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 헤더 — 끼니 이름이 길어져도 시간이 밀려 잘리지 않도록 시간에 고정 폭을 준다
            HStack(spacing: 8) {
                Image(systemName: mealType.symbolName)
                    .foregroundColor(mealType.symbolColor)
                    .font(.system(size: 20))
                Text(mealType.rawValue)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                // 식사 시간 (절대 잘리지 않게)
                if let timeText = capturedTimeText {
                    Text(timeText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel("기록 시각 \(timeText)")
                }
            }

            // 이미지 — 원본 비율 그대로(잘라내지 않음)
            if let beforeData = meal.beforeImageData, let image = UIImage(data: beforeData) {
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(memo)
                        .font(.system(size: 14))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("응원 남기기")
                .accessibilityHint("\(friend.name)님의 \(mealType.rawValue)에 응원 메시지를 보냅니다")
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
                                .font(.system(size: 18, weight: .semibold))

                            Text(friendManager.myUserId.isEmpty ? "" : "연결됨")
                                .font(.system(size: 14))
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
    /// 지금 보고 있는 탭 (음식/운동). 응원이 엉뚱한 기록에 달리지 않도록 끝까지 따라간다.
    var album: AlbumType = .diet

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 8) {
                        Text("\(friend.name)님의 \(mealType.rawValue)")
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
