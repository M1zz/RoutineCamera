//
//  FriendManager.swift
//  RoutineCamera
//
//  친구 관리 및 Firebase 연동
//

import Foundation
import FirebaseDatabase
import FirebaseAuth
import Combine

// 친구 모델
struct Friend: Identifiable, Codable {
    let id: String
    let code: String
    let name: String
    var addedDate: Date

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case name
        case addedDate
    }
}

// 친구 식단 데이터
struct FriendMealData: Codable {
    let beforeImageURL: String?
    let afterImageURL: String?
    let memo: String?
    let timestamp: TimeInterval

    var beforeImageData: Data? {
        guard let urlString = beforeImageURL, let url = URL(string: urlString) else { return nil }
        return try? Data(contentsOf: url)
    }

    var afterImageData: Data? {
        guard let urlString = afterImageURL, let url = URL(string: urlString) else { return nil }
        return try? Data(contentsOf: url)
    }
}

@MainActor
class FriendManager: ObservableObject {
    static let shared = FriendManager()

    @Published var myUserCode: String = ""
    @Published var myUserId: String = ""
    @Published var friends: [Friend] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var ref: DatabaseReference
    private var authStateListener: AuthStateDidChangeListenerHandle?

    private init() {
        self.ref = Database.database().reference()
        setupAuth()
    }

    // MARK: - 인증 설정

    private func setupAuth() {
        // 익명 로그인 (간단한 구현)
        if Auth.auth().currentUser == nil {
            Auth.auth().signInAnonymously { [weak self] result, error in
                if let error = error {
                    print("❌ 익명 로그인 실패: \(error)")
                    print("⚠️ Firebase 설정이 없습니다. 로컬 모드로 전환합니다.")
                    // Firebase 설정이 없으면 로컬 모드 사용
                    _Concurrency.Task { @MainActor in
                        self?.setupLocalMode()
                    }
                    return
                }

                _Concurrency.Task { @MainActor in
                    self?.myUserId = result?.user.uid ?? ""
                    self?.generateOrLoadUserCode()
                    self?.loadFriends()
                    print("✅ Firebase 인증 완료: \(self?.myUserId ?? "")")

                    // 첫 실행 시 샘플 데이터 자동 생성
                    await self?.createSampleDataIfNeeded()
                }
            }
        } else {
            myUserId = Auth.auth().currentUser?.uid ?? ""
            generateOrLoadUserCode()
            loadFriends()

            // 첫 실행 시 샘플 데이터 자동 생성
            _Concurrency.Task {
                await createSampleDataIfNeeded()
            }
        }
    }

    // Firebase 없이 로컬 모드로 작동
    private func setupLocalMode() {
        // UserDefaults에서 로컬 코드 로드 또는 생성
        if let savedCode = UserDefaults.standard.string(forKey: "localFriendCode") {
            myUserCode = savedCode
            print("✅ 로컬 친구 코드 로드: \(savedCode)")
        } else {
            let newCode = generateRandomCode()
            myUserCode = newCode
            UserDefaults.standard.set(newCode, forKey: "localFriendCode")
            print("✅ 로컬 친구 코드 생성: \(newCode)")
        }
        myUserId = "LOCAL_USER"
    }

    // MARK: - 사용자 코드 생성/로드

    private func generateOrLoadUserCode() {
        guard !myUserId.isEmpty else { return }

        // 먼저 저장된 코드 확인
        ref.child("users").child(myUserId).child("code").observeSingleEvent(of: .value) { [weak self] snapshot in
            if let code = snapshot.value as? String {
                _Concurrency.Task { @MainActor in
                    self?.myUserCode = code
                    print("✅ 기존 사용자 코드 로드: \(code)")
                }
            } else {
                // 새 코드 생성
                let newCode = self?.generateRandomCode() ?? ""
                self?.ref.child("users").child(self?.myUserId ?? "").child("code").setValue(newCode)
                self?.ref.child("userCodes").child(newCode).setValue(self?.myUserId)

                _Concurrency.Task { @MainActor in
                    self?.myUserCode = newCode
                    print("✅ 새 사용자 코드 생성: \(newCode)")
                }
            }
        }
    }

