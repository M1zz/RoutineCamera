//
//  MealRecordArchive.swift
//  RoutineCameraCore
//
//  기록을 디스크 형식(사진 파일 + 가벼운 JSON)으로 바꾸고 되읽는 규칙.
//  데이터 손실은 이 앱에서 가장 비싼 버그라, 형식과 "잃지 않는 순서" 를 여기 한 곳에 두고 테스트로 고정한다.
//  - 사진 바이트는 파일로, JSON 에는 파일 이름만.
//  - 예전 형식(사진 바이트가 JSON 안에 든 기록)도 그대로 읽는다.
//  - 파일로 못 옮긴 사진은 바이트로 남기고, 읽지 못한 사진은 참조를 지우지 않는다.
//

import Foundation

/// 저장하는 기록 한 건. 사진 바이트 대신 파일 이름을 담는다.
/// 위젯은 같은 JSON 에서 날짜 · 끼니 · 촬영 시각만 읽으므로 칸이 늘어도 영향이 없다.
public struct StoredMealRecord: Codable, Sendable {
    public let record: MealRecord
    public let beforeImageFile: String?
    public let afterImageFile: String?

    private enum FileKeys: String, CodingKey {
        case beforeImageFile
        case afterImageFile
    }

    public init(record: MealRecord, beforeImageFile: String?, afterImageFile: String?) {
        self.record = record
        self.beforeImageFile = beforeImageFile
        self.afterImageFile = afterImageFile
    }

    public init(from decoder: Decoder) throws {
        record = try MealRecord(from: decoder)
        let container = try decoder.container(keyedBy: FileKeys.self)
        beforeImageFile = try container.decodeIfPresent(String.self, forKey: .beforeImageFile)
        afterImageFile = try container.decodeIfPresent(String.self, forKey: .afterImageFile)
    }

    public func encode(to encoder: Encoder) throws {
        try record.encode(to: encoder)
        var container = encoder.container(keyedBy: FileKeys.self)
        try container.encodeIfPresent(beforeImageFile, forKey: .beforeImageFile)
        try container.encodeIfPresent(afterImageFile, forKey: .afterImageFile)
    }
}

public enum MealRecordArchive {

    /// 끼니 칸 하나의 기본 사진 파일 이름 (예: 2026-09-10_lunch_before.jpg)
    public static func slotName(for record: MealRecord, kind: String) -> String {
        MealImageFileStore.fileName(day: DayKey.string(from: record.date), slot: "\(record.mealType)", kind: kind)
    }

    // MARK: - 쓰기

    public struct Encoded: Sendable {
        /// 저장할 JSON
        public let data: Data
        /// 기록이 가리키는 사진 파일 이름들 — 여기 없는 파일은 JSON 을 바꾼 **뒤에** 지워도 된다
        public let referenced: Set<String>
        /// 파일로 쓰지 못해 JSON 안에 바이트로 남긴 사진 (칸 이름 → 이유)
        public let keptInline: [String: String]
    }

    /// 사진을 파일로 쓰고, 그 파일들을 가리키는 JSON 을 만든다.
    /// 부르는 쪽 순서: 이 함수(사진 파일 쓰기) → JSON 교체 → `referenced` 에 없는 파일 정리.
    /// 어느 단계에서 앱이 종료돼도 JSON 이 가리키는 사진은 디스크에 남아 있다.
    /// - Parameters:
    ///   - store: 사진 파일 보관소. nil 이면 사진을 JSON 안에 바이트로 둔다
    ///   - unreadable: 읽지 못한 사진 (끼니 칸 이름 → 실제 파일 이름). 비어 보여도 지운 사진이 아니라 참조와 파일을 지킨다
    public static func encode(records: [MealRecord], store: MealImageFileStore?,
                              unreadable: [String: String] = [:]) throws -> Encoded {
        var referenced = Set<String>()
        var keptInline: [String: String] = [:]
        var entries: [StoredMealRecord] = []
        entries.reserveCapacity(records.count)

        func storeImage(_ data: Data?, kind: String, of record: MealRecord) -> String? {
            guard let store else { return nil }
            let slot = slotName(for: record, kind: kind)
            guard let data else {
                // 읽지 못했던 사진이면 참조를 그대로 두고 다음 실행에 다시 읽는다
                guard let file = unreadable[slot] else { return nil }
                referenced.insert(file)
                return file
            }
            // 같은 날 같은 끼니 기록이 둘이면 서로 덮어쓰지 않게 기록 id 를 붙인다
            var name = slot
            if referenced.contains(name) {
                name = MealImageFileStore.fileName(day: DayKey.string(from: record.date),
                                                   slot: "\(record.mealType)-\(record.id.uuidString)", kind: kind)
            }
            do {
                try store.write(data, named: name)
                referenced.insert(name)
                return name
            } catch {
                keptInline[slot] = String(describing: error)
                return nil
            }
        }

        for record in records {
            let beforeFile = storeImage(record.beforeImageData, kind: "before", of: record)
            let afterFile = storeImage(record.afterImageData, kind: "after", of: record)
            // 파일로 옮긴 사진만 JSON 에서 뺀다. 못 옮긴 사진은 바이트 그대로 남는다.
            let slim = record.replacingImages(before: beforeFile == nil ? record.beforeImageData : nil,
                                              after: afterFile == nil ? record.afterImageData : nil)
            entries.append(StoredMealRecord(record: slim, beforeImageFile: beforeFile, afterImageFile: afterFile))
        }
        return Encoded(data: try JSONEncoder().encode(entries), referenced: referenced, keptInline: keptInline)
    }

    // MARK: - 읽기

    public struct Decoded: Sendable {
        public let records: [MealRecord]
        /// 사진 바이트가 JSON 안에 들어 있던 기록이 있다 (예전 형식 — 파일로 옮겨야 한다)
        public let hasInlinePhotos: Bool
        /// 파일을 읽지 못한 사진 (끼니 칸 이름 → 실제 파일 이름). 지운 사진이 아니다
        public let unreadable: [String: String]
    }

    /// 저장된 JSON 을 읽고 사진을 다시 붙인다. JSON 을 못 읽으면 던진다 — 빈 목록으로 돌려주지 않는다
    /// (빈 목록은 "다 지움" 으로 보여 다음 저장이 원본을 덮는다).
    public static func decode(_ data: Data, store: MealImageFileStore?) throws -> Decoded {
        let entries = try JSONDecoder().decode([StoredMealRecord].self, from: data)
        var hasInlinePhotos = false
        var unreadable: [String: String] = [:]

        func load(_ name: String?, kind: String, of record: MealRecord) -> Data? {
            guard let name else { return nil }
            if let data = store?.load(named: name) { return data }
            unreadable[slotName(for: record, kind: kind)] = name
            return nil
        }

        let records = entries.map { entry -> MealRecord in
            let record = entry.record
            if record.beforeImageData != nil || record.afterImageData != nil { hasInlinePhotos = true }
            let before = record.beforeImageData ?? load(entry.beforeImageFile, kind: "before", of: record)
            let after = record.afterImageData ?? load(entry.afterImageFile, kind: "after", of: record)
            return record.replacingImages(before: before, after: after)
        }
        return Decoded(records: records, hasInlinePhotos: hasInlinePhotos, unreadable: unreadable)
    }
}
