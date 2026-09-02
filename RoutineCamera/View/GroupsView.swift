//
//  GroupsView.swift
//  RoutineCamera
//
//  그룹: 만들기 / 초대 코드로 참여 / 그룹 멤버 전원의 기록 보기
//

import SwiftUI

struct GroupsView: View {
    @ObservedObject var friendManager = FriendManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var showingCreate = false
    @State private var showingJoin = false
    @State private var leaveTarget: FriendGroup?
    @State private var isLeaving = false
    @State private var leaveError: String?

    var body: some View {
        NavigationView {
            content
                .navigationTitle("그룹")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("닫기") { dismiss() }
                            .disabled(isLeaving)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button {
                                showingCreate = true
                            } label: {
                                Label("그룹 만들기", systemImage: "plus.circle")
                            }
                            Button {
                                showingJoin = true
                            } label: {
                                Label("코드로 참여", systemImage: "person.badge.key")
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .disabled(isLeaving)
                        .accessibilityLabel("그룹 만들기 또는 참여")
                    }
                }
                .sheet(isPresented: $showingCreate) {
                    CreateGroupSheet { name, visibility in
                        try await friendManager.createGroup(name: name, visibility: visibility)
                    }
                }
                .sheet(isPresented: $showingJoin) {
                    JoinGroupSheet { code in
                        try await friendManager.joinGroup(inviteCode: code)
                    }
                }
                .alert("그룹 나가기", isPresented: Binding(
                    get: { leaveTarget != nil },
                    set: { if !$0 { leaveTarget = nil } }
                )) {
                    Button("취소", role: .cancel) { leaveTarget = nil }
                    Button("나가기", role: .destructive) {
                        if let group = leaveTarget {
                            leave(group)
                        }
                    }
                } message: {
                    if let group = leaveTarget, group.ownerId == friendManager.myUserId {
                        Text("내가 만든 그룹이라 나가면 그룹 자체가 삭제되고, 멤버 전원이 볼 수 없게 됩니다.")
                    } else {
                        Text("그룹에서 나가면 멤버들의 기록을 볼 수 없어요. 초대 코드로 다시 참여할 수 있습니다.")
                    }
                }
                .alert("나가기 실패", isPresented: Binding(
                    get: { leaveError != nil },
                    set: { if !$0 { leaveError = nil } }
                )) {
                    Button("확인", role: .cancel) { leaveError = nil }
                } message: {
                    Text(leaveError ?? "")
                }
                .overlay {
                    if isLeaving {
                        StatusOverlay(text: "그룹에서 나가는 중...")
                    }
                }
                .task {
                    await friendManager.loadMyGroups()
                }
        }
    }

    /// 로딩 중 / 실패 / 비어 있음 / 목록을 분명히 구분해서 보여준다.
    /// (불러오는 중인데 "그룹이 없어요"가 뜨면 사용자가 실패했다고 오해한다)
    @ViewBuilder private var content: some View {
        if friendManager.isLoadingGroups && friendManager.groups.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("그룹 목록을 불러오는 중...")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = friendManager.groupsError, friendManager.groups.isEmpty {
            failureState(error)
        } else if friendManager.groups.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                if let error = friendManager.groupsError {
                    warningBanner("목록을 새로 고치지 못했어요. \(error)")
                }
                groupList
            }
        }
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 50))
                .foregroundColor(.orange)
                .accessibilityHidden(true)

            Text("그룹 목록을 불러오지 못했어요")
                .font(.system(size: 17, weight: .semibold))

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("다시 시도") {
                _Concurrency.Task { await friendManager.loadMyGroups() }
            }
            .font(.system(size: 15, weight: .semibold))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func warningBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 60))
                .foregroundColor(.gray)
                .accessibilityHidden(true)

            Text("아직 그룹이 없어요")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.secondary)

            Text("그룹을 만들어 초대 코드를 공유하거나\n받은 코드로 참여해보세요")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    showingCreate = true
                } label: {
                    Label("그룹 만들기", systemImage: "plus.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(10)
                }

                Button {
                    showingJoin = true
                } label: {
                    Label("코드로 참여", systemImage: "person.badge.key")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(10)
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupList: some View {
        List {
            ForEach(friendManager.groups) { group in
                NavigationLink(destination: GroupFeedView(group: group)) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.12))
                                .frame(width: 46, height: 46)
                            Image(systemName: "person.3.fill")
                                .foregroundColor(.purple)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name)
                                .font(.system(size: 17, weight: .semibold))

                            HStack(spacing: 6) {
                                Text(group.inviteCode)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.secondary)

                                if group.ownerId == friendManager.myUserId {
                                    Text("방장")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.purple)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.purple.opacity(0.12))
                                        .cornerRadius(4)
                                }

                                Label(group.visibility.title, systemImage: group.visibility.symbolName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        leaveTarget = group
                    } label: {
                        Label("나가기", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await friendManager.loadMyGroups()
        }
        .disabled(isLeaving)
    }

    private func leave(_ group: FriendGroup) {
        isLeaving = true
        leaveTarget = nil

        _Concurrency.Task {
            do {
                try await friendManager.leaveGroup(group)
            } catch {
                leaveError = FriendManager.readableMessage(for: error)
            }
            isLeaving = false
        }
    }
}

