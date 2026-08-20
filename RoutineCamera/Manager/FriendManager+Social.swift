//
//  FriendManager+Social.swift
//  RoutineCamera
//
//  친구 요청 → 수락(양방향) + 그룹
//
//  공개 DB는 "누구나 읽기, 생성자만 수정"이라 남의 레코드에 상태를 쓸 수 없다.
//  그래서 관계는 각자 자기 레코드만 만들고, 양쪽 레코드의 존재로 판정한다.
//  (Feedback이 "보내는 사람이 만들고 받는 사람이 쿼리"하는 것과 같은 패턴)
//
//  - FriendLink  : link_<내ID>_<상대ID> — 내가 만든 내 쪽 링크. 양쪽에 링크가 있으면 친구
//  - RCGroup     : group_<uuid> — 방장이 생성. 초대 코드로 검색
//  - GroupMember : member_<그룹ID>_<내ID> — 가입은 각자 자기 멤버 레코드를 만드는 셀프 등록
//
//  ⚠️ 공개 DB에는 읽기 제한이 없다. 수락·가입은 "앱 화면에 무엇을 보여줄지"를 정하는 UX 장치이고,
//     상대 userId를 아는 사람이 레코드를 읽는 것 자체를 막지는 못한다.
//

import Foundation
import CloudKit

// MARK: - 모델

enum FriendLinkState: String {
    case requested  // 요청 보냄
    case accepted   // 수락함
    case rejected   // 거절함
}

/// 내가 받은 친구 요청
struct FriendRequest: Identifiable, Equatable {
    let id: String      // 보낸 사람 userId
    let code: String
    let name: String
    let createdAt: Date
}

/// 내가 보낸 요청 (상대 수락 대기 중이거나 거절당함)
struct PendingFriend: Identifiable, Equatable {
    let id: String      // 상대 userId
    let code: String
    let name: String
    let sentAt: Date
    let isRejected: Bool
}

struct FriendGroup: Identifiable, Equatable {
    let id: String      // recordName: group_<uuid>
    let name: String
    let ownerId: String
    let inviteCode: String
    let createdAt: Date
    var memberCount: Int = 0
}

struct GroupMemberInfo: Identifiable, Equatable {
    let id: String      // userId
    let nickname: String
    let joinedAt: Date
}

/// FriendLink 레코드 한 건의 내부 표현
private struct FriendLinkRecord {
    let ownerId: String
    let otherId: String
    let ownerCode: String
    let otherCode: String
    let ownerNickname: String
    let otherNickname: String
    let state: FriendLinkState
    let isLegacy: Bool      // friendsJSON에서 이관된 관계 (상대가 아직 구버전일 수 있음)
    let createdAt: Date
}

@MainActor
extension FriendManager {

    // MARK: - 레코드 타입

    static let friendLinkRecordType = "FriendLink"
    static let groupRecordType = "RCGroup"
    static let groupMemberRecordType = "GroupMember"
    static let friendLinkSubscriptionKey = "friendLinkSubscriptionUserId"

    static func friendLinkName(owner: String, other: String) -> String {
        "link_\(owner)_\(other)"
    }

    static func groupMemberName(groupId: String, userId: String) -> String {
        "member_\(groupId)_\(userId)"
    }

    // MARK: - 친구 요청 / 수락

