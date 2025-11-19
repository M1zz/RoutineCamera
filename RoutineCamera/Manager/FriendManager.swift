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
import AuthenticationServices
import CryptoKit

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

// 캐시 데이터 래퍼 (NSCache용)
class CachedMealData: NSObject {
    let meals: [MealType: MealRecord]
    let cachedAt: Date

    init(meals: [MealType: MealRecord], cachedAt: Date = Date()) {
        self.meals = meals
        self.cachedAt = cachedAt
    }
}

// 디스크 캐시용 구조체
struct CachedMealsData: Codable {
    let meals: [String: CachedMealInfo] // MealType.rawValue -> CachedMealInfo
    let cachedAt: Date
}

struct CachedMealInfo: Codable {
    let date: Date
    let memo: String?
    let beforeImageFileName: String?
    let afterImageFileName: String?
}

@MainActor
class FriendManager: ObservableObject {
    static let shared = FriendManager()

    @Published var myUserCode: String = ""
    @Published var myUserId: String = ""
    @Published var friends: [Friend] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isSignedIn = false // Apple 로그인 상태

    private var ref: DatabaseReference
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    // MARK: - 캐싱 시스템

    /// 메모리 캐시 (빠른 접근)
    private let memoryCache = NSCache<NSString, CachedMealData>()

    /// 디스크 캐시 디렉토리
    private let diskCacheURL: URL = {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return cacheDir.appendingPathComponent("FriendMealsCache", isDirectory: true)
    }()

    private init() {
        self.ref = Database.database().reference()

        // 디스크 캐시 디렉토리 생성
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        // 메모리 캐시 설정 (최대 50개 항목)
        memoryCache.countLimit = 50

        checkAuthState()
    }

    // MARK: - 에러 로깅

    /// Firebase 에러 로깅 (App Check 관련 에러 감지)
    private func logFirebaseError(_ error: Error, context: String) {
        let nsError = error as NSError
        print("❌ [\(context)] Firebase 에러 발생")
        print("   📝 메시지: \(error.localizedDescription)")
        print("   🔍 도메인: \(nsError.domain)")
        print("   🔢 코드: \(nsError.code)")

        // App Check 관련 에러 감지
        let isAppCheckError = nsError.domain.contains("AppCheck") ||
                             nsError.localizedDescription.contains("App Check") ||
                             nsError.code == 17999 // Firebase Auth App Check token invalid

        if isAppCheckError {
            print("   🔐 ⚠️ App Check 관련 에러 감지됨!")
            print("   💡 해결 방법:")
            print("      1. Firebase Console에서 App Check 설정 확인")
            print("      2. 디버그 환경: 디버그 토큰 등록 필요")
            print("      3. 프로덕션: App Attest/DeviceCheck 설정 확인")
        }

        // 상세 정보
        if !nsError.userInfo.isEmpty {
            print("   📋 상세 정보:")
            for (key, value) in nsError.userInfo {
                print("      - \(key): \(value)")
            }
        }
    }

    // MARK: - 인증 설정

    /// 현재 인증 상태 확인 (자동 로그인 하지 않음)
    private func checkAuthState() {
        if let currentUser = Auth.auth().currentUser {
            myUserId = currentUser.uid
            isSignedIn = true
            generateOrLoadUserCode()
            loadFriends()
            print("✅ 기존 로그인 유지: \(myUserId)")

            // 샘플 데이터는 수동 생성 버튼 사용 (자동 생성 제거)
            // _Concurrency.Task {
            //     await createSampleDataIfNeeded()
            // }
        } else {
            isSignedIn = false
            print("ℹ️ 로그인이 필요합니다")
        }
    }

    /// Apple 로그인
    func signInWithApple(authorization: ASAuthorization) async throws {
        print("🔐 [FriendManager] signInWithApple 시작")

        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            print("❌ [FriendManager] ASAuthorizationAppleIDCredential 캐스팅 실패")
            throw NSError(domain: "FriendManager", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Apple 인증 정보를 가져올 수 없습니다."])
        }
        print("✅ [FriendManager] Apple credential 획득")
        print("   - User: \(appleIDCredential.user)")

        guard let nonce = currentNonce else {
            print("❌ [FriendManager] currentNonce가 nil")
            throw NSError(domain: "FriendManager", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "인증 토큰이 유효하지 않습니다."])
        }
        print("✅ [FriendManager] nonce 확인: \(nonce.prefix(10))...")

        guard let appleIDToken = appleIDCredential.identityToken else {
            print("❌ [FriendManager] identityToken이 nil")
            throw NSError(domain: "FriendManager", code: -3,
                         userInfo: [NSLocalizedDescriptionKey: "Apple ID 토큰을 가져올 수 없습니다."])
        }
        print("✅ [FriendManager] identityToken 획득 (\(appleIDToken.count) bytes)")

        guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            print("❌ [FriendManager] identityToken UTF-8 파싱 실패")
            throw NSError(domain: "FriendManager", code: -4,
                         userInfo: [NSLocalizedDescriptionKey: "토큰 파싱에 실패했습니다."])
        }
        print("✅ [FriendManager] idTokenString 파싱 성공")

        // Firebase 인증
        print("🔥 [FriendManager] Firebase credential 생성 중...")
        let credential = OAuthProvider.credential(
            providerID: AuthProviderID.apple,
            idToken: idTokenString,
            rawNonce: nonce
        )
        print("✅ [FriendManager] Firebase credential 생성 완료")

        do {
            print("🔥 [FriendManager] Firebase 로그인 시도...")
            let result = try await Auth.auth().signIn(with: credential)
            print("✅ [FriendManager] Firebase 로그인 성공!")
            print("   - UID: \(result.user.uid)")
            print("   - Email: \(result.user.email ?? "없음")")

            await MainActor.run {
                self.myUserId = result.user.uid
                self.isSignedIn = true
                self.generateOrLoadUserCode()
                self.loadFriends()
                print("✅ Apple 로그인 성공: \(self.myUserId)")
            }

            // 샘플 데이터는 수동 생성 (자동 생성 제거)
            // await createSampleDataIfNeeded()

        } catch {
            logFirebaseError(error, context: "Apple 로그인")
            throw error
        }
    }

    /// Sign in with Apple용 nonce 생성
    func prepareAppleSignIn() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return sha256(nonce)
    }

    /// 로그아웃
    func signOut() {
        do {
            try Auth.auth().signOut()

            // 캐시 삭제
            if !myUserId.isEmpty {
                UserDefaults.standard.removeObject(forKey: "friendCode_\(myUserId)")
            }

            myUserId = ""
            myUserCode = ""
            friends = []
            isSignedIn = false
            print("✅ 로그아웃 완료")
        } catch {
            print("❌ 로그아웃 실패: \(error)")
        }
    }

    /// 회원 탈퇴 (계정 삭제)
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "FriendManager", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "로그인된 사용자가 없습니다."])
        }

        let userId = user.uid
        print("🗑️ 회원 탈퇴 시작: \(userId)")

        do {
            // 1. Firebase에서 사용자 데이터 삭제
            print("   📤 Firebase 데이터 삭제 중...")

            // 사용자 코드 매핑 삭제
            if !myUserCode.isEmpty {
                try await ref.child("userCodes").child(myUserCode).removeValue()
                print("   ✅ userCodes 삭제: \(myUserCode)")
            }

            // 사용자 정보 삭제
            try await ref.child("users").child(userId).removeValue()
            print("   ✅ users 데이터 삭제")

            // 식단 데이터 삭제
            try await ref.child("meals").child(userId).removeValue()
            print("   ✅ meals 데이터 삭제")

            // 2. Firebase Auth 계정 삭제
            try await user.delete()
            print("   ✅ Firebase Auth 계정 삭제")

            // 3. 로컬 상태 초기화
            await MainActor.run {
                // 캐시 삭제
                UserDefaults.standard.removeObject(forKey: "friendCode_\(userId)")

                myUserId = ""
                myUserCode = ""
                friends = []
                isSignedIn = false
            }

            print("✅ 회원 탈퇴 완료")

        } catch {
            print("❌ 회원 탈퇴 실패: \(error)")
            throw error
        }
    }

    // MARK: - Helper Functions for Apple Sign In

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
    }


    // MARK: - 사용자 코드 생성/로드

    private func generateOrLoadUserCode() {
        guard !myUserId.isEmpty else { return }

        // 1. 로컬 캐시에서 먼저 로드 (즉시 표시)
        let cacheKey = "friendCode_\(myUserId)"
        if let cachedCode = UserDefaults.standard.string(forKey: cacheKey) {
            myUserCode = cachedCode
            print("⚡ 캐시된 친구 코드 즉시 로드: \(cachedCode)")
        }

        // 2. Firebase에서 확인 (백그라운드)
        ref.child("users").child(myUserId).child("code").observeSingleEvent(of: .value) { [weak self] snapshot in
            guard let self = self else { return }

            if let code = snapshot.value as? String {
                _Concurrency.Task { @MainActor in
                    self.myUserCode = code
                    // 캐시 업데이트
                    UserDefaults.standard.set(code, forKey: cacheKey)
                    print("✅ Firebase에서 코드 확인: \(code)")
                }
            } else {
                // 새 코드 생성
                let newCode = self.generateRandomCode()
                self.ref.child("users").child(self.myUserId).child("code").setValue(newCode)
                self.ref.child("userCodes").child(newCode).setValue(self.myUserId)

                _Concurrency.Task { @MainActor in
                    self.myUserCode = newCode
                    // 캐시 저장
                    UserDefaults.standard.set(newCode, forKey: cacheKey)
                    print("✅ 새 친구 코드 생성 및 저장: \(newCode)")
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
            logFirebaseError(error, context: "친구 추가")
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

        print("🔍 [FriendManager] 친구 목록 로드 시작: \(myUserId)")
        let friendsPath = "users/\(myUserId)/friends"
        print("   📍 Firebase 경로: \(friendsPath)")

        ref.child("users").child(myUserId).child("friends").observe(.value) { [weak self] snapshot in
            print("📥 [FriendManager] Firebase 응답 받음")
            print("   - snapshot.exists: \(snapshot.exists())")
            print("   - snapshot.value type: \(type(of: snapshot.value))")

            guard let friendsData = snapshot.value as? [String: [String: Any]] else {
                print("⚠️ [FriendManager] friendsData 파싱 실패 또는 친구 없음")
                print("   - snapshot.value: \(String(describing: snapshot.value))")
                _Concurrency.Task { @MainActor in
                    self?.friends = []
                }
                return
            }

            print("✅ [FriendManager] friendsData 파싱 성공: \(friendsData.keys.count)개 친구")
            var loadedFriends: [Friend] = []

            for (friendId, data) in friendsData {
                print("   🔍 처리 중: friendId=\(friendId)")
                print("      - code: \(data["code"] ?? "없음")")
                print("      - name: \(data["name"] ?? "없음")")
                print("      - addedDate: \(data["addedDate"] ?? "없음")")

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
                    print("      ✅ 친구 추가 성공: \(name)")
                } else {
                    print("      ❌ 필수 필드 누락")
                }
            }

            _Concurrency.Task { @MainActor in
                self?.friends = loadedFriends.sorted { $0.addedDate > $1.addedDate }
                print("✅ [FriendManager] 친구 목록 로드 완료: \(loadedFriends.count)명")
                if loadedFriends.isEmpty {
                    print("⚠️ [FriendManager] 친구 목록이 비어있습니다!")
                }
            }
        }
    }

    // MARK: - 친구 식단 데이터 가져오기

    func loadFriendMeals(friendId: String, date: Date) async throws -> [MealType: MealRecord] {
        let dateString = dateFormatter.string(from: date)
        let cacheKey = "\(friendId)_\(dateString)" as NSString

        // 1. 메모리 캐시 확인
        if let cachedData = memoryCache.object(forKey: cacheKey) {
            print("⚡ [캐시] 메모리에서 로드: \(cacheKey)")
            return cachedData.meals
        }

        // 2. 디스크 캐시 확인
        if let diskCachedMeals = loadFromDiskCache(friendId: friendId, dateString: dateString) {
            print("💾 [캐시] 디스크에서 로드: \(cacheKey)")
            // 디스크에서 로드한 데이터를 메모리 캐시에도 저장
            memoryCache.setObject(CachedMealData(meals: diskCachedMeals), forKey: cacheKey)
            return diskCachedMeals
        }

        // 3. Firebase에서 다운로드
        print("🌐 [Firebase] 다운로드 시작: \(cacheKey)")
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

        // 4. 다운로드한 데이터를 캐시에 저장
        if !meals.isEmpty {
            // 메모리 캐시에 저장
            memoryCache.setObject(CachedMealData(meals: meals), forKey: cacheKey)
            // 디스크 캐시에 저장
            saveToDiskCache(friendId: friendId, dateString: dateString, meals: meals)
            print("💾 [캐시] 저장 완료: \(cacheKey)")
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

    // MARK: - 캐시 관리

    /// 디스크 캐시에서 로드
    private func loadFromDiskCache(friendId: String, dateString: String) -> [MealType: MealRecord]? {
        let cacheKey = "\(friendId)_\(dateString)"
        let cacheFileURL = diskCacheURL.appendingPathComponent("\(cacheKey).json")

        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()

            // 캐시된 구조체 디코딩
            let cachedData = try decoder.decode(CachedMealsData.self, from: data)

            // 캐시 유효 기간 확인 (7일)
            let cacheAge = Date().timeIntervalSince(cachedData.cachedAt)
            if cacheAge > 7 * 24 * 60 * 60 {
                // 7일 지난 캐시는 삭제
                try? FileManager.default.removeItem(at: cacheFileURL)
                return nil
            }

            // 이미지 데이터 로드
            var meals: [MealType: MealRecord] = [:]
            for (mealTypeString, mealInfo) in cachedData.meals {
                guard let mealType = MealType(rawValue: mealTypeString) else { continue }

                var beforeData: Data?
                var afterData: Data?

                // 이미지 파일 로드
                if let beforeFileName = mealInfo.beforeImageFileName {
                    let imageURL = diskCacheURL.appendingPathComponent(beforeFileName)
                    beforeData = try? Data(contentsOf: imageURL)
                }

                if let afterFileName = mealInfo.afterImageFileName {
                    let imageURL = diskCacheURL.appendingPathComponent(afterFileName)
                    afterData = try? Data(contentsOf: imageURL)
                }

                let record = MealRecord(
                    date: mealInfo.date,
                    mealType: mealType,
                    beforeImageData: beforeData,
                    afterImageData: afterData,
                    memo: mealInfo.memo,
                    recordedWithoutPhoto: false,
                    hidePhotoCountBadge: false
                )

                meals[mealType] = record
            }

            return meals
        } catch {
            print("❌ [캐시] 디스크 로드 실패: \(error)")
            return nil
        }
    }

    /// 디스크 캐시에 저장
    private func saveToDiskCache(friendId: String, dateString: String, meals: [MealType: MealRecord]) {
        let cacheKey = "\(friendId)_\(dateString)"
        let cacheFileURL = diskCacheURL.appendingPathComponent("\(cacheKey).json")

        var mealsInfo: [String: CachedMealInfo] = [:]

        for (mealType, record) in meals {
            var beforeImageFileName: String?
            var afterImageFileName: String?

            // 이미지 파일 저장
            if let beforeData = record.beforeImageData {
                beforeImageFileName = "\(cacheKey)_\(mealType.rawValue)_before.jpg"
                let imageURL = diskCacheURL.appendingPathComponent(beforeImageFileName!)
                try? beforeData.write(to: imageURL)
            }

            if let afterData = record.afterImageData {
                afterImageFileName = "\(cacheKey)_\(mealType.rawValue)_after.jpg"
                let imageURL = diskCacheURL.appendingPathComponent(afterImageFileName!)
                try? afterData.write(to: imageURL)
            }

            let info = CachedMealInfo(
                date: record.date,
                memo: record.memo,
                beforeImageFileName: beforeImageFileName,
                afterImageFileName: afterImageFileName
            )

            mealsInfo[mealType.rawValue] = info
        }

        let cachedData = CachedMealsData(
            meals: mealsInfo,
            cachedAt: Date()
        )

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(cachedData)
            try data.write(to: cacheFileURL)
        } catch {
            print("❌ [캐시] 디스크 저장 실패: \(error)")
        }
    }

    /// 캐시 전체 삭제 (설정에서 호출 가능)
    func clearCache() {
        // 메모리 캐시 삭제
        memoryCache.removeAllObjects()

        // 디스크 캐시 삭제
        if let files = try? FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }

        print("🗑️ [캐시] 전체 삭제 완료")
    }

    // MARK: - 내 식단 업로드 (선택적)

    func uploadMyMeals(date: Date, meals: [MealType: MealRecord]) async throws {
        print("🔄 [Firebase] uploadMyMeals 시작")
        print("   - myUserId: \(myUserId)")
        print("   - date: \(date)")
        print("   - meals count: \(meals.count)")

        guard !myUserId.isEmpty else {
            print("❌ [Firebase] myUserId가 비어있음 - 업로드 중단")
            return
        }

        let dateString = dateFormatter.string(from: date)
        print("   - dateString: \(dateString)")

        for (mealType, record) in meals {
            print("   📤 [Firebase] 업로드 중: \(mealType.rawValue)")

            var data: [String: Any] = [
                "timestamp": Date().timeIntervalSince1970
            ]

            // 이미지는 Firebase Storage에 업로드하고 URL 저장
            // 간단하게 하기 위해 여기서는 base64로 저장 (실제로는 Storage 사용 권장)
            if let beforeData = record.beforeImageData {
                data["beforeImageBase64"] = beforeData.base64EncodedString()
                print("      - beforeImage: \(beforeData.count) bytes")
            }

            if let afterData = record.afterImageData {
                data["afterImageBase64"] = afterData.base64EncodedString()
                print("      - afterImage: \(afterData.count) bytes")
            }

            if let memo = record.memo {
                data["memo"] = memo
                print("      - memo: \(memo)")
            }

            let path = "meals/\(myUserId)/\(dateString)/\(mealType.rawValue)"
            print("      - Firebase path: \(path)")

            do {
                try await ref.child("meals").child(myUserId).child(dateString).child(mealType.rawValue).setValue(data)
                print("      ✅ 업로드 성공: \(mealType.rawValue)")
            } catch {
                print("      ❌ 업로드 실패: \(error.localizedDescription)")
                throw error
            }
        }

        print("✅ [Firebase] 식단 업로드 완료: \(dateString)")
    }

    // MARK: - 샘플 데이터 생성

    /// 앱 시작 시 샘플 데이터 자동 생성 (친구 추가 테스트용)
    private func createSampleDataIfNeeded() async {
        print("🔍 [Firebase] 샘플 데이터 생성 시작")

        // myUserId가 비어있으면 아직 인증이 완료되지 않은 것
        guard !myUserId.isEmpty else {
            print("⚠️ [Firebase] 인증이 완료되지 않아 샘플 데이터 생성 건너뜀")
            return
        }

        // 인증 완료 후 약간의 지연 (Firebase 연결 안정화)
        try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000) // 0.5초 대기

        // 샘플 데이터 생성 (매번 새로 생성해서 테스트 가능하도록)
        do {
            print("   📝 [Firebase] 샘플 친구 데이터 생성 중...")
            try await createSampleFriend()
            print("   ✅ [Firebase] 샘플 데이터 생성 완료")
        } catch {
            print("   ❌ [Firebase] 샘플 데이터 생성 실패: \(error.localizedDescription)")
            // 실패해도 앱은 계속 작동
        }
    }

    /// 테스트용 샘플 친구 데이터 생성 (코드: ABCABC)
    func createSampleFriend() async throws {
        let sampleUserId = "SAMPLE_USER_ABC"
        let sampleCode = "ABCABC"
        let sampleName = "샘플 친구"

        await MainActor.run {
            isLoading = true
        }
        defer {
            _Concurrency.Task { @MainActor in
                self.isLoading = false
            }
        }

        print("🔧 샘플 친구 데이터 생성 중...")
        print("   - Firebase Database URL: \(ref.url)")
        print("   - Firebase Auth UID: \(Auth.auth().currentUser?.uid ?? "nil")")
        print("   - 현재 사용자 인증 상태: \(Auth.auth().currentUser != nil ? "인증됨" : "미인증")")

        // 이미 존재하는지 확인
        do {
            print("   🔍 기존 샘플 데이터 확인 중...")
            let snapshot = try await withTimeout(seconds: 5) {
                try await self.ref.child("userCodes").child(sampleCode).getData()
            }
            if snapshot.exists() {
                print("   ℹ️ 샘플 친구가 이미 존재합니다")
                return
            }
        } catch is TimeoutError {
            print("   ⚠️ 확인 타임아웃 - 계속 진행")
        } catch {
            print("   ⚠️ 확인 실패 - 계속 진행: \(error)")
        }

        // Firebase 연결 테스트
        print("   🔥 Firebase 연결 테스트 중...")

        // 1. 샘플 사용자 정보 저장
        do {
            print("   📝 사용자 코드 저장 시도: /users/\(sampleUserId)/code")
            print("      ⏱️ 타임아웃: 10초")

            try await withTimeout(seconds: 10) {
                try await self.ref.child("users").child(sampleUserId).child("code").setValue(sampleCode)
            }

            print("   ✅ 코드 저장 완료")
        } catch is TimeoutError {
            print("   ❌ 코드 저장 타임아웃 (10초 초과)")
            print("      Firebase 연결 문제 또는 Security Rules 확인 필요")
            throw NSError(domain: "FriendManager", code: -100,
                         userInfo: [NSLocalizedDescriptionKey: "Firebase 연결 타임아웃"])
        } catch {
            logFirebaseError(error, context: "샘플 친구 생성")
            throw error
        }

        do {
            print("   📝 사용자 이름 저장 시도: /users/\(sampleUserId)/name")
            try await ref.child("users").child(sampleUserId).child("name").setValue(sampleName)
            print("   ✅ 이름 저장 완료")
        } catch {
            print("   ❌ 이름 저장 실패: \(error)")
            throw error
        }

        print("   ✅ 샘플 사용자 정보 저장 완료")

        // 2. userCodes 매핑 추가
        do {
            print("   📝 userCodes 매핑 저장 시도: /userCodes/\(sampleCode)")
            try await ref.child("userCodes").child(sampleCode).setValue(sampleUserId)
            print("   ✅ userCodes 매핑 추가 완료")
        } catch {
            print("   ❌ userCodes 매핑 실패: \(error)")
            throw error
        }

        // 3. 내 실제 식단 데이터 복사 (최근 3일, 사진 포함)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        print("   📅 내 식단 데이터 복사 시작 (최근 3일, 사진 포함)")

        for dayOffset in 0..<3 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dateString = dateFormatter.string(from: date)

            // 내 식단 데이터 가져오기
            let myMeals = MealRecordStore.shared.getMeals(for: date)

            if myMeals.isEmpty {
                print("      ⚠️ \(dateString): 식단 데이터 없음 - 건너뜀")
                continue
            }

            print("      📦 \(dateString): \(myMeals.count)개 식단 복사 중...")

            // 각 끼니별로 데이터 복사
            for (mealType, record) in myMeals {
                var mealData: [String: Any] = [
                    "timestamp": date.timeIntervalSince1970
                ]

                // 사진 데이터 추가 (base64 인코딩)
                if let beforeData = record.beforeImageData {
                    mealData["beforeImageBase64"] = beforeData.base64EncodedString()
                    print("         - \(mealType.rawValue): 사진(전) \(beforeData.count) bytes")
                }

                if let afterData = record.afterImageData {
                    mealData["afterImageBase64"] = afterData.base64EncodedString()
                    print("         - \(mealType.rawValue): 사진(후) \(afterData.count) bytes")
                }

                // 메모 추가
                if let memo = record.memo {
                    mealData["memo"] = memo
                    print("         - \(mealType.rawValue): 메모 포함")
                }

                do {
                    let path = "/meals/\(sampleUserId)/\(dateString)/\(mealType.rawValue)"
                    print("         📝 식단 저장: \(path)")
                    try await ref.child("meals")
                        .child(sampleUserId)
                        .child(dateString)
                        .child(mealType.rawValue)
                        .setValue(mealData)
                    print("         ✅ 저장 완료")
                } catch {
                    print("         ❌ 식단 저장 실패: \(error)")
                    throw error
                }
            }

            print("      ✅ \(dateString) 식단 데이터 복사 완료")
        }

        print("✅ 샘플 친구 생성 완료: \(sampleName) (\(sampleCode)) - 내 최근 3일 식단 데이터(사진 포함) 복사됨")
    }

    // MARK: - Helper Functions

    /// 타임아웃 에러
    struct TimeoutError: Error {}

    /// 비동기 작업에 타임아웃 추가
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // 실제 작업
            group.addTask {
                try await operation()
            }

            // 타임아웃 작업
            group.addTask {
                try await _Concurrency.Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }

            // 먼저 완료되는 작업 반환
            if let result = try await group.next() {
                group.cancelAll()
                return result
            }

            throw TimeoutError()
        }
    }

    // MARK: - 닉네임 관리

    /// 내 닉네임을 Firebase에 저장
    func saveMyNickname(_ nickname: String) async throws {
        guard !myUserId.isEmpty else {
            let error = NSError(domain: "FriendManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "사용자 ID 없음"])
            print("❌ [FriendManager] 닉네임 저장 실패: 사용자 ID 없음")
            throw error
        }

        guard !nickname.isEmpty else {
            let error = NSError(domain: "FriendManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "닉네임이 비어있습니다"])
            print("❌ [FriendManager] 닉네임 저장 실패: 빈 닉네임")
            throw error
        }

        do {
            let nicknameData: [String: Any] = [
                "nickname": nickname,
                "updatedAt": ServerValue.timestamp()
            ]

            try await ref.child("users").child(myUserId).child("profile").setValue(nicknameData)
            print("✅ [FriendManager] 닉네임 저장 완료: \(nickname)")
        } catch {
            print("❌ [FriendManager] 닉네임 저장 Firebase 에러: \(error.localizedDescription)")
            throw error
        }
    }

    /// 특정 사용자의 닉네임 가져오기
    func getUserNickname(_ userId: String) async throws -> String {
        guard !userId.isEmpty else {
            print("❌ [FriendManager] 닉네임 조회 실패: 빈 사용자 ID")
            return "사용자"
        }

        do {
            let snapshot = try await ref.child("users").child(userId).child("profile").child("nickname").getData()

            guard let nickname = snapshot.value as? String, !nickname.isEmpty else {
                print("⚠️ [FriendManager] 닉네임 없음, 기본값 반환: \(userId)")
                return "사용자"
            }

            return nickname
        } catch {
            print("❌ [FriendManager] 닉네임 조회 Firebase 에러: \(error.localizedDescription)")
            return "사용자"  // 에러 발생 시 기본값 반환
        }
    }

    // MARK: - 피드백 관리

    /// 친구의 식단에 피드백 작성
    func addFeedback(to friendId: String, date: Date, mealType: MealType, content: String) async throws {
        guard !myUserId.isEmpty else {
            let error = NSError(domain: "FriendManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "사용자 ID 없음"])
            print("❌ [FriendManager] 피드백 작성 실패: 사용자 ID 없음")
            throw error
        }

        guard !friendId.isEmpty else {
            let error = NSError(domain: "FriendManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "친구 ID 없음"])
            print("❌ [FriendManager] 피드백 작성 실패: 친구 ID 없음")
            throw error
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let error = NSError(domain: "FriendManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "피드백 내용이 비어있습니다"])
            print("❌ [FriendManager] 피드백 작성 실패: 빈 내용")
            throw error
        }

        do {
            // 내 닉네임 가져오기
            let myNickname = SettingsManager.shared.nickname

            let dateString = dateFormatter.string(from: date)
            let feedbackId = UUID().uuidString

            let feedback = MealFeedback(
                id: feedbackId,
                authorId: myUserId,
                authorNickname: myNickname,
                content: content,
                createdAt: Date(),
                isRead: false
            )

            // Firebase에 저장
            let feedbackPath = "feedbacks/\(friendId)/\(dateString)/\(mealType.rawValue)/\(feedbackId)"

            let feedbackData: [String: Any] = [
                "id": feedback.id,
                "authorId": feedback.authorId,
                "authorNickname": feedback.authorNickname,
                "content": feedback.content,
                "createdAt": feedback.createdAt.timeIntervalSince1970,
                "isRead": feedback.isRead
            ]

            try await ref.child(feedbackPath).setValue(feedbackData)

            // 내가 보낸 피드백도 저장 (나중에 확인할 수 있도록)
            let sentFeedbackPath = "sentFeedbacks/\(myUserId)/\(dateString)/\(mealType.rawValue)/\(feedbackId)"
            let sentFeedbackData: [String: Any] = [
                "id": feedback.id,
                "recipientId": friendId,
                "content": feedback.content,
                "createdAt": feedback.createdAt.timeIntervalSince1970
            ]
            try await ref.child(sentFeedbackPath).setValue(sentFeedbackData)

            print("✅ [FriendManager] 피드백 작성 완료: \(friendId) / \(dateString) / \(mealType.rawValue)")
        } catch {
            print("❌ [FriendManager] 피드백 작성 Firebase 에러: \(error.localizedDescription)")
            throw error
        }
    }

    /// 내 식단의 피드백 목록 가져오기
    func getMyFeedbacks(date: Date, mealType: MealType) async throws -> [MealFeedback] {
        guard !myUserId.isEmpty else {
            print("❌ [FriendManager] 피드백 목록 조회 실패: 사용자 ID 없음")
            return []  // 에러를 throw하지 않고 빈 배열 반환
        }

        do {
            let dateString = dateFormatter.string(from: date)
            let feedbackPath = "feedbacks/\(myUserId)/\(dateString)/\(mealType.rawValue)"

            let snapshot = try await ref.child(feedbackPath).getData()

            // 데이터가 없으면 빈 배열 반환
            guard snapshot.exists(), let feedbacksDict = snapshot.value as? [String: [String: Any]] else {
                print("ℹ️ [FriendManager] 피드백 없음: \(dateString) / \(mealType.rawValue)")
                return []
            }

            var feedbacks: [MealFeedback] = []

            for (_, feedbackData) in feedbacksDict {
                // 필수 필드 검증
                guard let id = feedbackData["id"] as? String,
                      let authorId = feedbackData["authorId"] as? String,
                      let authorNickname = feedbackData["authorNickname"] as? String,
                      let content = feedbackData["content"] as? String,
                      let createdAtTimestamp = feedbackData["createdAt"] as? TimeInterval else {
                    print("⚠️ [FriendManager] 피드백 파싱 실패: 필수 필드 누락")
                    continue  // 잘못된 데이터는 건너뛰기
                }

                let isRead = feedbackData["isRead"] as? Bool ?? false
                let createdAt = Date(timeIntervalSince1970: createdAtTimestamp)

                let feedback = MealFeedback(
                    id: id,
                    authorId: authorId,
                    authorNickname: authorNickname,
                    content: content,
                    createdAt: createdAt,
                    isRead: isRead
                )

                feedbacks.append(feedback)
            }

            print("✅ [FriendManager] 피드백 목록 조회 완료: \(feedbacks.count)개")
            // 최신순 정렬
            return feedbacks.sorted { $0.createdAt > $1.createdAt }
        } catch {
            print("❌ [FriendManager] 피드백 목록 조회 Firebase 에러: \(error.localizedDescription)")
            return []  // 에러 발생 시 빈 배열 반환
        }
    }

    /// 내 식단의 안읽은 피드백 개수 가져오기
    func getUnreadFeedbackCount(date: Date, mealType: MealType) async throws -> Int {
        do {
            let feedbacks = try await getMyFeedbacks(date: date, mealType: mealType)
            let unreadCount = feedbacks.filter { !$0.isRead }.count
            print("ℹ️ [FriendManager] 안읽은 피드백: \(unreadCount)개 / 전체: \(feedbacks.count)개")
            return unreadCount
        } catch {
            print("❌ [FriendManager] 안읽은 피드백 개수 조회 에러: \(error.localizedDescription)")
            return 0  // 에러 발생 시 0 반환
        }
    }

    /// 피드백을 읽음으로 표시
    func markFeedbackAsRead(feedbackId: String, date: Date, mealType: MealType) async throws {
        guard !myUserId.isEmpty else {
            print("❌ [FriendManager] 피드백 읽음 처리 실패: 사용자 ID 없음")
            return  // 에러를 throw하지 않고 조용히 반환
        }

        guard !feedbackId.isEmpty else {
            print("❌ [FriendManager] 피드백 읽음 처리 실패: 피드백 ID 없음")
            return
        }

        do {
            let dateString = dateFormatter.string(from: date)
            let feedbackPath = "feedbacks/\(myUserId)/\(dateString)/\(mealType.rawValue)/\(feedbackId)"

            try await ref.child(feedbackPath).child("isRead").setValue(true)
            print("✅ [FriendManager] 피드백 읽음 처리: \(feedbackId)")
        } catch {
            print("❌ [FriendManager] 피드백 읽음 처리 Firebase 에러: \(error.localizedDescription)")
            // 읽음 처리 실패는 치명적이지 않으므로 에러를 던지지 않음
        }
    }

    /// 모든 피드백을 읽음으로 표시
    func markAllFeedbacksAsRead(date: Date, mealType: MealType) async throws {
        do {
            let feedbacks = try await getMyFeedbacks(date: date, mealType: mealType)

            let unreadFeedbacks = feedbacks.filter { !$0.isRead }
            guard !unreadFeedbacks.isEmpty else {
                print("ℹ️ [FriendManager] 읽지 않은 피드백 없음")
                return
            }

            print("ℹ️ [FriendManager] \(unreadFeedbacks.count)개 피드백 읽음 처리 시작")

            for feedback in unreadFeedbacks {
                try await markFeedbackAsRead(feedbackId: feedback.id, date: date, mealType: mealType)
            }

            print("✅ [FriendManager] 모든 피드백 읽음 처리 완료")
        } catch {
            print("❌ [FriendManager] 모든 피드백 읽음 처리 에러: \(error.localizedDescription)")
            // 에러를 던지지 않고 조용히 실패 처리
        }
    }

    /// 내가 보낸 피드백 목록 가져오기
    func getMySentFeedbacks(date: Date, mealType: MealType) async throws -> [SentFeedback] {
        guard !myUserId.isEmpty else {
            print("❌ [FriendManager] 보낸 피드백 조회 실패: 사용자 ID 없음")
            return []
        }

        do {
            let dateString = dateFormatter.string(from: date)
            let sentFeedbackPath = "sentFeedbacks/\(myUserId)/\(dateString)/\(mealType.rawValue)"

            let snapshot = try await ref.child(sentFeedbackPath).getData()

            guard snapshot.exists(), let feedbacksDict = snapshot.value as? [String: [String: Any]] else {
                print("ℹ️ [FriendManager] 보낸 피드백 없음: \(dateString) / \(mealType.rawValue)")
                return []
            }

            var sentFeedbacks: [SentFeedback] = []

            for (_, feedbackData) in feedbacksDict {
                guard let id = feedbackData["id"] as? String,
                      let recipientId = feedbackData["recipientId"] as? String,
                      let content = feedbackData["content"] as? String,
                      let createdAtTimestamp = feedbackData["createdAt"] as? TimeInterval else {
                    print("⚠️ [FriendManager] 보낸 피드백 파싱 실패: 필수 필드 누락")
                    continue
                }

                let createdAt = Date(timeIntervalSince1970: createdAtTimestamp)

                let feedback = SentFeedback(
                    id: id,
                    recipientId: recipientId,
                    content: content,
                    createdAt: createdAt
                )

                sentFeedbacks.append(feedback)
            }

            print("✅ [FriendManager] 보낸 피드백 조회 완료: \(sentFeedbacks.count)개")
            return sentFeedbacks.sorted { $0.createdAt > $1.createdAt }
        } catch {
            print("❌ [FriendManager] 보낸 피드백 조회 Firebase 에러: \(error.localizedDescription)")
            return []
        }
    }
}
