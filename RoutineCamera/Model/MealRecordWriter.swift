//
//  MealRecordWriter.swift
//  RoutineCamera
//
//  기록을 디스크(사진 파일 + UserDefaults 의 가벼운 JSON)에 쓰는 일을 메인 밖에서 한다.
//  예전에는 기록을 하나 고칠 때마다 메인에서 JSON 을 만들고 사진 파일을 확인해, 그동안 화면이 멈췄다.
//  이제 메인은 고친 기록 목록을 넘기고 바로 돌아간다.
//  쓰기는 한 줄로 세워 순서가 뒤바뀌지 않고, 밀린 사이 여러 번 고쳤으면 마지막 것만 쓴다.
//

import Foundation
import RoutineCameraCore
import os

nonisolated final class MealRecordWriter: @unchecked Sendable {
    /// 한 앨범을 쓰는 데 필요한 값. 메인의 상태를 붙들지 않는다.
    struct Snapshot: Sendable {
        let records: [MealRecord]
        let key: String
        let store: MealImageFileStore?
        /// 읽지 못한 사진: 끼니 칸 이름 → 실제 파일 이름. 비어 보여도 지운 사진이 아니라 참조와 파일을 지킨다.
        let unreadable: [String: String]
    }

    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.ysoup.RoutineCamera.record-writer", qos: .userInitiated)
    private let lock = NSLock()
    /// 아직 쓰지 않은 앨범별 마지막 기록 (저장 키 → 스냅샷)
    private var pending: [String: Snapshot] = [:]

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// 쓰기를 줄 세운다. 다 쓰면 기록이 가리키는 사진 파일 이름들을 메인에서 `completion` 으로 알려 준다.
    /// 더 새 스냅샷에 밀려 건너뛴 쓰기는 `completion` 을 부르지 않는다.
    func enqueue(_ snapshot: Snapshot, completion: @escaping @MainActor @Sendable (Set<String>) -> Void) {
        lock.withLock { pending[snapshot.key] = snapshot }
        queue.async { [self] in
            guard let latest = lock.withLock({ pending.removeValue(forKey: snapshot.key) }),
                  let referenced = Self.write(latest, to: defaults) else { return }
            Task { @MainActor in completion(referenced) }
        }
    }

    /// 밀린 쓰기가 끝날 때까지 기다린다 — 앱이 백그라운드로 가거나 종료될 때 기록을 잃지 않게.
    func waitUntilIdle() {
        queue.sync {}
    }

    // MARK: - 쓰기

    /// 순서: 사진 파일 쓰기 → JSON 교체 → 더는 가리키지 않는 파일 정리 (형식과 규칙은 RoutineCameraCore 의 MealRecordArchive).
    /// 어느 단계에서 앱이 종료돼도 JSON 이 가리키는 사진은 디스크에 남아 있다.
    /// - Returns: 기록이 가리키는 사진 파일 이름들. JSON 을 만들지 못하면 nil (아무것도 바꾸지 않는다).
    private static func write(_ snapshot: Snapshot, to defaults: UserDefaults) -> Set<String>? {
        let encoded: MealRecordArchive.Encoded
        do {
            encoded = try MealRecordArchive.encode(records: snapshot.records, store: snapshot.store, unreadable: snapshot.unreadable)
        } catch {
            Log.store.fault("기록을 JSON 으로 만들지 못해 저장하지 않음: \(String(describing: error))")
            return nil
        }
        for (slot, reason) in encoded.keptInline {
            Log.store.error("사진 파일 저장 실패, 기록 안에 그대로 둠 (\(slot, privacy: .public)): \(reason)")
        }
        defaults.set(encoded.data, forKey: snapshot.key)

        if let store = snapshot.store {
            let removed = store.removeFiles(keeping: encoded.referenced)
            if removed > 0 { Log.store.info("기록에서 빠진 사진 파일 \(removed)개 정리") }
        }
        return encoded.referenced
    }
}
