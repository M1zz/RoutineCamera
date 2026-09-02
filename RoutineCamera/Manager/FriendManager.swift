//
//  FriendManager.swift
//  RoutineCamera
//
//  친구 관리 및 CloudKit 공개 DB 연동
//
//  구조:
//  - 신원: iCloud 계정 (CKContainer userRecordID) — 별도 로그인 불필요
//  - RCUser 레코드: 친구 코드·닉네임·친구 목록(JSON). recordName = "user_<userId>"
//  - Meal 레코드: 날짜·끼니별 식단. recordName = "meal_<userId>_<날짜>_<끼니키>"
//    사진은 CKAsset (base64 아님)
//  - Feedback 레코드: 피드백/콕 찌르기. 받는 사람의 CKQuerySubscription이 푸시를 배달
//  - 공개 DB 권한: 누구나 읽기, 생성자만 수정 — 기존 Firebase 규칙과 동일한 모델
//

import Foundation
import UIKit
import CloudKit
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
    // 실제로 먹은(찍은) 시각. 옵셔널이라 이 키가 없는 예전 캐시도 그대로 읽힌다.
    var capturedAt: Date?
}

@MainActor
class FriendManager: ObservableObject {
    static let shared = FriendManager()

    @Published var myUserCode: String = ""
    @Published var myUserId: String = ""
    @Published var friends: [Friend] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isSignedIn = false // iCloud 계정 사용 가능 여부
    /// 내 코드가 서버에서 검색되지 않을 때의 안내 (배포 환경 불일치·인덱스 미반영·레코드 생성 실패 등)
    @Published var codeStatusWarning: String?
    /// 내가 받은 친구 요청 (아직 수락/거절 안 함)
    @Published var incomingRequests: [FriendRequest] = []
    /// 내가 보낸 요청 (상대 수락 대기 또는 거절됨)
    @Published var pendingFriends: [PendingFriend] = []
    /// 내가 속한 그룹
    @Published var groups: [FriendGroup] = []
    /// 그룹 목록을 불러오는 중인지 (빈 목록과 로딩 중을 구분해서 보여주기 위함)
    @Published var isLoadingGroups = false
    /// 그룹 목록 조회 실패 사유 (성공 시 nil)
    @Published var groupsError: String?
    /// 친구 관계 조회 실패 사유 (성공 시 nil)
    @Published var socialError: String?
    /// 친구 관계를 불러오는 중인지 (빈 목록과 로딩 중을 구분)
    @Published var isLoadingSocial = false

    // MARK: - CloudKit

    static let userRecordType = "RCUser"
    static let mealRecordType = "Meal"
    static let feedbackRecordType = "Feedback"
    private static let feedbackSubscriptionSavedKey = "feedbackSubscriptionUserId"
    private static let readFeedbackIdsKey = "readFeedbackIds"

    var database: CKDatabase {
        CKContainer.default().publicCloudDatabase
    }

    /// 내 RCUser 레코드 (친구 코드·닉네임·친구 목록 보관)
    var myUserRecord: CKRecord?

    // MARK: - 캐싱 시스템

    /// 메모리 캐시 (빠른 접근)
    let memoryCache = NSCache<NSString, CachedMealData>()

    /// 영구 디스크 캐시 (Application Support)
    private var diskCache: FriendMealCache { FriendMealCache.shared }