    /// 친구 요청 보내기. 상대가 수락해야 서로의 기록이 보인다.
    /// 상대가 이미 나에게 요청을 보내둔 상태라면 곧바로 수락 처리된다.
    func sendFriendRequest(code rawCode: String) async throws {
        let code = rawCode.uppercased()

        guard code.count == 6 else {
            throw NSError(domain: "FriendManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "6자리 코드를 입력해주세요."])
        }
        guard code != myUserCode else {
            throw NSError(domain: "FriendManager", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "자신의 코드는 추가할 수 없습니다."])
        }
        guard !myUserId.isEmpty else {
            throw NSError(domain: "FriendManager", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "iCloud 계정을 확인할 수 없습니다."])
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let record = try await findUserRecord(byCode: code) else {
                throw NSError(domain: "FriendManager", code: -3,
                              userInfo: [NSLocalizedDescriptionKey: "존재하지 않는 코드입니다. 친구 앱에 지금 표시된 코드가 맞는지, 서로 같은 경로(TestFlight/앱스토어)로 설치한 앱인지 확인해주세요."])
            }

            let friendId = String(record.recordID.recordName.dropFirst("user_".count))
            guard friendId != myUserId else {
                throw NSError(domain: "FriendManager", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: "자신의 코드는 추가할 수 없습니다."])
            }
            if friends.contains(where: { $0.id == friendId }) {
                throw NSError(domain: "FriendManager", code: -4,
                              userInfo: [NSLocalizedDescriptionKey: "이미 추가된 친구입니다."])
            }
            if pendingFriends.contains(where: { $0.id == friendId && !$0.isRejected }) {
                throw NSError(domain: "FriendManager", code: -6,
                              userInfo: [NSLocalizedDescriptionKey: "이미 요청을 보냈어요. 상대의 수락을 기다리는 중입니다."])
            }

