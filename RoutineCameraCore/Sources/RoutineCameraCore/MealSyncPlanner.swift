//
//  MealSyncPlanner.swift
//  RoutineCameraCore
//
//  iCloud 백업에서 "이 기기에서 무엇이 바뀌었나" 를 정한다.
//  끼니 칸마다 지난번에 맞춘 상태(지문)를 기억해 두고, 지금 기록과 비교해 바뀐 칸만 보낸다.
//  CloudKit 은 모른다 — 앱의 MealCloudSync 가 이 계획대로 보낸다.
//

import CryptoKit
import Foundation

/// 끼니 칸(또는 하루 기록 문서) 하나의 동기화 상태. 기기에 저장해 둔다 — 칸 이름을 바꾸면 저장된 상태를 못 읽는다.
public struct MealSyncSlotState: Codable, Equatable, Sendable {
    public var fingerprint: String?
    public var modifiedAt: Date
    public var isDirty: Bool
    public var isDeleted: Bool
    public var systemFields: Data?

    public init(fingerprint: String? = nil, modifiedAt: Date, isDirty: Bool, isDeleted: Bool, systemFields: Data? = nil) {
        self.fingerprint = fingerprint
        self.modifiedAt = modifiedAt
        self.isDirty = isDirty
        self.isDeleted = isDeleted
        self.systemFields = systemFields
    }
}

public enum MealSyncPlanner {

    /// 이 기기에 지금 있는 것 하나
    public struct Item: Sendable {
        public let name: String
        public let fingerprint: String
        /// 처음 보는 것일 때 쓸 고친 시각
        public let firstSeenModifiedAt: Date
        /// 고친 시각을 따로 아는 것(하루 기록)이면 그 시각. nil 이면 지금
        public let knownModifiedAt: Date?
        /// 고친 시각을 아는 것은 바뀔 때마다 그 시각으로 맞춘다 (끼니는 처음 볼 때만 firstSeen 을 쓴다)
        public let usesKnownModifiedAt: Bool

        /// 끼니: 처음 보면 기록 시각을 쓰고(충돌 때 방금 고친 쪽이 이긴다), 그 뒤 바뀌면 지금
        public static func meal(name: String, fingerprint: String, recordedAt: Date) -> Item {
            Item(name: name, fingerprint: fingerprint, firstSeenModifiedAt: recordedAt, knownModifiedAt: nil, usesKnownModifiedAt: false)
        }

        /// 하루 기록 · 스탬프 목록: 고친 시각을 알면 그것, 모르면 지금
        public static func document(name: String, fingerprint: String, modifiedAt: Date?) -> Item {
            Item(name: name, fingerprint: fingerprint, firstSeenModifiedAt: modifiedAt ?? .distantPast,
                 knownModifiedAt: modifiedAt, usesKnownModifiedAt: true)
        }
    }

    public struct Plan: Equatable, Sendable {
        public var saves: [String] = []
        public var deletes: [String] = []
        public var isEmpty: Bool { saves.isEmpty && deletes.isEmpty }
    }

    /// 지금 있는 것과 저장해 둔 상태를 비교해 보낼 것을 정하고 상태를 고친다.
    /// 바뀌지 않은 칸은 건드리지 않는다 — 같은 내용으로 두 번 부르면 두 번째는 빈 계획이다.
    public static func reconcile(slots: inout [String: MealSyncSlotState], current: [Item], now: Date) -> Plan {
        var plan = Plan()
        var seen = Set<String>()

        for item in current {
            seen.insert(item.name)
            if var existing = slots[item.name] {
                guard existing.fingerprint != item.fingerprint || existing.isDeleted else { continue }
                existing.fingerprint = item.fingerprint
                existing.modifiedAt = item.usesKnownModifiedAt ? (item.knownModifiedAt ?? now) : now
                existing.isDirty = true
                existing.isDeleted = false
                slots[item.name] = existing
            } else {
                slots[item.name] = MealSyncSlotState(
                    fingerprint: item.fingerprint,
                    modifiedAt: item.usesKnownModifiedAt ? (item.knownModifiedAt ?? now) : item.firstSeenModifiedAt,
                    isDirty: true, isDeleted: false)
            }
            plan.saves.append(item.name)
        }

        // 기기에서 사라진 것은 지운 것이다
        for (name, slot) in slots where !seen.contains(name) && !slot.isDeleted {
            slots[name]?.isDeleted = true
            slots[name]?.isDirty = true
            slots[name]?.modifiedAt = now
            plan.deletes.append(name)
        }
        plan.deletes.sort()
        return plan
    }