/// 화면 전체를 덮는 진행 표시 — 무슨 일이 진행 중인지 문구로 밝힌다
struct StatusOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                Text(text)
                    .font(.callout)
                    .foregroundColor(.primary)
            }
            .padding(24)
            .background(.regularMaterial)
            .cornerRadius(14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - 그룹 만들기

struct CreateGroupSheet: View {
    /// 성공하면 만들어진 그룹을 돌려준다. 실패는 던진다.
    let onCreate: (String, GroupVisibility) async throws -> FriendGroup

    @State private var name = ""
    @State private var visibility: GroupVisibility = .full
    @State private var phase: Phase = .input
    @FocusState private var isNameFocused: Bool
    @Environment(\.dismiss) var dismiss

    enum Phase: Equatable {
        case input
        case working
        case failed(String)
        case done(FriendGroup)
    }

    private var isWorking: Bool { phase == .working }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationView {
            Group {
                if case .done(let group) = phase {
                    successView(group)
                } else {
                    inputView
                }
            }
            .navigationTitle("그룹 만들기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") { dismiss() }
                        .disabled(isWorking)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { isNameFocused = false }
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    private var inputView: some View {
        ScrollView {
            inputContent
        }
        .scrollDismissesKeyboard(.interactively)
        // 빈 곳을 누르면 키보드가 내려가도록 (스크롤 제스처와 충돌하지 않는 탭 제스처)
        .simultaneousGesture(
            TapGesture().onEnded { isNameFocused = false }
        )
    }

    private var inputContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "person.3.sequence")
                    .font(.system(size: 56))
                    .foregroundColor(.purple)

                Text("그룹 만들기")
                    .font(.system(size: 24, weight: .bold))

                Text("그룹을 만들면 6자리 초대 코드가 생겨요.\n코드를 받은 사람은 누구나 참여할 수 있습니다.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)

            TextField("예: 우리 회사 점심팀", text: $name)
                .font(.system(size: 18))
                .multilineTextAlignment(.center)
                .focused($isNameFocused)
                .submitLabel(.done)
                .onSubmit { isNameFocused = false }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                .disabled(isWorking)
                .onChange(of: name) { _, _ in
                    if case .failed = phase { phase = .input }
                }

            VStack(alignment: .leading, spacing: 8) {
                Text("서로에게 보여줄 범위")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                Picker("공개 범위", selection: $visibility) {
                    ForEach(GroupVisibility.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isWorking)

                Text(visibility.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("나중에 방장이 언제든 바꿀 수 있어요.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            if case .failed(let message) = phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
            }

            Button {
                create()
            } label: {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isWorking ? "그룹을 만드는 중..." : (isRetry ? "다시 시도" : "그룹 만들기"))
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(trimmedName.isEmpty || isWorking ? Color.gray : Color.purple)
                .cornerRadius(12)
            }
            .disabled(trimmedName.isEmpty || isWorking)
            .padding(.horizontal)

            if isWorking {
                Text("iCloud에 그룹을 등록하고 있어요. 잠시만 기다려주세요.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private var isRetry: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func successView(_ group: FriendGroup) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("'\(group.name)' 그룹을 만들었어요")
                .font(.system(size: 20, weight: .bold))
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Text("초대 코드")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    Text(group.inviteCode)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))

                    Button {
                        UIPasteboard.general.string = group.inviteCode
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 18))
                    }
                    .accessibilityLabel("초대 코드 복사")
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            VStack(spacing: 4) {
                Label(group.visibility.title, systemImage: group.visibility.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                Text("이 코드를 공유하면 상대가 그룹에 참여할 수 있어요.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)

            Button {
                dismiss()
            } label: {
                Text("완료")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.purple)
                    .cornerRadius(12)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 40)
    }

    private func create() {
        guard !isWorking else { return }
        isNameFocused = false
        phase = .working

        _Concurrency.Task {
            do {
                let group = try await onCreate(trimmedName, visibility)
                phase = .done(group)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - 그룹 참여

struct JoinGroupSheet: View {
    /// 성공하면 참여한 그룹을 돌려준다. 실패는 던진다.
    let onJoin: (String) async throws -> FriendGroup

    @State private var code = ""
    @State private var phase: Phase = .input
    @FocusState private var isCodeFocused: Bool
    @Environment(\.dismiss) var dismiss

    enum Phase: Equatable {
        case input
        case working
        case failed(String)
        case done(FriendGroup)
    }

    private var isWorking: Bool { phase == .working }

    private var trimmedCode: String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    var body: some View {
        NavigationView {
            Group {
                if case .done(let group) = phase {
                    successView(group)
                } else {
                    inputView
                }
            }
            .navigationTitle("그룹 참여")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") { dismiss() }
                        .disabled(isWorking)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { isCodeFocused = false }
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    private var inputView: some View {
        ScrollView {
            inputContent
        }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            TapGesture().onEnded { isCodeFocused = false }
        )
    }

    private var inputContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "person.badge.key")
                    .font(.system(size: 56))
                    .foregroundColor(.purple)

                Text("그룹 코드 입력")
                    .font(.system(size: 24, weight: .bold))

                Text("공유받은 6자리 그룹 코드를 입력하세요.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)

            TextField("예: ABC123", text: $code)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textCase(.uppercase)
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
                .focused($isCodeFocused)
                .submitLabel(.done)
                .onSubmit { isCodeFocused = false }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                .disabled(isWorking)
                .onChange(of: code) { _, _ in
                    if case .failed = phase { phase = .input }
                }

            if case .failed(let message) = phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
            }

            Button {
                join()
            } label: {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isWorking ? "그룹을 찾는 중..." : (isRetry ? "다시 시도" : "그룹 참여"))
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(trimmedCode.count == 6 && !isWorking ? Color.purple : Color.gray)
                .cornerRadius(12)
            }
            .disabled(trimmedCode.count != 6 || isWorking)
            .padding(.horizontal)

            if isWorking {
                Text("코드를 확인하고 그룹에 등록하고 있어요. 잠시만 기다려주세요.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private var isRetry: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func successView(_ group: FriendGroup) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("'\(group.name)' 그룹에 참여했어요")
                .font(.system(size: 20, weight: .bold))
                .multilineTextAlignment(.center)

            Text("이제 그룹 화면에서 멤버들의 기록을 볼 수 있어요.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                dismiss()
            } label: {
                Text("완료")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.purple)
                    .cornerRadius(12)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 40)
    }

    private func join() {
        guard !isWorking else { return }
        isCodeFocused = false
        phase = .working

        _Concurrency.Task {
            do {
                let group = try await onJoin(trimmedCode)
                phase = .done(group)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - 그룹 피드 (멤버 전원의 하루)

struct GroupFeedView: View {
    let group: FriendGroup

    @ObservedObject var friendManager = FriendManager.shared
    @State private var current: FriendGroup
    @State private var members: [GroupMemberInfo] = []
    @State private var mealsByUser: [String: [MealType: MealRecord]] = [:]
    @State private var recordedByUser: [String: Set<MealType>] = [:]
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var visibilityError: String?
    @State private var isChangingVisibility = false

    init(group: FriendGroup) {
        self.group = group
        _current = State(initialValue: group)
    }

    private var isOwner: Bool { current.ownerId == friendManager.myUserId }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    /// 사진까지 보여주는 그룹에서, 그 날 기록이 있는 멤버만
    private var membersWithRecords: [GroupMemberInfo] {
        members.filter { !(mealsByUser[$0.id]?.isEmpty ?? true) }
    }

    private var recordedCount: Int {
        switch current.visibility {
        case .full: return membersWithRecords.count
        case .record: return members.filter { !(recordedByUser[$0.id]?.isEmpty ?? true) }.count
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                visibilityMenu
            }
        }
        .overlay {
            if isChangingVisibility {
                StatusOverlay(text: "공개 범위를 바꾸는 중...")
            }
        }
        .alert("변경 실패", isPresented: Binding(
            get: { visibilityError != nil },
            set: { if !$0 { visibilityError = nil } }
        )) {
            Button("확인", role: .cancel) { visibilityError = nil }
        } message: {
            Text(visibilityError ?? "")
        }
        .task {
            await loadMembers()
        }
    }

    // MARK: 공개 범위

    @ViewBuilder private var visibilityMenu: some View {
        if isOwner {
            Menu {
                Picker("공개 범위", selection: Binding(
                    get: { current.visibility },
                    set: { change(to: $0) }
                )) {
                    ForEach(GroupVisibility.allCases) { option in
                        Label(option.title, systemImage: option.symbolName).tag(option)
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .disabled(isChangingVisibility)
            .accessibilityLabel("그룹 공개 범위 설정")
        }
    }

    private func change(to visibility: GroupVisibility) {
        guard visibility != current.visibility, !isChangingVisibility else { return }
        isChangingVisibility = true

        _Concurrency.Task {
            do {
                current = try await friendManager.updateGroupVisibility(current, to: visibility)
                mealsByUser = [:]
                recordedByUser = [:]
                await loadDay()
            } catch {
                visibilityError = error.localizedDescription
            }
            isChangingVisibility = false
        }
    }

    // MARK: 헤더

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    move(days: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                }
                .accessibilityLabel("이전 날")

                Spacer()

                VStack(spacing: 2) {
                    Text(date, format: .dateTime.month().day().weekday(.wide))
                        .font(.system(size: 16, weight: .semibold))
                    Text("기록 \(recordedCount)명 · 멤버 \(members.count)명")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    move(days: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                .disabled(isToday)
                .accessibilityLabel("다음 날")
            }
            .padding(.horizontal)

            HStack(spacing: 8) {
                Label(current.visibility.title, systemImage: current.visibility.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.12))
                    .cornerRadius(6)

                Text(current.inviteCode)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))

                Button {
                    UIPasteboard.general.string = current.inviteCode
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                }
                .accessibilityLabel("그룹 초대 코드 복사")

                if !isToday {
                    Spacer()
                    Button("오늘") {
                        date = Calendar.current.startOfDay(for: Date())
                        _Concurrency.Task { await loadDay() }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    // MARK: 본문

    @ViewBuilder private var content: some View {
        if isLoading && members.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                Text("불러오는 중...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.icloud")
                    .font(.system(size: 44))
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)

                Text(loadError)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("다시 시도") {
                    _Concurrency.Task { await loadMembers() }
                }
                .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if members.isEmpty {
            Text("아직 멤버가 없어요")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch current.visibility {
            case .record:
                statusList
            case .full:
                photoFeed
            }
        }
    }

    /// 기록 여부만 공개하는 그룹 — 멤버 전원을 O/X로 보여준다 (누가 안 했는지가 핵심)
    private var statusList: some View {
        List {
            Section {
                ForEach(members) { member in
                    GroupStatusRow(
                        member: member,
                        isMe: member.id == friendManager.myUserId,
                        recorded: recordedByUser[member.id] ?? []
                    )
                }
            } footer: {
                Text("이 그룹은 기록 여부만 공유합니다. 사진과 메모는 서로 보이지 않아요.")
            }
        }
        .listStyle(.plain)
        .refreshable { await loadDay() }
    }

    /// 사진까지 공개하는 그룹 — 그 날 기록이 있는 멤버만
    @ViewBuilder private var photoFeed: some View {
        if membersWithRecords.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 40))
                    .foregroundColor(.gray)
                    .accessibilityHidden(true)
                Text("이 날은 아무도 기록하지 않았어요")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(membersWithRecords) { member in
                        GroupMemberSection(
                            member: member,
                            isMe: member.id == friendManager.myUserId,
                            meals: mealsByUser[member.id] ?? [:]
                        )
                    }
                }
                .padding(.vertical, 12)
            }
            .refreshable { await loadDay() }
        }
    }

    // MARK: 로딩

    private func move(days: Int) {
        guard let moved = Calendar.current.date(byAdding: .day, value: days, to: date) else { return }
        let today = Calendar.current.startOfDay(for: Date())
        guard moved <= today else { return }
        date = moved
        _Concurrency.Task { await loadDay() }
    }

    private func loadMembers() async {
        isLoading = true
        defer { isLoading = false }

        do {
            members = try await friendManager.loadGroupMembers(groupId: current.id)
            loadError = nil
            await loadDay()
        } catch {
            loadError = "멤버를 불러오지 못했어요.\n\(FriendManager.readableMessage(for: error))"
        }
    }

    private func loadDay() async {
        guard !members.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        let ids = members.map(\.id)

        do {
            switch current.visibility {
            case .record:
                recordedByUser = try await friendManager.loadGroupMealStatus(userIds: ids, date: date)
            case .full:
                mealsByUser = try await friendManager.loadGroupMeals(userIds: ids, date: date)
            }
            loadError = nil
        } catch {
            loadError = "기록을 불러오지 못했어요.\n\(FriendManager.readableMessage(for: error))"
        }
    }
}

/// 기록 여부만 보여주는 행
struct GroupStatusRow: View {
    let member: GroupMemberInfo
    let isMe: Bool
    let recorded: Set<MealType>

    private var hasRecord: Bool { !recorded.isEmpty }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(hasRecord ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: hasRecord ? "checkmark" : "minus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(hasRecord ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(isMe ? "\(member.nickname) (나)" : member.nickname)
                    .font(.system(size: 16, weight: .semibold))

                if hasRecord {
                    HStack(spacing: 4) {
                        ForEach(MealType.allCases.filter { recorded.contains($0) }, id: \.self) { mealType in
                            Text(mealType.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray6))
                                .cornerRadius(4)
                        }
                    }
                } else {
                    Text("아직 기록 없음")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hasRecord
                            ? "\(member.nickname), 기록함, \(recorded.map(\.rawValue).joined(separator: ", "))"
                            : "\(member.nickname), 아직 기록 없음")
    }
}

/// 그룹 피드에서 멤버 한 명의 하루 (사진까지 공개하는 그룹)
struct GroupMemberSection: View {
    let member: GroupMemberInfo
    let isMe: Bool
    let meals: [MealType: MealRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Text(String(member.nickname.prefix(1)))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.blue)
                }

                Text(isMe ? "\(member.nickname) (나)" : member.nickname)
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Text("\(meals.count)개")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            VStack(spacing: 12) {
                ForEach(MealType.allCases, id: \.self) { mealType in
                    if let meal = meals[mealType] {
                        FriendMealCard(mealType: mealType, meal: meal)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .cornerRadius(14)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
    }
}
