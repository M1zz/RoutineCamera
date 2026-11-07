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

    /// 끼니 칸 하나의 기본 사진 파일 이름 (예: 2026-09-10_lunch_before.jpg)
    static func slotName(for record: MealRecord, kind: String) -> String {
        MealImageFileStore.fileName(day: DayKey.string(from: record.date), slot: "\(record.mealType)", kind: kind)
    }

    // MARK: - 쓰기

    /// 순서: 사진 파일 쓰기 → JSON 교체 → 더는 가리키지 않는 파일 정리.
    /// 어느 단계에서 앱이 종료돼도 JSON 이 가리키는 사진은 디스크에 남아 있다.
    /// - Returns: 기록이 가리키는 사진 파일 이름들. JSON 을 만들지 못하면 nil (아무것도 바꾸지 않는다).
    private static func write(_ snapshot: Snapshot, to defaults: UserDefaults) -> Set<String>? {
        var referenced = Set<String>()
        var entries: [StoredMealRecord] = []
        entries.reserveCapacity(snapshot.records.count)

        for record in snapshot.records {
            let beforeFile = storeImage(record.beforeImageData, kind: "before", of: record, in: snapshot, referenced: &referenced)
            let afterFile = storeImage(record.afterImageData, kind: "after", of: record, in: snapshot, referenced: &referenced)
            // 파일로 옮긴 사진만 JSON 에서 뺀다. 못 옮긴 사진은 바이트 그대로 남는다.
            let slim = record.replacingImages(before: beforeFile == nil ? record.beforeImageData : nil,
                                              after: afterFile == nil ? record.afterImageData : nil)
            entries.append(StoredMealRecord(record: slim, beforeImageFile: beforeFile, afterImageFile: afterFile))
        }

        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(entries)
        } catch {
            Log.store.fault("기록을 JSON 으로 만들지 못해 저장하지 않음: \(String(describing: error))")
            return nil
        }
        defaults.set(encoded, forKey: snapshot.key)

        if let store = snapshot.store {
            let removed = store.removeFiles(keeping: referenced)
            if removed > 0 { Log.store.info("기록에서 빠진 사진 파일 \(removed)개 정리") }
        }
        return referenced
    }

    /// 사진 한 장을 파일로 쓰고 JSON 에 담을 파일 이름을 돌려준다. 파일로 못 쓰면 nil (바이트로 남긴다).
    private static func storeImage(_ data: Data?, kind: String, of record: MealRecord, in snapshot: Snapshot,
                                   referenced: inout Set<String>) -> String? {
        guard let store = snapshot.store else { return nil }
        let slot = slotName(for: record, kind: kind)

        guard let data else {
            // 읽지 못했던 사진이면 참조를 그대로 두고 다음 실행에 다시 읽는다
            guard let unreadable = snapshot.unreadable[slot] else { return nil }
            referenced.insert(unreadable)
            return unreadable
        }

        // 같은 날 같은 끼니 기록이 둘이면 서로 덮어쓰지 않게 기록 id 를 붙인다
        var name = slot
        if referenced.contains(name) {
            name = MealImageFileStore.fileName(day: DayKey.string(from: record.date),
                                               slot: "\(record.mealType)-\(record.id.uuidString)",
                                               kind: kind)
        }

        do {
            try store.write(data, named: name)
            referenced.insert(name)
            return name
        } catch {
            Log.store.error("사진 파일 저장 실패, 기록 안에 그대로 둠: \(String(describing: error))")
            return nil
        }
    }
}

/// UserDefaults 에 저장하는 기록 한 건. 사진 바이트 대신 파일 이름을 담는다.
/// 예전 형식(사진 바이트가 든 기록)도 그대로 읽히고, 파일로 못 옮긴 사진은 바이트로 남겨 잃지 않는다.
/// 위젯은 같은 키에서 날짜·끼니·촬영 시각만 읽으므로 형식이 바뀌어도 영향이 없다.
nonisolated struct StoredMealRecord: Codable, Sendable {
    let record: MealRecord
    let beforeImageFile: String?
    let afterImageFile: String?

    private enum FileKeys: String, CodingKey {
        case beforeImageFile
        case afterImageFile
    }

    init(record: MealRecord, beforeImageFile: String?, afterImageFile: String?) {
        self.record = record
        self.beforeImageFile = beforeImageFile
        self.afterImageFile = afterImageFile
    }

    init(from decoder: Decoder) throws {
        record = try MealRecord(from: decoder)
        let container = try decoder.container(keyedBy: FileKeys.self)
        beforeImageFile = try container.decodeIfPresent(String.self, forKey: .beforeImageFile)
        afterImageFile = try container.decodeIfPresent(String.self, forKey: .afterImageFile)
    }

    func encode(to encoder: Encoder) throws {
        try record.encode(to: encoder)
        var container = encoder.container(keyedBy: FileKeys.self)
        try container.encodeIfPresent(beforeImageFile, forKey: .beforeImageFile)
        try container.encodeIfPresent(afterImageFile, forKey: .afterImageFile)
    }
}