            let nickname = (record["nickname"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "친구"
            // 상대가 먼저 보낸 요청이 있으면 바로 성사
            let alreadyRequestedByThem = incomingRequests.contains { $0.id == friendId }
            let state: FriendLinkState = alreadyRequestedByThem ? .accepted : .requested

            try await saveMyLink(otherId: friendId, otherCode: code, otherNickname: nickname, state: state)
            await refreshSocialGraph()

            print("✅ 친구 요청 \(alreadyRequestedByThem ? "수락(맞요청)" : "전송"): \(nickname) (\(code))")
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// 받은 요청 수락 → 내 쪽 링크 생성으로 양방향 성립
    func acceptFriendRequest(_ request: FriendRequest) async throws {
        isLoading = true
        defer { isLoading = false }

        try await saveMyLink(otherId: request.id, otherCode: request.code,
                             otherNickname: request.name, state: .accepted)
        await refreshSocialGraph()
        print("✅ 친구 요청 수락: \(request.name)")
    }

    /// 받은 요청 거절 (거절 링크를 남겨 같은 요청이 다시 뜨지 않게 한다)
    func rejectFriendRequest(_ request: FriendRequest) async throws {
        isLoading = true
        defer { isLoading = false }

        try await saveMyLink(otherId: request.id, otherCode: request.code,
                             otherNickname: request.name, state: .rejected)
        await refreshSocialGraph()
        print("✅ 친구 요청 거절: \(request.name)")
    }

    /// 내가 보낸 요청 취소 / 거절당한 요청 정리
    func cancelFriendRequest(_ pending: PendingFriend) async throws {
        isLoading = true
        defer { isLoading = false }

        try await deleteMyLink(otherId: pending.id)
        await refreshSocialGraph()
        print("✅ 보낸 요청 취소: \(pending.name)")
    }

    /// 내 쪽 링크 저장 (내가 만든 레코드이므로 덮어쓰기 가능 — 거절 후 재요청도 같은 레코드를 갱신)
    private func saveMyLink(otherId: String, otherCode: String, otherNickname: String,
                            state: FriendLinkState, isLegacy: Bool = false) async throws {
        guard !myUserId.isEmpty else {
            throw NSError(domain: "FriendManager", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "iCloud 계정을 확인할 수 없습니다."])
        }

        let recordID = CKRecord.ID(recordName: Self.friendLinkName(owner: myUserId, other: otherId))
        let record = CKRecord(recordType: Self.friendLinkRecordType, recordID: recordID)
        record["ownerId"] = myUserId
        record["otherId"] = otherId
        record["ownerCode"] = myUserCode
        record["otherCode"] = otherCode
        record["ownerNickname"] = SettingsManager.shared.nickname
        record["otherNickname"] = otherNickname
        record["state"] = state.rawValue
        record["isLegacy"] = isLegacy ? 1 : 0
        record["createdAtTS"] = Date().timeIntervalSince1970

        let (saveResults, _) = try await database.modifyRecords(
            saving: [record], deleting: [], savePolicy: .allKeys, atomically: false
        )
        for (_, result) in saveResults {
            _ = try result.get()
        }
    }

    func deleteMyLink(otherId: String) async throws {
        guard !myUserId.isEmpty else { return }
        let recordID = CKRecord.ID(recordName: Self.friendLinkName(owner: myUserId, other: otherId))
        _ = try? await database.deleteRecord(withID: recordID)
    }

    /// 양방향 링크를 모두 읽어 친구·받은 요청·보낸 요청을 갱신.
    /// 조회에 실패하면 기존 목록(구버전 friendsJSON 포함)을 그대로 유지한다.
    func refreshSocialGraph() async {
        guard !myUserId.isEmpty else { return }

        do {
            let outgoing = try await queryLinks(field: "ownerId", value: myUserId)
            let incoming = try await queryLinks(field: "otherId", value: myUserId)

            var mine: [String: FriendLinkRecord] = [:]
            for link in outgoing { mine[link.otherId] = link }
            var theirs: [String: FriendLinkRecord] = [:]
            for link in incoming { theirs[link.ownerId] = link }

            var accepted: [Friend] = []
            var pending: [PendingFriend] = []

            for (otherId, link) in mine where link.state != .rejected {
                let reverse = theirs[otherId]
                let reverseAlive = reverse != nil && reverse?.state != .rejected
                // 구버전에서 이관된 관계는 상대가 아직 업데이트하지 않았을 수 있으므로 그대로 인정
                let isMutual = reverseAlive || link.isLegacy
                let displayName = reverse?.ownerNickname.isEmpty == false
                    ? reverse!.ownerNickname
                    : (link.otherNickname.isEmpty ? "친구" : link.otherNickname)

                if isMutual {
                    accepted.append(Friend(id: otherId, code: link.otherCode,
                                           name: displayName, addedDate: link.createdAt))
                } else {
                    pending.append(PendingFriend(id: otherId, code: link.otherCode,
                                                 name: displayName, sentAt: link.createdAt,
                                                 isRejected: reverse?.state == .rejected))
                }
            }

            var requests: [FriendRequest] = []
            for (ownerId, link) in theirs where link.state != .rejected {
                guard mine[ownerId] == nil else { continue } // 내가 이미 응답한 요청
                requests.append(FriendRequest(id: ownerId,
                                              code: link.ownerCode,
                                              name: link.ownerNickname.isEmpty ? "친구" : link.ownerNickname,
                                              createdAt: link.createdAt))
            }

            friends = accepted.sorted { $0.addedDate > $1.addedDate }
            pendingFriends = pending.sorted { $0.sentAt > $1.sentAt }
            incomingRequests = requests.sorted { $0.createdAt > $1.createdAt }

            print("✅ [CloudKit] 친구 \(friends.count)명 / 받은 요청 \(incomingRequests.count)건 / 보낸 요청 \(pendingFriends.count)건")
        } catch {
            print("❌ [CloudKit] 친구 관계 조회 실패(기존 목록 유지): \(error.localizedDescription)")
        }
    }

    private func queryLinks(field: String, value: String) async throws -> [FriendLinkRecord] {
        let query = CKQuery(recordType: Self.friendLinkRecordType,
                            predicate: NSPredicate(format: "\(field) == %@", value))
        return try await fetchAll(query: query).compactMap { Self.parseLink($0) }
    }

    private static func parseLink(_ record: CKRecord) -> FriendLinkRecord? {
        guard let ownerId = record["ownerId"] as? String,
              let otherId = record["otherId"] as? String else { return nil }

        let stateRaw = record["state"] as? String ?? FriendLinkState.requested.rawValue
        return FriendLinkRecord(
            ownerId: ownerId,
            otherId: otherId,
            ownerCode: record["ownerCode"] as? String ?? "",
            otherCode: record["otherCode"] as? String ?? "",
            ownerNickname: record["ownerNickname"] as? String ?? "",
            otherNickname: record["otherNickname"] as? String ?? "",
            state: FriendLinkState(rawValue: stateRaw) ?? .requested,
            isLegacy: (record["isLegacy"] as? NSNumber)?.intValue == 1,
            createdAt: Date(timeIntervalSince1970: record["createdAtTS"] as? TimeInterval ?? 0)
        )
    }

    /// 구버전 friendsJSON 친구를 FriendLink로 이관 (계정당 1회).
    /// 이미 서로 추가한 사이라면 양쪽이 업데이트하는 순간 자연스럽게 상호 링크가 된다.
    func migrateLegacyFriendsIfNeeded() async {
        guard !myUserId.isEmpty else { return }

        let key = "friendLinkMigrated_\(myUserId)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard !friends.isEmpty else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        for friend in friends {
            do {
                try await saveMyLink(otherId: friend.id, otherCode: friend.code,
                                     otherNickname: friend.name, state: .accepted, isLegacy: true)
            } catch {
                // 다음 실행에서 재시도 (플래그를 세우지 않음)
                print("❌ [CloudKit] 친구 이관 실패(\(friend.code)): \(error.localizedDescription)")
                return
            }
        }

        UserDefaults.standard.set(true, forKey: key)
        print("✅ [CloudKit] 기존 친구 \(friends.count)명 → FriendLink 이관 완료")
    }

