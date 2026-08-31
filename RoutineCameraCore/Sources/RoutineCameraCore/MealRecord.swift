//
//  MealRecord.swift
//  RoutineCameraCore
//
//  한 끼 기록 모델 (순수 Foundation). 이미지는 Data로 보관.
//

import Foundation

// Vision/OpenAI 분석 결과
public struct VisionAnalysisData: Codable, Sendable {
    public let foodItems: [String]
    public let extractedText: [String]
    public let confidence: Float
    public let analyzedDate: Date
    public let isOpenAI: Bool
    public let description: String?

    public init(foodItems: [String], extractedText: [String], confidence: Float, analyzedDate: Date, isOpenAI: Bool = false, description: String? = nil) {
        self.foodItems = foodItems
        self.extractedText = extractedText
        self.confidence = confidence
        self.analyzedDate = analyzedDate
        self.isOpenAI = isOpenAI
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        foodItems = try c.decode([String].self, forKey: .foodItems)
        extractedText = try c.decode([String].self, forKey: .extractedText)
        confidence = try c.decode(Float.self, forKey: .confidence)
        analyzedDate = try c.decode(Date.self, forKey: .analyzedDate)
        isOpenAI = try c.decodeIfPresent(Bool.self, forKey: .isOpenAI) ?? false
        description = try c.decodeIfPresent(String.self, forKey: .description)
    }

    public var summary: String {
        var result = ""
        if !foodItems.isEmpty { result += "🍽️ 음식: \(foodItems.joined(separator: ", "))\n" }
        if let desc = description, !desc.isEmpty { result += "💬 \(desc)\n" }
        if !extractedText.isEmpty { result += "📝 텍스트: \(extractedText.joined(separator: " "))" }
        return result.isEmpty ? "분석 결과 없음" : result
    }
}

public struct MealRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let mealType: MealType
    public let beforeImageData: Data?
    public let afterImageData: Data?
    public var memo: String?
    public let recordedWithoutPhoto: Bool
    public var hidePhotoCountBadge: Bool
    public var visionAnalysis: VisionAnalysisData?
    public var capturedAt: Date?
    public var ateAll: Bool

    public init(date: Date, mealType: MealType, beforeImageData: Data? = nil, afterImageData: Data? = nil, memo: String? = nil, recordedWithoutPhoto: Bool = false, hidePhotoCountBadge: Bool = false, visionAnalysis: VisionAnalysisData? = nil, capturedAt: Date? = nil, ateAll: Bool = false) {
        self.id = UUID()
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
    }

    /// 썸네일용 (식후 우선, 없으면 식전)
    public var thumbnailImageData: Data? { afterImageData ?? beforeImageData }

    /// 사진 1장 이상 / 사진 없이 기록 / "다 먹음" 중 하나라도면 완료
    public var isComplete: Bool {
        beforeImageData != nil || afterImageData != nil || recordedWithoutPhoto || ateAll
    }

    /// 정렬용 시각 (촬영 시각 있으면 그것, 없으면 그날 날짜)
    public var sortDate: Date { capturedAt ?? date }

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
