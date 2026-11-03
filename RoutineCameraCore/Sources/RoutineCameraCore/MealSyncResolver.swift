//
//  MealSyncResolver.swift
//  RoutineCameraCore
//
//  iCloud 동기화에서 같은 끼니가 양쪽에서 바뀌었을 때 무엇을 남길지 정한다.
//  원칙은 "기록을 잃지 않는다" — 애매하면 지우지 않고 남긴다.
//

import Foundation

public enum MealSyncResolver {

    /// 받은 변경을 이 기기에 어떻게 반영할지
    public enum Decision: Equatable, Sendable {
        /// 받은 내용으로 바꾼다
        case applyRemote
        /// 받은 내용이 더 새롭다. 다만 받은 쪽에 없는 사진은 이 기기 것을 채워 다시 올린다
        case applyRemoteFillingPhotos
        /// 이 기기 내용이 더 새롭다. 이 기기에만 없는 사진은 받은 것으로 채워 다시 올린다
        case keepLocalFillingPhotos
        /// 이 기기 내용을 그대로 두고 다시 올린다 (받은 것과 섞지 않는다)
        case keepLocal
        /// 아무것도 바꾸지 않는다
        case ignore
    }

    /// 다른 기기에서 저장한 끼니를 받았을 때
    /// - Parameters:
    ///   - localExists: 이 기기에 그 끼니 기록이 있는지
    ///   - localHasPendingChange: 이 기기에 아직 올리지 못한 변경(삭제 포함)이 있는지
    ///   - localModifiedAt: 이 기기에서 마지막으로 바꾼 시각
    ///   - localWasSynced: 이 기기의 기록이 서버의 그 끼니와 한 번이라도 맞춰진 적 있는지.
    ///     없으면(재설치 뒤 새로 찍은 끼니 등) 같은 식사를 고친 게 아니라 다른 식사다.
    public static func resolveRemoteSave(localExists: Bool,
                                         localHasPendingChange: Bool,
                                         localModifiedAt: Date?,
                                         remoteModifiedAt: Date,
                                         localWasSynced: Bool = true) -> Decision {
        guard localHasPendingChange else { return .applyRemote }
        let remoteIsNewer = remoteModifiedAt >= (localModifiedAt ?? .distantPast)
        if localExists && !localWasSynced {
            // 다른 식사의 사진을 서로 채우면 식전·식후가 다른 끼니로 섞인다 — 더 나중 것 하나를 통째로 남긴다
            return remoteIsNewer ? .applyRemote : .keepLocal
        }
        if localExists {
            return remoteIsNewer ? .applyRemoteFillingPhotos : .keepLocalFillingPhotos
        }
        // 이 기기에서 지웠는데 아직 안 올라간 경우 — 더 나중에 지웠으면 지운 쪽을 따른다
        return remoteIsNewer ? .applyRemote : .ignore
    }

    /// 다른 기기에서 지운 끼니를 받았을 때, 이 기기에서도 지워도 되는지.
    /// 아직 올리지 못한 변경이 있으면 지우지 않는다 (그 변경이 다시 올라가 기록이 살아난다).
    public static func shouldApplyRemoteDelete(localHasPendingChange: Bool) -> Bool {
        !localHasPendingChange
    }
}