    /// 나에게 온 친구 요청·수락 푸시 구독
    func ensureFriendLinkSubscription() {
        guard !myUserId.isEmpty else { return }
        if UserDefaults.standard.string(forKey: Self.friendLinkSubscriptionKey) == myUserId { return }

        let userId = myUserId
        _Concurrency.Task {
            do {
                let subscription = CKQuerySubscription(
                    recordType: Self.friendLinkRecordType,
                    predicate: NSPredicate(format: "otherId == %@", userId),
                    subscriptionID: "friendlink-sub-\(userId)",
                    options: [.firesOnRecordCreation]
                )

                let info = CKSubscription.NotificationInfo()
                info.title = "친구 소식이 있어요 👋"
                info.alertBody = "친구 요청이 오거나 보낸 요청이 수락됐어요. 친구 화면에서 확인해 보세요!"
                info.soundName = "default"
                subscription.notificationInfo = info

                _ = try await database.save(subscription)
                UserDefaults.standard.set(userId, forKey: Self.friendLinkSubscriptionKey)
                print("📡 [CloudKit] 친구 요청 푸시 구독 등록 완료")
            } catch let error as CKError where error.code == .serverRejectedRequest {
                UserDefaults.standard.set(userId, forKey: Self.friendLinkSubscriptionKey)
                print("📡 [CloudKit] 친구 요청 구독이 이미 존재함 - 스킵")
            } catch {
                print("❌ [CloudKit] 친구 요청 구독 등록 실패: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 그룹

    /// 내가 멤버로 등록된 그룹 목록
    func loadMyGroups() async {
        guard !myUserId.isEmpty else { return }

        do {
            let memberRecords = try await fetchAll(
                query: CKQuery(recordType: Self.groupMemberRecordType,
                               predicate: NSPredicate(format: "userId == %@", myUserId))
            )
            let groupIds = memberRecords.compactMap { $0["groupId"] as? String }
            guard !groupIds.isEmpty else {
                groups = []
                return
            }

            let results = try await database.records(for: groupIds.map { CKRecord.ID(recordName: $0) })

            var loaded: [FriendGroup] = []
            for groupId in groupIds {
                switch results[CKRecord.ID(recordName: groupId)] {
                case .success(let record):
                    if let group = Self.parseGroup(record) { loaded.append(group) }
                default:
                    // 방장이 없앤 그룹 — 남아 있는 내 멤버 레코드를 정리
                    _ = try? await database.deleteRecord(
                        withID: CKRecord.ID(recordName: Self.groupMemberName(groupId: groupId, userId: myUserId))
                    )
                }
            }

            groups = loaded.sorted { $0.createdAt > $1.createdAt }
            print("✅ [CloudKit] 내 그룹 \(groups.count)개")
        } catch {
            print("❌ [CloudKit] 그룹 조회 실패: \(error.localizedDescription)")
        }
    }

    /// 그룹 만들기 (만든 사람이 방장, 초대 코드 자동 발급)
    @discardableResult
    func createGroup(name: String) async throws -> FriendGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "FriendManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "그룹 이름을 입력해주세요."])
        }
        guard !myUserId.isEmpty else {
            throw NSError(domain: "FriendManager", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "iCloud 계정을 확인할 수 없습니다."])
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let inviteCode = try await makeUniqueInviteCode()
            let groupId = "group_\(UUID().uuidString)"
            let now = Date()

            let record = CKRecord(recordType: Self.groupRecordType,
                                  recordID: CKRecord.ID(recordName: groupId))
            record["name"] = trimmed
            record["ownerId"] = myUserId
            record["inviteCode"] = inviteCode
            record["createdAtTS"] = now.timeIntervalSince1970
            _ = try await database.save(record)

            try await saveMyMembership(groupId: groupId)
            await loadMyGroups()

            print("✅ 그룹 생성: \(trimmed) (\(inviteCode))")
            return FriendGroup(id: groupId, name: trimmed, ownerId: myUserId,
                               inviteCode: inviteCode, createdAt: now, memberCount: 1)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// 초대 코드로 그룹 참여 (내 멤버 레코드만 만드는 셀프 등록)
    @discardableResult
    func joinGroup(inviteCode rawCode: String) async throws -> FriendGroup {
        let code = rawCode.uppercased()

        guard code.count == 6 else {
            throw NSError(domain: "FriendManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "6자리 그룹 코드를 입력해주세요."])
        }
        guard !myUserId.isEmpty else {
            throw NSError(domain: "FriendManager", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "iCloud 계정을 확인할 수 없습니다."])
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let record = try await findGroupRecord(byInviteCode: code),
                  let group = Self.parseGroup(record) else {
                throw NSError(domain: "FriendManager", code: -3,
                              userInfo: [NSLocalizedDescriptionKey: "존재하지 않는 그룹 코드입니다. 코드가 맞는지, 서로 같은 경로(TestFlight/앱스토어)로 설치한 앱인지 확인해주세요."])
            }
            guard !groups.contains(where: { $0.id == group.id }) else {
                throw NSError(domain: "FriendManager", code: -4,
                              userInfo: [NSLocalizedDescriptionKey: "이미 참여 중인 그룹입니다."])
            }

            try await saveMyMembership(groupId: group.id)
            await loadMyGroups()

            print("✅ 그룹 참여: \(group.name)")
            return group
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// 그룹 나가기. 방장이 나가면 그룹 자체를 없앤다
    /// (남의 멤버 레코드는 지울 수 없지만, 그룹이 사라지면 각자 화면에서 정리된다)
    func leaveGroup(_ group: FriendGroup) async throws {
        guard !myUserId.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        _ = try? await database.deleteRecord(
            withID: CKRecord.ID(recordName: Self.groupMemberName(groupId: group.id, userId: myUserId))
        )

        if group.ownerId == myUserId {
            _ = try? await database.deleteRecord(withID: CKRecord.ID(recordName: group.id))
            print("🗑️ 방장이 나가 그룹 삭제: \(group.name)")
        }

        await loadMyGroups()
    }

    /// 그룹 멤버 목록 (가입 순)
    func loadGroupMembers(groupId: String) async throws -> [GroupMemberInfo] {
        let records = try await fetchAll(
            query: CKQuery(recordType: Self.groupMemberRecordType,
                           predicate: NSPredicate(format: "groupId == %@", groupId))
        )

        return records.compactMap { record -> GroupMemberInfo? in
            guard let userId = record["userId"] as? String else { return nil }
            return GroupMemberInfo(
                id: userId,
                nickname: (record["nickname"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "멤버",
                joinedAt: Date(timeIntervalSince1970: record["joinedAtTS"] as? TimeInterval ?? 0)
            )
        }.sorted { $0.joinedAt < $1.joinedAt }
    }

    /// 그룹 멤버 전원의 특정 날짜 식단을 한 번에 조회.
    /// (사람 × 끼니) 레코드 ID를 묶어서 요청하므로 쿼리 인덱스가 필요 없고, 사람 수만큼 왕복하지도 않는다.
    func loadGroupMeals(userIds: [String], date: Date) async throws -> [String: [MealType: MealRecord]] {
        let dateString = dateFormatter.string(from: date)
        var out: [String: [MealType: MealRecord]] = [:]
        var missing: [String] = []

        // 1. 기존 캐시(친구 화면과 공유) 먼저
        for userId in userIds {
            let cacheKey = "\(userId)_\(dateString)" as NSString
            if let cached = memoryCache.object(forKey: cacheKey) {
                out[userId] = cached.meals
            } else if let disk = loadFromDiskCache(friendId: userId, dateString: dateString) {
                memoryCache.setObject(CachedMealData(meals: disk), forKey: cacheKey)
                out[userId] = disk
            } else {
                missing.append(userId)
            }
        }
        guard !missing.isEmpty else { return out }

        // 2. 남은 사람들의 레코드 ID를 100개씩 묶어 조회
        var recordIDs: [CKRecord.ID] = []
        for userId in missing {
            for mealType in MealType.allCases {
                recordIDs.append(CKRecord.ID(recordName: "meal_\(userId)_\(dateString)_\(Self.mealKey(mealType))"))
            }
        }

        let fetched = try await fetchRecordsInChunks(recordIDs)

        // 3. 사람별로 정리 + 캐시 저장
        for userId in missing {
            var meals: [MealType: MealRecord] = [:]
            for mealType in MealType.allCases {
                let id = CKRecord.ID(recordName: "meal_\(userId)_\(dateString)_\(Self.mealKey(mealType))")
                guard case .success(let record)? = fetched[id] else { continue }
                meals[mealType] = Self.mealRecord(from: record, date: date, mealType: mealType)
            }
            out[userId] = meals

            if !meals.isEmpty {
                memoryCache.setObject(CachedMealData(meals: meals), forKey: "\(userId)_\(dateString)" as NSString)
                saveToDiskCache(friendId: userId, dateString: dateString, meals: meals)
            }
        }

        print("🌐 [CloudKit] 그룹 식단 조회: \(dateString) — 캐시 \(userIds.count - missing.count)명 / 신규 \(missing.count)명")
        return out
    }

    /// 한 친구의 여러 날짜 식단을 한 번에 조회.
    /// 기록이 없는 날도 빈 값으로 돌려주므로, 화면에서 "없는 날"을 숨기면서도 같은 날을 다시 요청하지 않는다.
    func loadFriendMealsBatch(friendId: String, dates: [Date]) async throws -> [Date: [MealType: MealRecord]] {
        var out: [Date: [MealType: MealRecord]] = [:]
        var missing: [Date] = []

        for date in dates {
            let dateString = dateFormatter.string(from: date)
            let cacheKey = "\(friendId)_\(dateString)" as NSString
            if let cached = memoryCache.object(forKey: cacheKey) {
                out[date] = cached.meals
            } else if let disk = loadFromDiskCache(friendId: friendId, dateString: dateString) {
                memoryCache.setObject(CachedMealData(meals: disk), forKey: cacheKey)
                out[date] = disk
            } else {
                missing.append(date)
            }
        }
        guard !missing.isEmpty else { return out }

        var recordIDs: [CKRecord.ID] = []
        for date in missing {
            let dateString = dateFormatter.string(from: date)
            for mealType in MealType.allCases {
                recordIDs.append(CKRecord.ID(recordName: "meal_\(friendId)_\(dateString)_\(Self.mealKey(mealType))"))
            }
        }

        let fetched = try await fetchRecordsInChunks(recordIDs)

        for date in missing {
            let dateString = dateFormatter.string(from: date)
            var meals: [MealType: MealRecord] = [:]
            for mealType in MealType.allCases {
                let id = CKRecord.ID(recordName: "meal_\(friendId)_\(dateString)_\(Self.mealKey(mealType))")
                guard case .success(let record)? = fetched[id] else { continue }
                meals[mealType] = Self.mealRecord(from: record, date: date, mealType: mealType)
            }
            out[date] = meals

            if !meals.isEmpty {
                memoryCache.setObject(CachedMealData(meals: meals), forKey: "\(friendId)_\(dateString)" as NSString)
                saveToDiskCache(friendId: friendId, dateString: dateString, meals: meals)
            }
        }

        print("🌐 [CloudKit] 친구 식단 배치 조회: 캐시 \(dates.count - missing.count)일 / 신규 \(missing.count)일")
        return out
    }

    /// 레코드 ID를 100개씩 끊어서 조회 (CloudKit 요청 크기 제한 대응)
    private func fetchRecordsInChunks(_ recordIDs: [CKRecord.ID]) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        var fetched: [CKRecord.ID: Result<CKRecord, Error>] = [:]
        for start in stride(from: 0, to: recordIDs.count, by: 100) {
            let chunk = Array(recordIDs[start..<min(start + 100, recordIDs.count)])
            let results = try await database.records(for: chunk)
            fetched.merge(results) { current, _ in current }
        }
        return fetched
    }

    private func saveMyMembership(groupId: String) async throws {
        let recordID = CKRecord.ID(recordName: Self.groupMemberName(groupId: groupId, userId: myUserId))
        let record = CKRecord(recordType: Self.groupMemberRecordType, recordID: recordID)
        record["groupId"] = groupId
        record["userId"] = myUserId
        record["nickname"] = SettingsManager.shared.nickname
        record["joinedAtTS"] = Date().timeIntervalSince1970

        let (saveResults, _) = try await database.modifyRecords(
            saving: [record], deleting: [], savePolicy: .allKeys, atomically: false
        )
        for (_, result) in saveResults {
            _ = try result.get()
        }
    }

    private func findGroupRecord(byInviteCode code: String) async throws -> CKRecord? {
        let query = CKQuery(recordType: Self.groupRecordType,
                            predicate: NSPredicate(format: "inviteCode == %@", code))
        do {
            let (results, _) = try await database.records(matching: query, resultsLimit: 1)
            return try results.first?.1.get()
        } catch let error as CKError {
            throw Self.lookupError(from: error)
        }
    }

    /// 이미 쓰이는 초대 코드를 피해서 발급 (최대 3회 시도)
    private func makeUniqueInviteCode() async throws -> String {
        for _ in 0..<3 {
            let candidate = generateRandomCode()
            do {
                if try await findGroupRecord(byInviteCode: candidate) == nil { return candidate }
            } catch {
                // 첫 그룹이라 스키마가 아직 없는 경우 등 — 중복 검사 없이 진행
                return candidate
            }
        }
        return generateRandomCode()
    }

    private static func parseGroup(_ record: CKRecord) -> FriendGroup? {
        guard let name = record["name"] as? String,
              let ownerId = record["ownerId"] as? String,
              let inviteCode = record["inviteCode"] as? String else { return nil }

        return FriendGroup(
            id: record.recordID.recordName,
            name: name,
            ownerId: ownerId,
            inviteCode: inviteCode,
            createdAt: Date(timeIntervalSince1970: record["createdAtTS"] as? TimeInterval ?? 0)
        )
    }

    // MARK: - 공용 헬퍼

    /// 커서를 따라 전체 결과를 모아 반환
    func fetchAll(query: CKQuery) async throws -> [CKRecord] {
        var out: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let (results, nextCursor): ([(CKRecord.ID, Result<CKRecord, Error>)], CKQueryOperation.Cursor?)
            if let existing = cursor {
                (results, nextCursor) = try await database.records(continuingMatchFrom: existing)
            } else {
                (results, nextCursor) = try await database.records(matching: query)
            }
            out.append(contentsOf: results.compactMap { try? $0.1.get() })
            cursor = nextCursor
        } while cursor != nil

        return out
    }

    /// Meal 레코드 → MealRecord (친구 화면·그룹 화면 공용)
    static func mealRecord(from record: CKRecord, date: Date, mealType: MealType) -> MealRecord {
        let beforeData = (record["beforeImage"] as? CKAsset).flatMap { asset in
            asset.fileURL.flatMap { try? Data(contentsOf: $0) }
        }
        let afterData = (record["afterImage"] as? CKAsset).flatMap { asset in
            asset.fileURL.flatMap { try? Data(contentsOf: $0) }
        }

        return MealRecord(
            date: date,
            mealType: mealType,
            beforeImageData: beforeData,
            afterImageData: afterData,
            memo: record["memo"] as? String,
            recordedWithoutPhoto: false,
            hidePhotoCountBadge: false
        )
    }
}
