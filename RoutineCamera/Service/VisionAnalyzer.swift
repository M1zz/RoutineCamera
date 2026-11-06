//
//  VisionAnalyzer.swift
//  RoutineCamera
//
//  Vision Framework를 사용한 식단 분석 (이미지 분류 + OCR)
//

import Foundation
import Vision
import UIKit

// 분석 결과 모델
nonisolated struct FoodAnalysisResult: Sendable {
    let foodItems: [String] // 인식된 음식 종류
    let extractedText: [String] // 추출된 텍스트
    let confidence: Float // 신뢰도 (0.0 ~ 1.0)

    var summary: String {
        var result = ""

        if !foodItems.isEmpty {
            result += String(localized: "🍽️ 음식: \(foodItems.joined(separator: ", "))", comment: "Analysis summary line listing recognized foods") + "\n"
        }

        if !extractedText.isEmpty {
            result += String(localized: "📝 텍스트: \(extractedText.joined(separator: " "))", comment: "Analysis summary line with text read from the photo")
        }

        return result.isEmpty ? String(localized: "분석 결과 없음", comment: "Shown when photo analysis found nothing") : result
    }
}

/// 메인 액터에 묶지 않는다 — 분석은 백그라운드 큐에서 돈다(프로젝트 기본 격리가 MainActor 다).
nonisolated final class VisionAnalyzer: Sendable {
    static let shared = VisionAnalyzer()

    private init() {}

    // 영어 음식 이름을 한국어로 변환하는 딕셔너리
    private let foodNameTranslations: [String: String] = [
        // 주식
        "rice": String(localized: "밥", comment: "Food name recognized in a meal photo"),
        "bread": String(localized: "빵", comment: "Food name recognized in a meal photo"),
        "noodle": String(localized: "국수", comment: "Food name recognized in a meal photo"),
        "pasta": String(localized: "파스타", comment: "Food name recognized in a meal photo"),
        "pizza": String(localized: "피자", comment: "Food name recognized in a meal photo"),
        "sandwich": String(localized: "샌드위치", comment: "Food name recognized in a meal photo"),
        "burger": String(localized: "버거", comment: "Food name recognized in a meal photo"),
        "hamburger": String(localized: "햄버거", comment: "Food name recognized in a meal photo"),
        "hot dog": String(localized: "핫도그", comment: "Food name recognized in a meal photo"),
        "taco": String(localized: "타코", comment: "Food name recognized in a meal photo"),
        "burrito": String(localized: "부리또", comment: "Food name recognized in a meal photo"),
        "sushi": String(localized: "초밥", comment: "Food name recognized in a meal photo"),
        "ramen": String(localized: "라면", comment: "Food name recognized in a meal photo"),

        // 고기류
        "meat": String(localized: "고기", comment: "Food name recognized in a meal photo"),
        "beef": String(localized: "소고기", comment: "Food name recognized in a meal photo"),
        "pork": String(localized: "돼지고기", comment: "Food name recognized in a meal photo"),
        "chicken": String(localized: "닭고기", comment: "Food name recognized in a meal photo"),
        "fish": String(localized: "생선", comment: "Food name recognized in a meal photo"),
        "steak": String(localized: "스테이크", comment: "Food name recognized in a meal photo"),
        "bacon": String(localized: "베이컨", comment: "Food name recognized in a meal photo"),
        "sausage": String(localized: "소시지", comment: "Food name recognized in a meal photo"),
        "fried chicken": String(localized: "후라이드 치킨", comment: "Food name recognized in a meal photo"),

        // 채소/과일
        "salad": String(localized: "샐러드", comment: "Food name recognized in a meal photo"),
        "vegetable": String(localized: "채소", comment: "Food name recognized in a meal photo"),
        "fruit": String(localized: "과일", comment: "Food name recognized in a meal photo"),
        "apple": String(localized: "사과", comment: "Food name recognized in a meal photo"),
        "banana": String(localized: "바나나", comment: "Food name recognized in a meal photo"),
        "orange": String(localized: "오렌지", comment: "Food name recognized in a meal photo"),
        "strawberry": String(localized: "딸기", comment: "Food name recognized in a meal photo"),
        "tomato": String(localized: "토마토", comment: "Food name recognized in a meal photo"),
        "potato": String(localized: "감자", comment: "Food name recognized in a meal photo"),
        "carrot": String(localized: "당근", comment: "Food name recognized in a meal photo"),
        "onion": String(localized: "양파", comment: "Food name recognized in a meal photo"),
        "lettuce": String(localized: "상추", comment: "Food name recognized in a meal photo"),
        "cabbage": String(localized: "양배추", comment: "Food name recognized in a meal photo"),

        // 음료
        "coffee": String(localized: "커피", comment: "Food name recognized in a meal photo"),
        "tea": String(localized: "차", comment: "Food name recognized in a meal photo"),
        "juice": String(localized: "주스", comment: "Food name recognized in a meal photo"),
        "milk": String(localized: "우유", comment: "Food name recognized in a meal photo"),
        "water": String(localized: "물", comment: "Food name recognized in a meal photo"),
        "soda": String(localized: "탄산음료", comment: "Food name recognized in a meal photo"),
        "beer": String(localized: "맥주", comment: "Food name recognized in a meal photo"),
        "wine": String(localized: "와인", comment: "Food name recognized in a meal photo"),

        // 디저트
        "cake": String(localized: "케이크", comment: "Food name recognized in a meal photo"),
        "cookie": String(localized: "쿠키", comment: "Food name recognized in a meal photo"),
        "ice cream": String(localized: "아이스크림", comment: "Food name recognized in a meal photo"),
        "chocolate": String(localized: "초콜릿", comment: "Food name recognized in a meal photo"),
        "candy": String(localized: "사탕", comment: "Food name recognized in a meal photo"),
        "pie": String(localized: "파이", comment: "Food name recognized in a meal photo"),
        "donut": String(localized: "도넛", comment: "Food name recognized in a meal photo"),
        "muffin": String(localized: "머핀", comment: "Food name recognized in a meal photo"),

        // 한식
        "kimchi": String(localized: "김치", comment: "Food name recognized in a meal photo"),
        "bibimbap": String(localized: "비빔밥", comment: "Food name recognized in a meal photo"),
        "bulgogi": String(localized: "불고기", comment: "Food name recognized in a meal photo"),
        "tteokbokki": String(localized: "떡볶이", comment: "Food name recognized in a meal photo"),

        // 기타
        "egg": String(localized: "계란", comment: "Food name recognized in a meal photo"),
        "soup": String(localized: "수프", comment: "Food name recognized in a meal photo"),
        "curry": String(localized: "카레", comment: "Food name recognized in a meal photo"),
        "fried rice": String(localized: "볶음밥", comment: "Food name recognized in a meal photo"),
        "dumpling": String(localized: "만두", comment: "Food name recognized in a meal photo"),
        "spring roll": String(localized: "스프링롤", comment: "Food name recognized in a meal photo"),
        "french fries": String(localized: "감자튀김", comment: "Food name recognized in a meal photo"),
        "cheese": String(localized: "치즈", comment: "Food name recognized in a meal photo"),
        "yogurt": String(localized: "요거트", comment: "Food name recognized in a meal photo"),
        "cereal": String(localized: "시리얼", comment: "Food name recognized in a meal photo"),
        "oatmeal": String(localized: "오트밀", comment: "Food name recognized in a meal photo"),

        // 일반 분류
        "food": String(localized: "음식", comment: "Food name recognized in a meal photo"),
        "meal": String(localized: "식사", comment: "Food name recognized in a meal photo"),
        "dish": String(localized: "요리", comment: "Food name recognized in a meal photo"),
        "snack": String(localized: "간식", comment: "Food name recognized in a meal photo"),
        "dessert": String(localized: "디저트", comment: "Food name recognized in a meal photo"),
        "appetizer": String(localized: "애피타이저", comment: "Food name recognized in a meal photo"),
        "main course": String(localized: "메인 요리", comment: "Food name recognized in a meal photo"),
        "side dish": String(localized: "반찬", comment: "Food name recognized in a meal photo"),
        "breakfast": String(localized: "아침식사", comment: "Food name recognized in a meal photo"),
        "lunch": String(localized: "점심식사", comment: "Food name recognized in a meal photo"),
        "dinner": String(localized: "저녁식사", comment: "Food name recognized in a meal photo")
    ]

    // 영어 레이블을 한국어로 변환
    private func translateToKorean(_ englishLabel: String) -> String {
        let lowercased = englishLabel.lowercased().replacingOccurrences(of: "_", with: " ")

        // 정확히 일치하는 경우
        if let translation = foodNameTranslations[lowercased] {
            return translation
        }

        // 부분 일치 검색 (예: "grilled chicken" -> "닭고기")
        for (key, value) in foodNameTranslations {
            if lowercased.contains(key) {
                return value
            }
        }

        // 번역을 찾지 못한 경우 원문 반환 (첫 글자만 대문자로)
        return lowercased.capitalized
    }

    // 음식 + 텍스트 종합 분석
    /// 분석은 백그라운드에서 돌고, completion 은 메인에서 불린다.
    ///
    /// 1.2.2 에서 여기서 앱이 죽었다(libdispatch, 짝 없는 dispatch_group_leave).
    /// Vision 은 요청이 실패하면 요청의 완료 콜백을 에러로 부르고 **그와 함께** `perform` 도
    /// throw 한다. 콜백과 catch 가 둘 다 completion 을 불러 그룹을 두 번 떠났다.
    /// 그래서 요청에 콜백을 달지 않는다 — `perform` 이 끝나면 `results` 를 읽는다. 한 길뿐이다.
    /// 정확도 OCR 은 무거워 메인에서 돌면 화면이 멈추므로 백그라운드 큐에서 돌린다.
    func analyzeFoodImage(_ image: UIImage,
                          completion: @escaping @MainActor @Sendable (Result<FoodAnalysisResult, Error>) -> Void) {
        guard let cgImage = image.cgImage else {
            let error = NSError(domain: "VisionAnalyzer", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "이미지 변환 실패", comment: "Error: the photo could not be read for analysis")])
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let objects = self.classifyObjects(cgImage: cgImage)
            let texts = self.extractText(cgImage: cgImage)
            let result = FoodAnalysisResult(
                foodItems: objects.items,
                extractedText: texts.items,
                confidence: max(objects.confidence, texts.confidence)
            )
            DispatchQueue.main.async { completion(.success(result)) }
        }
    }

    // 이미지 분류 (음식 관련 항목 추출)
    private func classifyObjects(cgImage: CGImage) -> (items: [String], confidence: Float) {
        let request = VNClassifyImageRequest()
        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            print("❌ 이미지 분류 오류: \(error)")
            return ([], 0)
        }
        let observations = request.results ?? []

        // 상위 5개 결과 (신뢰도 25% 이상)을 한국어로
        let items = observations
            .filter { $0.confidence > 0.25 }
            .prefix(5)
            .map { translateToKorean($0.identifier) }
        let confidence = observations.first?.confidence ?? 0

        print("✅ 이미지 분류 결과: \(items.joined(separator: ", ")) (신뢰도: \(confidence))")
        return (items, confidence)
    }

    // 텍스트 추출 (OCR)
    private func extractText(cgImage: CGImage) -> (items: [String], confidence: Float) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"] // 한글 + 영어
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            print("❌ 텍스트 추출 오류: \(error)")
            return ([], 0)
        }
        let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }

        let texts = candidates.filter { $0.confidence > 0.5 }.map(\.string)
        let confidence = candidates.map(\.confidence).max() ?? 0

        print("✅ 텍스트 추출 결과: \(texts.joined(separator: " ")) (신뢰도: \(confidence))")
        return (texts, confidence)
    }
}