    private init() {
        // 메모리 캐시: 개수와 총 바이트 양쪽으로 제한 (사진이 들어 있어 개수만으로는 부족)
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 80 * 1024 * 1024

        // 디스크 캐시 용량 정리 (상한 초과 시 오래된 것부터). 실행 직후를 피해 뒤로 미룬다.
        _Concurrency.Task {
            FriendMealCache.shared.enforceBudget()
        }

        // iCloud 계정 상태 확인 및 변경 감지
        checkAccountState()
        NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor [weak self] in
                self?.checkAccountState()
            }
        }
    }

    // MARK: - 계정(iCloud) 상태

    /// iCloud 계정 확인 후 내 사용자 레코드 준비. 별도 로그인 과정 없음.
    private func checkAccountState() {
        _Concurrency.Task {
            do {
                let status = try await CKContainer.default().accountStatus()
                guard status == .available else {
                    self.isSignedIn = false
                    print("ℹ️ [CloudKit] iCloud 미로그인 (status: \(status.rawValue))")
                    return
                }

                let recordID = try await CKContainer.default().userRecordID()
                self.myUserId = recordID.recordName
                self.isSignedIn = true
                print("✅ [CloudKit] iCloud 계정 확인: \(self.myUserId)")

                // 캐시된 친구 코드 즉시 표시
                if let cachedCode = UserDefaults.standard.string(forKey: "friendCode_\(self.myUserId)") {
                    self.myUserCode = cachedCode
                }

                await self.bootstrapMyUserRecord()
                self.ensureFeedbackSubscription()
                self.ensureFriendLinkSubscription()
            } catch {
                self.isSignedIn = false
                print("❌ [CloudKit] 계정 확인 실패: \(error.localizedDescription)")
            }
        }
    }

    /// 내 RCUser 레코드 로드(없으면 생성) + 코드·친구 목록 반영
    private func bootstrapMyUserRecord() async {
        guard !myUserId.isEmpty else { return }

        let recordID = CKRecord.ID(recordName: Self.userRecordName(for: myUserId))

        do {
            let record = try await database.record(for: recordID)
            myUserRecord = record

            if let code = record["code"] as? String {
                myUserCode = code
                UserDefaults.standard.set(code, forKey: "friendCode_\(myUserId)")
            }
            friends = Self.decodeFriends(from: record)
            print("✅ [CloudKit] 사용자 레코드 로드: 코드 \(myUserCode), 친구 \(friends.count)명")
        } catch let error as CKError where error.code == .unknownItem {
            // 첫 사용 - 새 레코드 생성
            let newCode = generateRandomCode()
            let record = CKRecord(recordType: Self.userRecordType, recordID: recordID)
            record["code"] = newCode
            record["nickname"] = SettingsManager.shared.nickname

            do {
                let saved = try await database.save(record)
                myUserRecord = saved
                myUserCode = newCode
                UserDefaults.standard.set(newCode, forKey: "friendCode_\(myUserId)")
                print("✅ [CloudKit] 새 친구 코드 생성: \(newCode)")
            } catch {
                print("❌ [CloudKit] 사용자 레코드 생성 실패: \(error.localizedDescription)")
            }
        } catch {
            print("❌ [CloudKit] 사용자 레코드 로드 실패: \(error.localizedDescription)")
        }

        await migrateLegacyFriendsIfNeeded()
        await refreshSocialGraph()
        await loadMyGroups()
        await verifyMyCodeRegistered()
    }

    /// 내 RCUser 레코드 저장 (last-writer-wins)
    private func saveMyUserRecord() async throws {
        guard let record = myUserRecord else { return }
        let (saveResults, _) = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .allKeys,
            atomically: false
        )
        for (_, result) in saveResults {
            myUserRecord = try result.get()
        }
    }

    static func userRecordName(for userId: String) -> String {
        "user_\(userId)"
    }

    private static func decodeFriends(from record: CKRecord) -> [Friend] {
        guard let json = record["friendsJSON"] as? String,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Friend].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.addedDate > $1.addedDate }
    }

    func persistFriends() async throws {
        guard let record = myUserRecord else { return }
        let data = try JSONEncoder().encode(friends)
        record["friendsJSON"] = String(data: data, encoding: .utf8)
        try await saveMyUserRecord()
    }

    /// 회원 탈퇴: 내가 만든 공유 데이터(사용자 레코드·식단·피드백)를 모두 삭제
    func deleteAccount() async throws {
        guard !myUserId.isEmpty else {
            throw NSError(domain: "FriendManager", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "iCloud 계정을 확인할 수 없습니다."])
        }

        let userId = myUserId
        print("🗑️ 공유 데이터 삭제 시작: \(userId)")

        // 1. 내 식단 레코드 삭제
        try await deleteMyRecords(ofType: Self.mealRecordType, field: "ownerId", value: userId)

        // 2. 내가 작성한 피드백 삭제
        try await deleteMyRecords(ofType: Self.feedbackRecordType, field: "authorId", value: userId)

        // 3. 친구 링크·그룹 멤버십·내가 만든 그룹 삭제
        try? await deleteMyRecords(ofType: Self.friendLinkRecordType, field: "ownerId", value: userId)
        try? await deleteMyRecords(ofType: Self.groupMemberRecordType, field: "userId", value: userId)
        try? await deleteMyRecords(ofType: Self.groupRecordType, field: "ownerId", value: userId)

        // 4. 사용자 레코드 삭제
        _ = try? await database.deleteRecord(withID: CKRecord.ID(recordName: Self.userRecordName(for: userId)))

        // 5. 푸시 구독 해제
        _ = try? await database.deleteSubscription(withID: "feedback-sub-\(userId)")
        _ = try? await database.deleteSubscription(withID: "friendlink-sub-\(userId)")
        UserDefaults.standard.removeObject(forKey: Self.feedbackSubscriptionSavedKey)
        UserDefaults.standard.removeObject(forKey: Self.friendLinkSubscriptionKey)
        UserDefaults.standard.removeObject(forKey: "friendLinkMigrated_\(userId)")

        // 6. 로컬 상태 초기화 후 새 계정으로 재시작
        UserDefaults.standard.removeObject(forKey: "friendCode_\(userId)")
        myUserRecord = nil
        myUserCode = ""
        friends = []
        incomingRequests = []
        pendingFriends = []
        groups = []
        clearCache()

        print("✅ 공유 데이터 삭제 완료 - 새 코드로 재시작")
        await bootstrapMyUserRecord()
        ensureFeedbackSubscription()
        ensureFriendLinkSubscription()
    }

    func deleteMyRecords(ofType type: String, field: String, value: String) async throws {
        let query = CKQuery(recordType: type, predicate: NSPredicate(format: "\(field) == %@", value))
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let (results, nextCursor): ([(CKRecord.ID, Result<CKRecord, Error>)], CKQueryOperation.Cursor?)
            if let existing = cursor {
                (results, nextCursor) = try await database.records(continuingMatchFrom: existing)
            } else {
                (results, nextCursor) = try await database.records(matching: query)
            }

            let ids = results.map { $0.0 }
            if !ids.isEmpty {
                _ = try await database.modifyRecords(saving: [], deleting: ids, atomically: false)
                print("   🗑️ \(type) \(ids.count)개 삭제")
            }
            cursor = nextCursor
        } while cursor != nil
    }

    // MARK: - 친구 코드

    func generateRandomCode() -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // 혼동되는 문자 제외 (I, O, 0, 1)
        return String((0..<6).map { _ in characters.randomElement()! })
    }

    /// 코드로 RCUser 레코드 조회. 일치하는 사용자가 없으면 nil, 조회 자체가 실패하면 원인별 메시지로 throw
    func findUserRecord(byCode code: String) async throws -> CKRecord? {
        let query = CKQuery(recordType: Self.userRecordType,
                            predicate: NSPredicate(format: "code == %@", code))
        do {
            let (results, _) = try await database.records(matching: query, resultsLimit: 1)
            return try results.first?.1.get()
        } catch let error as CKError {
            throw Self.lookupError(from: error)
        }
    }

    /// CloudKit 조회 실패를 원인별 안내 문구로 변환 (0건 = 코드 없음과 구분하기 위함)
    static func lookupError(from error: CKError) -> NSError {
        let message: String
        switch error.code {
        case .unknownItem:
            // 이 환경(Development/Production)에 RCUser 스키마가 아직 배포되지 않음
            message = "친구 코드 저장소가 아직 준비되지 않았어요. 잠시 후 다시 시도해주세요."
        case .invalidArguments:
            // code 필드에 Queryable 인덱스가 없을 때
            message = "친구 코드 검색 설정에 문제가 있어요(검색 인덱스 없음). 앱 업데이트 후 다시 시도해주세요."
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
            message = "네트워크 연결을 확인한 뒤 다시 시도해주세요."
        case .notAuthenticated:
            message = "iCloud에 로그인한 뒤 다시 시도해주세요."
        default:
            message = error.localizedDescription
        }
        print("❌ [CloudKit] 코드 조회 실패(\(error.code.rawValue)): \(error.localizedDescription)")
        return NSError(domain: "FriendManager", code: error.code.rawValue,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// 내 코드가 실제로 서버에서 검색되는지 확인.
    /// 화면의 코드는 UserDefaults 캐시에서도 나오기 때문에, 레코드가 없거나
    /// 배포 환경(Development/Production)이 다른 "유령 코드" 상태를 여기서 잡아낸다.
    /// 새로 만든 레코드는 인덱싱에 몇 초 걸릴 수 있어 몇 번 재시도한 뒤에만 경고한다.
    func verifyMyCodeRegistered(retries: Int = 2) async {
        guard !myUserCode.isEmpty else { return }
        let code = myUserCode

        for attempt in 0...max(0, retries) {
            do {
                if try await findUserRecord(byCode: code) != nil {
                    codeStatusWarning = nil
                    print("✅ [CloudKit] 내 코드 조회 확인: \(code)")
                    return
                }
            } catch {
                // 네트워크 등 조회 자체가 실패한 경우는 경고하지 않음 (오탐 방지)
                print("ℹ️ [CloudKit] 코드 자가검증 건너뜀: \(error.localizedDescription)")
                return
            }

            if attempt < max(0, retries) {
                try? await _Concurrency.Task.sleep(nanoseconds: 3_000_000_000)
            }
        }

        guard code == myUserCode else { return } // 검증 중 코드가 바뀌었으면 무시
        codeStatusWarning = "이 코드가 아직 서버에서 검색되지 않아요. 친구가 추가하면 '존재하지 않는 코드'로 나올 수 있어요."
        print("⚠️ [CloudKit] 내 코드 \(code)가 쿼리로 조회되지 않음 (레코드 미생성 또는 배포 환경 불일치)")
    }

    /// 끼니를 레코드 이름에 쓸 수 있는 영문 키로 변환 (rawValue는 한글)
    static func mealKey(_ type: MealType) -> String {
        String(describing: type) // breakfast, lunch, dinner, snack1...
    }

    // MARK: - 친구 관리

    /// 친구 끊기: 내 쪽 링크를 지운다. (상대 링크는 상대만 지울 수 있어 그대로 남지만,
    /// 상대 화면에서는 "상대가 끊음"으로 보이고 내 목록에서는 사라진다)
    func removeFriend(friendId: String) async throws {
        isLoading = true
        defer { isLoading = false }

        try await deleteMyLink(otherId: friendId)

        // 구버전 호환용 friendsJSON에도 남아 있으면 함께 정리
        if friends.contains(where: { $0.id == friendId }) {
            friends.removeAll { $0.id == friendId }
            try? await persistFriends()
        }

        await refreshSocialGraph()
        print("✅ 친구 삭제 완료: \(friendId)")
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
        if let diskCachedMeals = loadFromDiskCache(friendId: friendId, dateString: dateString, date: date) {
            print("💾 [캐시] 디스크에서 로드: \(cacheKey)")
            memoryCache.setObject(CachedMealData(meals: diskCachedMeals), forKey: cacheKey)
            return diskCachedMeals
        }

        // 3. CloudKit에서 다운로드 - 끼니별 레코드 ID로 직접 조회 (쿼리·인덱스 불필요)
        print("🌐 [CloudKit] 다운로드 시작: \(cacheKey)")
        let recordIDs = MealType.allCases.map {
            CKRecord.ID(recordName: "meal_\(friendId)_\(dateString)_\(Self.mealKey($0))")
        }

        let results = try await database.records(for: recordIDs)

        var meals: [MealType: MealRecord] = [:]

        for mealType in MealType.allCases {
            let id = CKRecord.ID(recordName: "meal_\(friendId)_\(dateString)_\(Self.mealKey(mealType))")
            guard case .success(let record)? = results[id] else { continue }

            meals[mealType] = Self.mealRecord(from: record, date: date, mealType: mealType)
        }

        // 4. 다운로드한 데이터를 캐시에 저장 (기록 없는 날도 저장해 반복 조회를 막는다)
        cacheMeals(meals, friendId: friendId, dateString: dateString)
        print("💾 [캐시] 저장 완료: \(cacheKey) (\(meals.count)개)")

        return meals
    }

    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    // MARK: - 캐시 관리

    /// 디스크 캐시에서 로드 (지난 날짜는 만료 없음, 기록 없는 날도 "없음"으로 캐시됨)
    func loadFromDiskCache(friendId: String, dateString: String, date: Date) -> [MealType: MealRecord]? {
        diskCache.load(friendId: friendId, dateString: dateString, date: date)
    }

    /// 디스크 캐시에 저장 (빈 결과도 저장해 같은 날을 다시 조회하지 않는다)
    func saveToDiskCache(friendId: String, dateString: String, meals: [MealType: MealRecord]) {
        diskCache.save(friendId: friendId, dateString: dateString, meals: meals)
    }

    /// 메모리 + 디스크에 함께 저장. 메모리 비용은 사진 바이트 기준으로 계산한다.
    func cacheMeals(_ meals: [MealType: MealRecord], friendId: String, dateString: String) {
        let cost = meals.values.reduce(0) { $0 + ($1.beforeImageData?.count ?? 0) + ($1.afterImageData?.count ?? 0) }
        memoryCache.setObject(CachedMealData(meals: meals),
                              forKey: "\(friendId)_\(dateString)" as NSString,
                              cost: cost)
        saveToDiskCache(friendId: friendId, dateString: dateString, meals: meals)
    }

    /// 특정 날짜 캐시 무효화 (강제 새로고침용)
    func invalidateCache(friendId: String, date: Date) {
        let dateString = dateFormatter.string(from: date)
        memoryCache.removeObject(forKey: "\(friendId)_\(dateString)" as NSString)
        diskCache.invalidate(friendId: friendId, dateString: dateString)
    }

    /// 캐시 전체 삭제 (설정에서 호출 가능)
    func clearCache() {
        memoryCache.removeAllObjects()
        diskCache.clearAll()
    }

    // MARK: - 업로드용 이미지 축소

    /// 업로드 전 이미지 축소 (긴 변 1024px, JPEG 0.6)
    /// 원본(2~4MB)을 그대로 올리면 20명 이벤트 기준 하루 수 GB 전송이 되므로 필수
    nonisolated static func resizeForUpload(_ data: Data, maxDimension: CGFloat = 1024, quality: CGFloat = 0.6) -> Data {
        guard let image = UIImage(data: data) else { return data }

        let largerSide = max(image.size.width, image.size.height)
        // 이미 충분히 작으면 재압축만 (그래도 원본보다 커지면 원본 유지)
        let scale = min(1.0, maxDimension / largerSide)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        guard let resizedData = resized.jpegData(compressionQuality: quality), resizedData.count < data.count else {
            return data
        }
        return resizedData
    }

    // MARK: - 내 식단 업로드 (선택적)

    func uploadMyMeals(date: Date, meals: [MealType: MealRecord]) async throws {
        print("🔄 [CloudKit] uploadMyMeals 시작 (\(meals.count)개)")

        guard !myUserId.isEmpty else {
            print("❌ [CloudKit] myUserId가 비어있음 - 업로드 중단")
            return
        }

        let dateString = dateFormatter.string(from: date)
        var records: [CKRecord] = []
        var tempFiles: [URL] = []
        defer { tempFiles.forEach { try? FileManager.default.removeItem(at: $0) } }

        for (mealType, mealRecord) in meals {
            let recordName = "meal_\(myUserId)_\(dateString)_\(Self.mealKey(mealType))"
            let record = CKRecord(recordType: Self.mealRecordType,
                                  recordID: CKRecord.ID(recordName: recordName))
            record["ownerId"] = myUserId
            record["dateString"] = dateString
            record["mealType"] = Self.mealKey(mealType)
            // 친구 화면에서 "몇 시에 먹었는지"를 보여주려면 업로드 시각이 아니라 기록 시각이어야 한다
            record["timestamp"] = (mealRecord.capturedAt ?? mealRecord.date).timeIntervalSince1970
            record["memo"] = mealRecord.memo

            // 사진은 CKAsset으로 업로드 (전송량 절감을 위해 긴 변 1024px로 축소)
            if let beforeData = mealRecord.beforeImageData {
                let resized = Self.resizeForUpload(beforeData)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(recordName)_before.jpg")
                try resized.write(to: url)
                tempFiles.append(url)
                record["beforeImage"] = CKAsset(fileURL: url)
            }

            if let afterData = mealRecord.afterImageData {
                let resized = Self.resizeForUpload(afterData)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(recordName)_after.jpg")
                try resized.write(to: url)
                tempFiles.append(url)
                record["afterImage"] = CKAsset(fileURL: url)
            }

            records.append(record)
        }

        guard !records.isEmpty else { return }

        let (saveResults, _) = try await database.modifyRecords(
            saving: records,
            deleting: [],
            savePolicy: .allKeys,
            atomically: false
        )

        for (id, result) in saveResults {
            if case .failure(let error) = result {
                print("   ❌ 업로드 실패 (\(id.recordName)): \(error.localizedDescription)")
                throw error
            }
        }

        print("✅ [CloudKit] 식단 업로드 완료: \(dateString)")
    }

    /// 특정 날짜의 내 식단을 서버에서 삭제 (기록을 모두 지웠을 때 친구 화면에서도 사라지도록)
    func deleteMyMeals(date: Date) async {
        guard !myUserId.isEmpty else { return }

        let dateString = dateFormatter.string(from: date)
        let ids = MealType.allCases.map {
            CKRecord.ID(recordName: "meal_\(myUserId)_\(dateString)_\(Self.mealKey($0))")
        }
        _ = try? await database.modifyRecords(saving: [], deleting: ids, atomically: false)
    }

    /// 이미 서버에 올라간 끼니 수를 날짜별로 확인.
    /// `desiredKeys: []` 로 필드를 하나도 받지 않아 사진을 내려받지 않는다.
    func uploadedMealCounts(dates: [Date]) async throws -> [String: Int] {
        guard !myUserId.isEmpty, !dates.isEmpty else { return [:] }

        var dateForID: [CKRecord.ID: String] = [:]
        for date in dates {
            let dateString = dateFormatter.string(from: date)
            for mealType in MealType.allCases {
                let id = CKRecord.ID(recordName: "meal_\(myUserId)_\(dateString)_\(Self.mealKey(mealType))")
                dateForID[id] = dateString
            }
        }

        var counts: [String: Int] = [:]
        let ids = Array(dateForID.keys)

        for start in stride(from: 0, to: ids.count, by: 100) {
            let chunk = Array(ids[start..<min(start + 100, ids.count)])
            let results = try await database.records(for: chunk, desiredKeys: [])
            for (id, result) in results {
                guard case .success = result, let dateString = dateForID[id] else { continue }
                counts[dateString, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - 샘플 데이터 생성

    /// 테스트용 샘플 친구 데이터 생성 (코드: ABCABC)
    func createSampleFriend() async throws {
        let sampleUserId = "SAMPLE_USER_ABC"
        let sampleCode = "ABCABC"
        let sampleName = "샘플 친구"

        isLoading = true
        defer { isLoading = false }

        print("🔧 샘플 친구 데이터 생성 중...")

        // 1. 샘플 사용자 레코드 (이미 다른 사용자가 만들었으면 그대로 사용)
        let userRecord = CKRecord(recordType: Self.userRecordType,
                                  recordID: CKRecord.ID(recordName: Self.userRecordName(for: sampleUserId)))
        userRecord["code"] = sampleCode
        userRecord["nickname"] = sampleName

        do {
            _ = try await database.modifyRecords(saving: [userRecord], deleting: [], savePolicy: .allKeys, atomically: false)
            print("   ✅ 샘플 사용자 저장")
        } catch let error as CKError where error.code == .permissionFailure {
            print("   ℹ️ 샘플 사용자가 이미 존재 (다른 계정이 생성)")
        }

        // 샘플 친구가 나를 수락한 것처럼 역방향 링크도 만들어 둔다 (양방향 판정 통과용)
        if !myUserId.isEmpty {
            let link = CKRecord(recordType: Self.friendLinkRecordType,
                                recordID: CKRecord.ID(recordName: Self.friendLinkName(owner: sampleUserId, other: myUserId)))
            link["ownerId"] = sampleUserId
            link["otherId"] = myUserId
            link["ownerCode"] = sampleCode
            link["otherCode"] = myUserCode
            link["ownerNickname"] = sampleName
            link["otherNickname"] = SettingsManager.shared.nickname
            link["state"] = FriendLinkState.accepted.rawValue
            link["isLegacy"] = 0
            link["createdAtTS"] = Date().timeIntervalSince1970

            do {
                _ = try await database.modifyRecords(saving: [link], deleting: [], savePolicy: .allKeys, atomically: false)
                print("   ✅ 샘플 친구 역방향 링크 저장")
            } catch let error as CKError where error.code == .permissionFailure {
                print("   ℹ️ 샘플 링크가 이미 존재 (다른 계정이 생성)")
            }
        }

        // 2. 내 실제 식단 데이터 복사 (최근 3일, 사진 포함)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for dayOffset in 0..<3 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let myMeals = MealRecordStore.shared.getMeals(for: date)

            if myMeals.isEmpty { continue }

            let dateString = dateFormatter.string(from: date)
            var tempFiles: [URL] = []
            var records: [CKRecord] = []

            for (mealType, mealRecord) in myMeals {
                let recordName = "meal_\(sampleUserId)_\(dateString)_\(Self.mealKey(mealType))"
                let record = CKRecord(recordType: Self.mealRecordType,
                                      recordID: CKRecord.ID(recordName: recordName))
                record["ownerId"] = sampleUserId
                record["dateString"] = dateString
                record["mealType"] = Self.mealKey(mealType)
                record["timestamp"] = (mealRecord.capturedAt ?? date).timeIntervalSince1970
                record["memo"] = mealRecord.memo

                if let beforeData = mealRecord.beforeImageData {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(recordName)_before.jpg")
                    try Self.resizeForUpload(beforeData).write(to: url)
                    tempFiles.append(url)
                    record["beforeImage"] = CKAsset(fileURL: url)
                }
                if let afterData = mealRecord.afterImageData {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(recordName)_after.jpg")
                    try Self.resizeForUpload(afterData).write(to: url)
                    tempFiles.append(url)
                    record["afterImage"] = CKAsset(fileURL: url)
                }

                records.append(record)
            }

            do {
                _ = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys, atomically: false)
                print("   ✅ \(dateString) 식단 \(records.count)개 복사")
            } catch let error as CKError where error.code == .permissionFailure {
                print("   ℹ️ \(dateString) - 다른 계정이 만든 샘플이라 갱신 불가, 건너뜀")
            }

            tempFiles.forEach { try? FileManager.default.removeItem(at: $0) }
        }

        print("✅ 샘플 친구 생성 완료: \(sampleName) (\(sampleCode))")
    }

    // MARK: - 닉네임 관리

    /// 내 닉네임을 CloudKit에 저장
    func saveMyNickname(_ nickname: String) async throws {
        guard !myUserId.isEmpty else {
            throw NSError(domain: "FriendManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "사용자 ID 없음"])
        }

        guard !nickname.isEmpty else {
            throw NSError(domain: "FriendManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "닉네임이 비어있습니다"])
        }

        if myUserRecord == nil {
            await bootstrapMyUserRecord()
        }
        guard let record = myUserRecord else {
            throw NSError(domain: "FriendManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "사용자 레코드 없음"])
        }

        record["nickname"] = nickname
        try await saveMyUserRecord()
        print("✅ [FriendManager] 닉네임 저장 완료: \(nickname)")
    }

    /// 특정 사용자의 닉네임 가져오기
    func getUserNickname(_ userId: String) async throws -> String {
        guard !userId.isEmpty else { return "사용자" }

        do {
            let record = try await database.record(for: CKRecord.ID(recordName: Self.userRecordName(for: userId)))
            guard let nickname = record["nickname"] as? String, !nickname.isEmpty else {
                return "사용자"
            }
            return nickname
        } catch {
            print("❌ [FriendManager] 닉네임 조회 실패: \(error.localizedDescription)")
            return "사용자"
        }
    }

    // MARK: - 피드백 관리
    //
    // Feedback 레코드 하나로 저장·조회·푸시를 모두 처리한다.
    // - 받은 피드백: recipientId == 나
    // - 보낸 피드백: authorId == 나
    // - 푸시: 받는 사람이 등록한 CKQuerySubscription이 레코드 생성 시 발동
    // - 읽음 상태: 공개 DB 레코드는 생성자만 수정할 수 있으므로 수신 기기에 로컬 저장

    /// 친구의 식단에 피드백 작성 (푸시는 CloudKit 구독이 자동 배달)
    func addFeedback(to friendId: String, date: Date, mealType: MealType, content: String) async throws {
        guard !myUserId.isEmpty else {
            throw NSError(domain: "FriendManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "사용자 ID 없음"])
        }

        guard !friendId.isEmpty else {
            throw NSError(domain: "FriendManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "친구 ID 없음"])
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "FriendManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "피드백 내용이 비어있습니다"])
        }

        let dateString = dateFormatter.string(from: date)

        let record = CKRecord(recordType: Self.feedbackRecordType)
        record["recipientId"] = friendId
        record["authorId"] = myUserId
        record["authorNickname"] = SettingsManager.shared.nickname
        record["content"] = content
        record["dateString"] = dateString
        record["mealType"] = Self.mealKey(mealType)
        record["createdAtTS"] = Date().timeIntervalSince1970

        do {
            _ = try await database.save(record)
        } catch {
            throw NSError(domain: "FriendManager", code: -9,
                          userInfo: [NSLocalizedDescriptionKey: Self.readableMessage(for: error)])
        }
        print("✅ [FriendManager] 피드백 작성 완료: \(friendId) / \(dateString) / \(mealType.rawValue)")
    }

    /// 내 식단의 피드백 목록 가져오기
    func getMyFeedbacks(date: Date, mealType: MealType) async throws -> [MealFeedback] {
        guard !myUserId.isEmpty else { return [] }

        do {
            let records = try await queryFeedbacks(field: "recipientId", value: myUserId,
                                                   date: date, mealType: mealType)
            let readIds = Self.readFeedbackIds()

            let feedbacks: [MealFeedback] = records.compactMap { record in
                guard let authorId = record["authorId"] as? String,
                      let content = record["content"] as? String,
                      let createdAtTS = record["createdAtTS"] as? TimeInterval else {
                    return nil
                }

                return MealFeedback(
                    id: record.recordID.recordName,
                    authorId: authorId,
                    authorNickname: record["authorNickname"] as? String ?? "친구",
                    content: content,
                    createdAt: Date(timeIntervalSince1970: createdAtTS),
                    isRead: readIds.contains(record.recordID.recordName)
                )
            }

            print("✅ [FriendManager] 피드백 목록 조회 완료: \(feedbacks.count)개")
            return feedbacks.sorted { $0.createdAt > $1.createdAt }
        } catch {
            print("❌ [FriendManager] 피드백 목록 조회 실패: \(error.localizedDescription)")
            return []
        }
    }

    /// 내가 보낸 피드백 목록 가져오기
    func getMySentFeedbacks(date: Date, mealType: MealType) async throws -> [SentFeedback] {
        guard !myUserId.isEmpty else { return [] }

        do {
            let records = try await queryFeedbacks(field: "authorId", value: myUserId,
                                                   date: date, mealType: mealType)

            let sentFeedbacks: [SentFeedback] = records.compactMap { record in
                guard let recipientId = record["recipientId"] as? String,
                      let content = record["content"] as? String,
                      let createdAtTS = record["createdAtTS"] as? TimeInterval else {
                    return nil
                }

                return SentFeedback(
                    id: record.recordID.recordName,
                    recipientId: recipientId,
                    content: content,
                    createdAt: Date(timeIntervalSince1970: createdAtTS)
                )
            }

            print("✅ [FriendManager] 보낸 피드백 조회 완료: \(sentFeedbacks.count)개")
            return sentFeedbacks.sorted { $0.createdAt > $1.createdAt }
        } catch {
            print("❌ [FriendManager] 보낸 피드백 조회 실패: \(error.localizedDescription)")
            return []
        }
    }

    private func queryFeedbacks(field: String, value: String, date: Date, mealType: MealType) async throws -> [CKRecord] {
        let dateString = dateFormatter.string(from: date)
        let predicate = NSPredicate(format: "\(field) == %@ AND dateString == %@ AND mealType == %@",
                                    value, dateString, Self.mealKey(mealType))
        let query = CKQuery(recordType: Self.feedbackRecordType, predicate: predicate)

        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let (results, nextCursor): ([(CKRecord.ID, Result<CKRecord, Error>)], CKQueryOperation.Cursor?)
            if let existing = cursor {
                (results, nextCursor) = try await database.records(continuingMatchFrom: existing)
            } else {
                (results, nextCursor) = try await database.records(matching: query)
            }
            records.append(contentsOf: results.compactMap { try? $0.1.get() })
            cursor = nextCursor
        } while cursor != nil

        return records
    }

    /// 내 식단의 안읽은 피드백 개수 가져오기
    func getUnreadFeedbackCount(date: Date, mealType: MealType) async throws -> Int {
        let feedbacks = try await getMyFeedbacks(date: date, mealType: mealType)
        let unreadCount = feedbacks.filter { !$0.isRead }.count
        print("ℹ️ [FriendManager] 안읽은 피드백: \(unreadCount)개 / 전체: \(feedbacks.count)개")
        return unreadCount
    }

    /// 피드백을 읽음으로 표시 (수신 기기 로컬 저장)
    func markFeedbackAsRead(feedbackId: String, date: Date, mealType: MealType) async throws {
        guard !feedbackId.isEmpty else { return }
        var readIds = Self.readFeedbackIds()
        readIds.insert(feedbackId)
        UserDefaults.standard.set(Array(readIds), forKey: Self.readFeedbackIdsKey)
        print("✅ [FriendManager] 피드백 읽음 처리: \(feedbackId)")
    }

    /// 모든 피드백을 읽음으로 표시
    func markAllFeedbacksAsRead(date: Date, mealType: MealType) async throws {
        let feedbacks = try await getMyFeedbacks(date: date, mealType: mealType)
        let unreadFeedbacks = feedbacks.filter { !$0.isRead }
        guard !unreadFeedbacks.isEmpty else { return }

        var readIds = Self.readFeedbackIds()
        for feedback in unreadFeedbacks {
            readIds.insert(feedback.id)
        }
        UserDefaults.standard.set(Array(readIds), forKey: Self.readFeedbackIdsKey)
        print("✅ [FriendManager] \(unreadFeedbacks.count)개 피드백 읽음 처리 완료")
    }

    private static func readFeedbackIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: readFeedbackIdsKey) ?? [])
    }

    // MARK: - 피드백 푸시 구독

    /// 내 앞으로 온 피드백에 대한 푸시 구독 등록. 같은 계정으로 이미 등록했으면 스킵.
    /// CloudKit 구독 푸시는 서버·APNs 키 없이 Apple이 배달한다.
    private func ensureFeedbackSubscription() {
        guard !myUserId.isEmpty else { return }

        if UserDefaults.standard.string(forKey: Self.feedbackSubscriptionSavedKey) == myUserId {
            return
        }

        let userId = myUserId
        _Concurrency.Task {
            do {
                let predicate = NSPredicate(format: "recipientId == %@", userId)
                let subscription = CKQuerySubscription(
                    recordType: Self.feedbackRecordType,
                    predicate: predicate,
                    subscriptionID: "feedback-sub-\(userId)",
                    options: [.firesOnRecordCreation]
                )

                let info = CKSubscription.NotificationInfo()
                info.title = "새 피드백이 도착했어요 💬"
                info.alertBody = "친구가 내 식단에 메시지를 남겼어요. 확인해 보세요!"
                info.soundName = "default"
                subscription.notificationInfo = info

                _ = try await database.save(subscription)
                UserDefaults.standard.set(userId, forKey: Self.feedbackSubscriptionSavedKey)
                print("📡 [CloudKit] 피드백 푸시 구독 등록 완료")
            } catch let error as CKError where error.code == .serverRejectedRequest {
                // 동일 ID 구독이 이미 서버에 존재 - 등록된 것으로 간주
                UserDefaults.standard.set(userId, forKey: Self.feedbackSubscriptionSavedKey)
                print("📡 [CloudKit] 구독이 이미 존재함 - 스킵")
            } catch {
                print("❌ [CloudKit] 구독 등록 실패: \(error.localizedDescription)")
            }
        }
    }
}