    private func generateRandomCode() -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // 혼동되는 문자 제외 (I, O, 0, 1)
        return String((0..<6).map { _ in characters.randomElement()! })
    }

    // MARK: - 친구 관리

    func addFriend(code: String) async throws {
        guard code.count == 6 else {
            throw NSError(domain: "FriendManager", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "6자리 코드를 입력해주세요."])
        }

        guard code != myUserCode else {
            throw NSError(domain: "FriendManager", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "자신의 코드는 추가할 수 없습니다."])
        }

        isLoading = true
        errorMessage = nil

        do {
            // 1. 코드로 친구 ID 찾기
            let snapshot = try await ref.child("userCodes").child(code).getData()
            guard let friendId = snapshot.value as? String else {
                throw NSError(domain: "FriendManager", code: -3,
                             userInfo: [NSLocalizedDescriptionKey: "존재하지 않는 코드입니다."])
            }

            // 2. 이미 친구인지 확인
            if friends.contains(where: { $0.id == friendId }) {
                throw NSError(domain: "FriendManager", code: -4,
                             userInfo: [NSLocalizedDescriptionKey: "이미 추가된 친구입니다."])
            }

            // 3. 친구 정보 가져오기
            let friendSnapshot = try await ref.child("users").child(friendId).getData()
            guard let friendData = friendSnapshot.value as? [String: Any] else {
                throw NSError(domain: "FriendManager", code: -5,
                             userInfo: [NSLocalizedDescriptionKey: "친구 정보를 가져올 수 없습니다."])
            }

            let friendName = friendData["name"] as? String ?? "친구"

            // 4. 내 친구 목록에 추가
            try await ref.child("users").child(myUserId).child("friends").child(friendId).setValue([
                "code": code,
                "name": friendName,
                "addedDate": Date().timeIntervalSince1970
            ])

            // 5. 로컬에 추가
            let newFriend = Friend(
                id: friendId,
                code: code,
                name: friendName,
                addedDate: Date()
            )

            await MainActor.run {
                friends.append(newFriend)
                isLoading = false
            }

            print("✅ 친구 추가 완료: \(friendName) (\(code))")

        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }

    func removeFriend(friendId: String) async throws {
        isLoading = true

        try await ref.child("users").child(myUserId).child("friends").child(friendId).removeValue()

        await MainActor.run {
            friends.removeAll { $0.id == friendId }
            isLoading = false
        }

        print("✅ 친구 삭제 완료: \(friendId)")
    }

    private func loadFriends() {
        guard !myUserId.isEmpty else {
            print("⚠️ myUserId가 비어있어 친구 목록을 로드할 수 없습니다")
            return
        }

        ref.child("users").child(myUserId).child("friends").observe(.value) { [weak self] snapshot in
            guard let friendsData = snapshot.value as? [String: [String: Any]] else {
                _Concurrency.Task { @MainActor in
                    self?.friends = []
                }
                return
            }

            var loadedFriends: [Friend] = []

            for (friendId, data) in friendsData {
                if let code = data["code"] as? String,
                   let name = data["name"] as? String,
                   let timestamp = data["addedDate"] as? TimeInterval {
                    let friend = Friend(
                        id: friendId,
                        code: code,
                        name: name,
                        addedDate: Date(timeIntervalSince1970: timestamp)
                    )
                    loadedFriends.append(friend)
                }
            }

            _Concurrency.Task { @MainActor in
                self?.friends = loadedFriends.sorted { $0.addedDate > $1.addedDate }
                print("✅ 친구 목록 로드: \(loadedFriends.count)명")
            }
        }
    }

    // MARK: - 친구 식단 데이터 가져오기

    func loadFriendMeals(friendId: String, date: Date) async throws -> [MealType: MealRecord] {
        let dateString = dateFormatter.string(from: date)

        let snapshot = try await ref.child("meals").child(friendId).child(dateString).getData()

        guard let mealsData = snapshot.value as? [String: [String: Any]] else {
            return [:]
        }

        var meals: [MealType: MealRecord] = [:]

        for (mealTypeString, data) in mealsData {
            guard let mealType = MealType(rawValue: mealTypeString) else { continue }

            // 이미지 데이터 로드 (URL 또는 base64)
            var beforeData: Data?
            var afterData: Data?

            // beforeImage: URL에서 다운로드 또는 base64 디코드
            if let beforeURL = data["beforeImageURL"] as? String, let url = URL(string: beforeURL) {
                beforeData = try? await downloadImageData(from: url)
            } else if let beforeBase64 = data["beforeImageBase64"] as? String {
                beforeData = Data(base64Encoded: beforeBase64)
            }

            // afterImage: URL에서 다운로드 또는 base64 디코드
            if let afterURL = data["afterImageURL"] as? String, let url = URL(string: afterURL) {
                afterData = try? await downloadImageData(from: url)
            } else if let afterBase64 = data["afterImageBase64"] as? String {
                afterData = Data(base64Encoded: afterBase64)
            }

            let memo = data["memo"] as? String

            let record = MealRecord(
                date: date,
                mealType: mealType,
                beforeImageData: beforeData,
                afterImageData: afterData,
                memo: memo,
                recordedWithoutPhoto: false,
                hidePhotoCountBadge: false
            )

            meals[mealType] = record
        }

        return meals
    }

    private func downloadImageData(from url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    // MARK: - 내 식단 업로드 (선택적)

    func uploadMyMeals(date: Date, meals: [MealType: MealRecord]) async throws {
        let dateString = dateFormatter.string(from: date)

        for (mealType, record) in meals {
            var data: [String: Any] = [
                "timestamp": Date().timeIntervalSince1970
            ]

            // 이미지는 Firebase Storage에 업로드하고 URL 저장
            // 간단하게 하기 위해 여기서는 base64로 저장 (실제로는 Storage 사용 권장)
            if let beforeData = record.beforeImageData {
                data["beforeImageBase64"] = beforeData.base64EncodedString()
            }

            if let afterData = record.afterImageData {
                data["afterImageBase64"] = afterData.base64EncodedString()
            }

            if let memo = record.memo {
                data["memo"] = memo
            }

            try await ref.child("meals").child(myUserId).child(dateString).child(mealType.rawValue).setValue(data)
        }

        print("✅ 식단 업로드 완료: \(dateString)")
    }

    // MARK: - 샘플 데이터 생성

    /// 앱 첫 실행 시 샘플 데이터 자동 생성
    private func createSampleDataIfNeeded() async {
        // 이미 생성했는지 확인
        let key = "sampleDataCreated_v1"
        guard !UserDefaults.standard.bool(forKey: key) else {
            print("ℹ️ 샘플 데이터가 이미 생성되어 있습니다")
            return
        }

        // Firebase에 샘플 데이터가 있는지 확인
        do {
            let snapshot = try await ref.child("userCodes").child("ABCABC").getData()
            if snapshot.exists() {
                print("ℹ️ Firebase에 샘플 데이터가 이미 존재합니다")
                UserDefaults.standard.set(true, forKey: key)
                return
            }
        } catch {
            print("⚠️ 샘플 데이터 확인 중 오류: \(error)")
        }

        // 샘플 데이터 생성
        do {
            try await createSampleFriend()
            UserDefaults.standard.set(true, forKey: key)
            print("✅ 앱 첫 실행 - 샘플 데이터 자동 생성 완료")
        } catch {
            print("❌ 샘플 데이터 자동 생성 실패: \(error)")
        }
    }

    /// 테스트용 샘플 친구 데이터 생성 (코드: ABCABC)
    func createSampleFriend() async throws {
        let sampleUserId = "SAMPLE_USER_ABC"
        let sampleCode = "ABCABC"
        let sampleName = "샘플 친구"

        print("🔧 샘플 친구 데이터 생성 중...")

        // 1. 샘플 사용자 정보 저장
        try await ref.child("users").child(sampleUserId).child("code").setValue(sampleCode)
        try await ref.child("users").child(sampleUserId).child("name").setValue(sampleName)

        // 2. userCodes 매핑 추가
        try await ref.child("userCodes").child(sampleCode).setValue(sampleUserId)

        // 3. 현재 사용자의 모든 식단 데이터를 샘플 사용자에게 복사
        let snapshot = try await ref.child("meals").child(myUserId).getData()

        if let mealsData = snapshot.value {
            try await ref.child("meals").child(sampleUserId).setValue(mealsData)
            print("✅ 샘플 친구 생성 완료: \(sampleName) (\(sampleCode))")
        } else {
            print("⚠️ 복사할 식단 데이터가 없습니다")
        }
    }
}
