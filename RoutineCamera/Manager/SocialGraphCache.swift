//
//  SocialGraphCache.swift
//  RoutineCamera
//
//  친구 목록 · 받은 요청 · 보낸 요청 · 그룹의 로컬 캐시
//
//  설계 의도
//  - 친구 화면을 열 때마다 iCloud 계정 확인 → 사용자 레코드 → 링크 조회 2번을 다 기다리면
//    그동안 빈 화면이나 "불러오는 중" 만 보인다. 마지막으로 받은 목록을 먼저 보여 주고,
//    새로 받은 것으로 조용히 바꾼다.
//  - 계정(userId)마다 파일을 따로 둔다. 다른 iCloud 계정의 친구가 섞여 보이면 안 된다.
//  - 사진이 없는 작은 JSON 이라 Application Support 에 두고 백업에서는 뺀다.
//

import Foundation
import Combine
import RoutineCameraCore
import os

struct SocialGraphSnapshot: Codable {
    var friends: [Friend]
    var pendingFriends: [PendingFriend]
    var incomingRequests: [FriendRequest]
    var groups: [FriendGroup]
    var savedAt: Date
}

enum SocialGraphCache {
    /// 마지막으로 확인된 내 userId — 실행 직후 계정 확인을 기다리지 않고 캐시를 고르는 데 쓴다
    static let lastUserIdKey = "socialGraphCache.lastUserId"

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SocialGraphCache", isDirectory: true)
    }

    private static func fileURL(userId: String) -> URL {
        // recordName 에 파일 이름으로 못 쓰는 글자가 섞여도 안전하게
        let safe = userId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? userId
        return directory.appendingPathComponent("\(safe).json")
    }

    static func load(userId: String) -> SocialGraphSnapshot? {
        guard !userId.isEmpty,
              let data = try? Data(contentsOf: fileURL(userId: userId)) else { return nil }
        return try? JSONDecoder().decode(SocialGraphSnapshot.self, from: data)
    }

    static func save(_ snapshot: SocialGraphSnapshot, userId: String) {
        guard !userId.isEmpty, let data = try? JSONEncoder().encode(snapshot) else { return }
        let fileManager = FileManager.default
        var dir = directory
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
        }
        try? data.write(to: fileURL(userId: userId), options: .atomic)
        UserDefaults.standard.set(userId, forKey: lastUserIdKey)
    }

    static func remove(userId: String) {
        try? FileManager.default.removeItem(at: fileURL(userId: userId))
        if UserDefaults.standard.string(forKey: lastUserIdKey) == userId {
            UserDefaults.standard.removeObject(forKey: lastUserIdKey)
        }
    }
}

// MARK: - FriendManager 연결

extension FriendManager {
    /// 실행 직후, 계정 확인을 기다리지 않고 마지막 계정의 목록을 먼저 보여 준다.
    /// 계정 확인이 끝나면 recheckAccount 가 다른 계정인지 확인해 바꾼다.
    func restoreSocialGraphFromCache() {
        guard let lastUserId = UserDefaults.standard.string(forKey: SocialGraphCache.lastUserIdKey),
              let snapshot = SocialGraphCache.load(userId: lastUserId) else { return }
        myUserId = lastUserId
        if let cachedCode = UserDefaults.standard.string(forKey: "friendCode_\(lastUserId)") {
            myUserCode = cachedCode
        }
        applySocialSnapshot(snapshot)
        hasCachedSocialGraph = true
        isSignedIn = true
        Log.friends.debug("친구 \(self.friends.count)명 · 요청 \(self.incomingRequests.count)건 · 그룹 \(self.groups.count)개 먼저 표시")
    }

    /// 캐시 내용으로 목록을 바꾼다. nil 이면 비운다 (다른 계정으로 바뀌었는데 캐시가 없을 때).
    func applySocialSnapshot(_ snapshot: SocialGraphSnapshot?) {
        friends = snapshot?.friends ?? []
        pendingFriends = snapshot?.pendingFriends ?? []
        incomingRequests = snapshot?.incomingRequests ?? []
        groups = snapshot?.groups ?? []
    }

    /// 목록이 바뀔 때마다(서버 새로고침 · 요청 보내기 · 삭제 등 어디서 바꾸든) 잠시 모아 한 번 저장한다
    func observeSocialGraphForCache() {
        socialCacheCancellable = Publishers.CombineLatest4($friends, $pendingFriends, $incomingRequests, $groups)
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] friends, pending, incoming, groups in
                guard let self, !self.myUserId.isEmpty else { return }
                SocialGraphCache.save(SocialGraphSnapshot(friends: friends,
                                                          pendingFriends: pending,
                                                          incomingRequests: incoming,
                                                          groups: groups,
                                                          savedAt: Date()),
                                      userId: self.myUserId)
            }
    }

    /// 화면에 먼저 보여 줄 친구 기록. 만료된 캐시도 돌려준다 — 새로 받아 오는 동안 빈칸 대신 보여 주는 용도.
    func cachedMealsForDisplay(friendId: String, date: Date, album: AlbumType = .diet) -> [MealType: MealRecord]? {
        let cacheDateKey = DayKey.string(from: date) + album.recordSuffix
        if let cached = memoryCache.object(forKey: "\(friendId)_\(cacheDateKey)" as NSString) {
            return cached.meals
        }
        return FriendMealCache.shared.load(friendId: friendId, dateString: cacheDateKey, date: date, allowStale: true)
    }
}
