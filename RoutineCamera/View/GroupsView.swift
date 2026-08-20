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
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var leaveTarget: FriendGroup?

    var body: some View {
        NavigationView {
            Group {
                if friendManager.groups.isEmpty {
                    emptyState
                } else {
                    groupList
                }
            }
            .navigationTitle("그룹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("닫기") { dismiss() }
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
                    .accessibilityLabel("그룹 만들기 또는 참여")
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreateGroupSheet { name in
                    await run { _ = try await friendManager.createGroup(name: name) }
                }
            }
            .sheet(isPresented: $showingJoin) {
                JoinGroupSheet { code in
                    await run { _ = try await friendManager.joinGroup(inviteCode: code) }
                }
            }
            .alert("오류", isPresented: $showingError) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("그룹 나가기", isPresented: Binding(
                get: { leaveTarget != nil },
                set: { if !$0 { leaveTarget = nil } }
            )) {
                Button("취소", role: .cancel) { leaveTarget = nil }
                Button("나가기", role: .destructive) {
                    if let group = leaveTarget {
                        _Concurrency.Task {
                            await run { try await friendManager.leaveGroup(group) }
                            leaveTarget = nil
                        }
                    }
                }
            } message: {
                if let group = leaveTarget, group.ownerId == friendManager.myUserId {
                    Text("내가 만든 그룹이라 나가면 그룹 자체가 삭제되고, 멤버 전원이 볼 수 없게 됩니다.")
                } else {
                    Text("그룹에서 나가면 멤버들의 기록을 볼 수 없어요. 초대 코드로 다시 참여할 수 있습니다.")
                }
            }
            .task {
                await friendManager.loadMyGroups()
            }
        }
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
    }

    /// 그룹 작업 공통 실행 (실패 시 알럿)
    private func run(_ action: () async throws -> Void) async {
        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - 그룹 만들기

struct CreateGroupSheet: View {
    let onCreate: (String) async -> Void

    @State private var name = ""
    @State private var isWorking = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
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
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                Button {
                    isWorking = true
                    _Concurrency.Task {
                        await onCreate(name)
                        isWorking = false
                        dismiss()
                    }
                } label: {
                    Text(isWorking ? "만드는 중..." : "그룹 만들기")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.purple)
                        .cornerRadius(12)
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("그룹 만들기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 그룹 참여

struct JoinGroupSheet: View {
    let onJoin: (String) async -> Void

    @State private var code = ""
    @State private var isWorking = false
    @Environment(\.dismiss) var dismiss

    private var trimmedCode: String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    var body: some View {
        NavigationView {
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
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                Button {
                    isWorking = true
                    _Concurrency.Task {
                        await onJoin(trimmedCode)
                        isWorking = false
                        dismiss()
                    }
                } label: {
                    Text(isWorking ? "참여하는 중..." : "그룹 참여")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(trimmedCode.count == 6 ? Color.purple : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(trimmedCode.count != 6 || isWorking)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("그룹 참여")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 그룹 피드 (멤버 전원의 하루)

struct GroupFeedView: View {
    let group: FriendGroup

    @ObservedObject var friendManager = FriendManager.shared
    @State private var members: [GroupMemberInfo] = []
    @State private var mealsByUser: [String: [MealType: MealRecord]] = [:]
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var isLoading = false
    @State private var loadError: String?

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    /// 그 날 기록이 있는 멤버만 (기록 없는 사람은 숨긴다)
    private var membersWithRecords: [GroupMemberInfo] {
        members.filter { !(mealsByUser[$0.id]?.isEmpty ?? true) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if isLoading && mealsByUser.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("불러오는 중...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundColor(.orange)
                    Text(loadError)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if members.isEmpty {
                Text("아직 멤버가 없어요")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if membersWithRecords.isEmpty {
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
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMembers()
        }
    }

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
                    Text("기록 \(membersWithRecords.count)명 · 멤버 \(members.count)명")
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
                Text("초대 코드")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(group.inviteCode)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))

                Button {
                    UIPasteboard.general.string = group.inviteCode
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                }
                .accessibilityLabel("그룹 초대 코드 복사")

                if !isToday {
                    Spacer()
                    Button("오늘") {
                        date = Calendar.current.startOfDay(for: Date())
                        _Concurrency.Task { await loadMeals() }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private func move(days: Int) {
        guard let moved = Calendar.current.date(byAdding: .day, value: days, to: date) else { return }
        let today = Calendar.current.startOfDay(for: Date())
        guard moved <= today else { return }
        date = moved
        _Concurrency.Task { await loadMeals() }
    }

    private func loadMembers() async {
        isLoading = true
        defer { isLoading = false }

        do {
            members = try await friendManager.loadGroupMembers(groupId: group.id)
            loadError = nil
            await loadMeals()
        } catch {
            loadError = "멤버를 불러오지 못했어요.\n\(error.localizedDescription)"
        }
    }

    private func loadMeals() async {
        guard !members.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            mealsByUser = try await friendManager.loadGroupMeals(userIds: members.map(\.id), date: date)
            loadError = nil
        } catch {
            loadError = "기록을 불러오지 못했어요.\n\(error.localizedDescription)"
        }
    }
}

/// 그룹 피드에서 멤버 한 명의 하루
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
