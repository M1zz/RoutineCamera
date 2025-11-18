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

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 내 코드 섹션
                VStack(spacing: 12) {
                    Text("내 친구 코드")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Text(friendManager.myUserCode.isEmpty ? "로딩 중..." : friendManager.myUserCode)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)

                        Button(action: {
                            UIPasteboard.general.string = friendManager.myUserCode
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    Text("이 코드를 친구에게 공유하세요")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemBackground))

                Divider()

                // 친구 목록
                if friendManager.friends.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)

                        Text("아직 친구가 없어요")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.secondary)

                        Text("친구 코드를 입력해서\n친구를 추가해보세요!")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: {
                            showingAddFriend = true
                        }) {
                            HStack {
                                Image(systemName: "person.badge.plus")
                                Text("친구 추가")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(friendManager.friends) { friend in
                            Button(action: {
                                selectedFriend = friend
                            }) {
                                HStack(spacing: 12) {
                                    // 친구 아이콘
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
                                }
                                .padding(.vertical, 8)
                            }
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
                    .listStyle(.plain)
                }
            }
            .navigationTitle("친구")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
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
                            .foregroundColor(.orange)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddFriend = true
                    }) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 20))
                    }
                }
            }
            .sheet(isPresented: $showingAddFriend) {
                AddFriendSheet(
                    friendCode: $friendCode,
                    onAdd: {
                        _Concurrency.Task {
                            do {
                                try await friendManager.addFriend(code: friendCode.uppercased())
                                friendCode = ""
                                showingAddFriend = false
                            } catch {
                                errorMessage = error.localizedDescription
                                showingError = true
                            }
                        }
                    }
                )
            }
            .sheet(item: $selectedFriend) { friend in
                FriendMealsView(friend: friend)
            }
            .alert("오류", isPresented: $showingError) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
}

// 친구 추가 시트
struct AddFriendSheet: View {
    @Binding var friendCode: String
    let onAdd: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    Text("친구 코드 입력")
                        .font(.system(size: 24, weight: .bold))

                    Text("친구가 공유한 6자리 코드를 입력하세요")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                // 코드 입력 필드
                TextField("예: ABC123", text: $friendCode)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textCase(.uppercase)
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .onChange(of: friendCode) { oldValue, newValue in
                        // 6자리 제한
                        if newValue.count > 6 {
                            friendCode = String(newValue.prefix(6))
                        }
                    }

                Button(action: onAdd) {
                    Text("친구 추가")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(friendCode.count == 6 ? Color.blue : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(friendCode.count != 6)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("친구 추가")
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
    @State private var selectedDate = Date()
    @State private var meals: [MealType: MealRecord] = [:]
    @State private var isLoading = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 날짜 선택기
                DatePicker("날짜", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .padding()
                    .onChange(of: selectedDate) { oldValue, newValue in
                        loadMeals()
                    }

                Divider()

                // 식단 표시 (ContentView와 동일한 형식)
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if meals.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)

                        Text("이 날짜에는 기록이 없어요")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(MealType.allCases.filter { !$0.isSnack }, id: \.self) { mealType in
                                if let meal = meals[mealType] {
                                    FriendMealCard(mealType: mealType, meal: meal)
                                }
                            }
                        }
                        .padding()
                    }
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
                loadMeals()
            }
        }
    }

    private func loadMeals() {
        isLoading = true
        _Concurrency.Task {
            do {
                let loadedMeals = try await friendManager.loadFriendMeals(friendId: friend.id, date: selectedDate)
                await MainActor.run {
                    meals = loadedMeals
                    isLoading = false
                }
            } catch {
                print("❌ 친구 식단 로드 실패: \(error)")
                await MainActor.run {
                    meals = [:]
                    isLoading = false
                }
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
            }

            // 이미지
            if let beforeData = meal.beforeImageData, let image = UIImage(data: beforeData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .clipped()
                    .cornerRadius(12)
            }

            // 메모
            if let memo = meal.memo, !memo.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("메모")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(memo)
                        .font(.system(size: 14))
                }
            }

        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}
