//
//  MealRecord.swift
//  RoutineCameraCore
//
//  한 끼 기록 모델 (순수 Foundation). 이미지는 Data로 보관.
//

import Foundation

// 사진 분석 결과 (기기 안 Vision). description 은 예전 버전이 남긴 설명 — 있으면 그대로 보인다
public struct VisionAnalysisData: Codable, Sendable {
    public let foodItems: [String]
    public let extractedText: [String]
    public let confidence: Float
    public let analyzedDate: Date
    public let description: String?

    public init(foodItems: [String], extractedText: [String], confidence: Float, analyzedDate: Date, description: String? = nil) {
        self.foodItems = foodItems
        self.extractedText = extractedText
        self.confidence = confidence
        self.analyzedDate = analyzedDate
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        foodItems = try c.decode([String].self, forKey: .foodItems)
        extractedText = try c.decode([String].self, forKey: .extractedText)
        confidence = try c.decode(Float.self, forKey: .confidence)
        analyzedDate = try c.decode(Date.self, forKey: .analyzedDate)
        description = try c.decodeIfPresent(String.self, forKey: .description)
    }

    public var summary: String {
        var result = ""
        // 패키지엔 리소스가 없어 앱/위젯 번들(.main)의 카탈로그에서 찾는다
        if !foodItems.isEmpty {
            let foods = foodItems.joined(separator: ", ")
            result += "🍽️ " + String(localized: "음식: \(foods)", bundle: .main, comment: "Food analysis summary: detected foods") + "\n"
        }
        if let desc = description, !desc.isEmpty { result += "💬 \(desc)\n" }
        if !extractedText.isEmpty {
            let text = extractedText.joined(separator: " ")
            result += "📝 " + String(localized: "텍스트: \(text)", bundle: .main, comment: "Food analysis summary: text found in the photo")
        }
        return result.isEmpty ? String(localized: "분석 결과 없음", bundle: .main, comment: "Food analysis summary: nothing found") : result
    }
}

/// 사진을 찍은 곳. 이름은 찍은 뒤 기기에서 주소로 바꿔 둔 것 (못 바꿨으면 nil)
public struct MealPlace: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public var name: String?

    public init(latitude: Double, longitude: Double, name: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
    }
}