    // MARK: - 지문

    /// 끼니 기록의 지문. 저장해 둔 지문과 그대로 비교되므로 **이미 있는 칸의 순서 · 모양을 바꾸면 안 된다** —
    /// 바꾸면 모든 기록이 "바뀐 것" 으로 잡혀 전부 다시 올라간다. 새 칸은 값이 있는 기록에만 뒤에 더한다.
    public static func fingerprint(of record: MealRecord) -> String {
        var parts = [record.id.uuidString,
                     record.memo ?? "",
                     "\(record.beforeImageData?.count ?? -1)",
                     "\(record.afterImageData?.count ?? -1)",
                     "\(record.recordedWithoutPhoto)",
                     "\(record.hidePhotoCountBadge)",
                     "\(record.ateAll)",
                     "\(record.capturedAt?.timeIntervalSince1970 ?? 0)",
                     "\(record.visionAnalysis?.analyzedDate.timeIntervalSince1970 ?? 0)"]
        // 찍은 곳이 있는 기록만 더한다 — 예전 기록의 지문이 바뀌어 전부 다시 올라가지 않게
        if let place = record.place {
            parts.append("\(place.latitude),\(place.longitude),\(place.name ?? "")")
        }
        // 먹은 양도 남긴 기록만 더한다 (같은 이유)
        if let portion = record.portion {
            parts.append("portion:\(portion.rawValue)")
        }
        // 식사 시간도 잰 기록만 더한다 (같은 이유)
        if record.startedAt != nil || record.finishedAt != nil {
            parts.append("pace:\(record.startedAt?.timeIntervalSince1970 ?? 0)-\(record.finishedAt?.timeIntervalSince1970 ?? 0)")
        }
        return hexDigest(Data(parts.joined(separator: "|").utf8))
    }

    /// 소문자 16진수 SHA256
    public static func hexDigest(_ source: Data) -> String {
        var hex: [UInt8] = []
        hex.reserveCapacity(64)
        for byte in SHA256.hash(data: source) {
            hex.append(hexDigits[Int(byte >> 4)])
            hex.append(hexDigits[Int(byte & 0x0F)])
        }
        return String(decoding: hex, as: UTF8.self)
    }

    private static let hexDigits = Array("0123456789abcdef".utf8)

    // MARK: - 사진 채우기

    /// base 에 없는 사진을 other 의 것으로 채운다 (양쪽에서 식전 · 식후를 따로 찍었을 때 둘 다 남긴다)
    public static func fillingPhotos(of base: MealRecord, from other: MealRecord?) -> MealRecord {
        base.replacingImages(before: base.beforeImageData ?? other?.beforeImageData,
                             after: base.afterImageData ?? other?.afterImageData)
    }

    // MARK: - 칸 이름

    /// 레코드 이름 meal_<앨범>_<yyyy-MM-dd>_<끼니> 를 나눈다. 끼니는 표시용 rawValue(한글)가 아니라 케이스 이름이다.
    /// 모르는 끼니(새 버전이 만든 것)나 틀린 날짜면 nil.
    public static func parseSlotName(_ recordName: String) -> (album: String, day: String, mealType: MealType)? {
        let parts = recordName.split(separator: "_").map(String.init)
        guard parts.count == 4, parts[0] == "meal",
              let mealType = MealType.allCases.first(where: { "\($0)" == parts[3] }),
              DayKey.date(from: parts[2]) != nil else { return nil }
        return (parts[1], parts[2], mealType)
    }

    public static func slotName(album: String, day: String, mealType: MealType) -> String {
        "meal_\(album)_\(day)_\(mealType)"
    }
}