public struct MealRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let mealType: MealType
    public var beforeImageData: Data?
    public var afterImageData: Data?
    public var memo: String?
    public var recordedWithoutPhoto: Bool
    public var hidePhotoCountBadge: Bool
    public var visionAnalysis: VisionAnalysisData?
    public var capturedAt: Date?
    public var ateAll: Bool
    /// 찍은 곳 (설정에서 켰을 때만). 친구에게는 올리지 않는다
    public var place: MealPlace?
    /// 얼마나 먹었는지 (다 / 절반 / 조금). 남기지 않았으면 nil
    public var portion: MealPortion?

    public init(id: UUID = UUID(), date: Date, mealType: MealType, beforeImageData: Data? = nil, afterImageData: Data? = nil, memo: String? = nil, recordedWithoutPhoto: Bool = false, hidePhotoCountBadge: Bool = false, visionAnalysis: VisionAnalysisData? = nil, capturedAt: Date? = nil, ateAll: Bool = false, place: MealPlace? = nil, portion: MealPortion? = nil) {
        self.id = id
        self.date = date
        self.mealType = mealType
        self.beforeImageData = beforeImageData
        self.afterImageData = afterImageData
        self.memo = memo
        self.recordedWithoutPhoto = recordedWithoutPhoto
        self.hidePhotoCountBadge = hidePhotoCountBadge
        self.visionAnalysis = visionAnalysis
        self.capturedAt = capturedAt
        self.ateAll = ateAll
        self.place = place
        self.portion = portion
    }

    /// 같은 기록(id 유지)에 사진만 바꿔 끼운 사본 — 사진을 파일로 빼서 저장하고 다시 붙일 때 쓴다
    public func replacingImages(before: Data?, after: Data?) -> MealRecord {
        MealRecord(id: id, date: date, mealType: mealType, beforeImageData: before, afterImageData: after, memo: memo,
                   recordedWithoutPhoto: recordedWithoutPhoto, hidePhotoCountBadge: hidePhotoCountBadge,
                   visionAnalysis: visionAnalysis, capturedAt: capturedAt, ateAll: ateAll, place: place, portion: portion)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        mealType = try c.decode(MealType.self, forKey: .mealType)
        beforeImageData = try c.decodeIfPresent(Data.self, forKey: .beforeImageData)
        afterImageData = try c.decodeIfPresent(Data.self, forKey: .afterImageData)
        memo = try c.decodeIfPresent(String.self, forKey: .memo)
        recordedWithoutPhoto = try c.decodeIfPresent(Bool.self, forKey: .recordedWithoutPhoto) ?? false
        hidePhotoCountBadge = try c.decodeIfPresent(Bool.self, forKey: .hidePhotoCountBadge) ?? false
        visionAnalysis = try c.decodeIfPresent(VisionAnalysisData.self, forKey: .visionAnalysis)
        capturedAt = try c.decodeIfPresent(Date.self, forKey: .capturedAt)
        ateAll = try c.decodeIfPresent(Bool.self, forKey: .ateAll) ?? false
        place = try c.decodeIfPresent(MealPlace.self, forKey: .place)
        // 모르는 값(새 버전이 더한 양)이면 버리지 않고 비워 둔다 — 기록 전체를 못 읽게 되지 않게
        portion = (try? c.decodeIfPresent(MealPortion.self, forKey: .portion)) ?? nil
    }

    /// 썸네일용 (식후 우선, 없으면 식전)
    public var thumbnailImageData: Data? { afterImageData ?? beforeImageData }

    /// 사진 1장 이상 / 사진 없이 기록 / "다 먹음" 중 하나라도면 완료
    public var isComplete: Bool {
        beforeImageData != nil || afterImageData != nil || recordedWithoutPhoto || ateAll
    }

    /// 정렬용 시각 (촬영 시각 있으면 그것, 없으면 그날 날짜)
    public var sortDate: Date { capturedAt ?? date }

    /// 순간 피드의 자리: 촬영 시각, 없으면 그날의 끼니 대표 시각.
    /// 같은 날 안에서도 아침(아래) → 저녁(위) 순으로 시간 흐름대로 놓인다.
    public func feedDate(calendar: Calendar = .current) -> Date {
        if let capturedAt { return capturedAt }
        let base = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .hour, value: mealType.typicalHour, to: base) ?? base
    }
    public var feedDate: Date { feedDate() }

    /// 식전만 찍고 아직 식후/다먹음 신호가 없는 미마감 기록
    public var isEatingInProgress: Bool {
        beforeImageData != nil && afterImageData == nil && !ateAll && !recordedWithoutPhoto
    }

    /// "먹는 중"으로 볼 수 있는 상태 — 당일 기록에만 해당
    public var isEatingInProgressToday: Bool { isEatingInProgress(asOf: Date()) }

    /// 식전만 남긴 채 날이 지나간 기록 → 마무리 기록이 필요한 상태
    public var needsRecordCompletion: Bool { needsRecordCompletion(asOf: Date()) }

    /// 기준 시각과 같은 날의 미마감 기록인지
    public func isEatingInProgress(asOf now: Date, calendar: Calendar = .current) -> Bool {
        self.isEatingInProgress && calendar.isDate(sortDate, inSameDayAs: now)
    }

    /// 기준 시각보다 이전 날에 남긴 미마감 기록인지
    public func needsRecordCompletion(asOf now: Date, calendar: Calendar = .current) -> Bool {
        self.isEatingInProgress && !calendar.isDate(sortDate, inSameDayAs: now)
    }

    /// 식전·식후 둘 다 있어 식사가 마감된 기록
    public var hasBeforeAfterComparison: Bool {
        beforeImageData != nil && afterImageData != nil
    }

    /// 식후만 남기고 식전 사진이 비어 있는 기록 → 어떤 사진이 필요한지 화면에 그대로 표시하기 위함
    public var needsBeforePhoto: Bool {
        afterImageData != nil && beforeImageData == nil && !ateAll && !recordedWithoutPhoto
    }
}
