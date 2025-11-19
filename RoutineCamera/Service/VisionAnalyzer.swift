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
struct FoodAnalysisResult {
    let foodItems: [String] // 인식된 음식 종류
    let extractedText: [String] // 추출된 텍스트
    let confidence: Float // 신뢰도 (0.0 ~ 1.0)

    var summary: String {
        var result = ""

        if !foodItems.isEmpty {
            result += "🍽️ 음식: \(foodItems.joined(separator: ", "))\n"
        }

        if !extractedText.isEmpty {
            result += "📝 텍스트: \(extractedText.joined(separator: " "))"
        }

        return result.isEmpty ? "분석 결과 없음" : result
    }
}

class VisionAnalyzer {
    static let shared = VisionAnalyzer()

    private init() {}

    // 영어 음식 이름을 한국어로 변환하는 딕셔너리
    private let foodNameTranslations: [String: String] = [
        // 주식
        "rice": "밥",
        "bread": "빵",
        "noodle": "국수",
        "pasta": "파스타",
        "pizza": "피자",
        "sandwich": "샌드위치",
        "burger": "버거",
        "hamburger": "햄버거",
        "hot dog": "핫도그",
        "taco": "타코",
        "burrito": "부리또",
        "sushi": "초밥",
        "ramen": "라면",

        // 고기류
        "meat": "고기",
        "beef": "소고기",
        "pork": "돼지고기",
        "chicken": "닭고기",
        "fish": "생선",
        "steak": "스테이크",
        "bacon": "베이컨",
        "sausage": "소시지",
        "fried chicken": "후라이드 치킨",

        // 채소/과일
        "salad": "샐러드",
        "vegetable": "채소",
        "fruit": "과일",
        "apple": "사과",
        "banana": "바나나",
        "orange": "오렌지",
        "strawberry": "딸기",
        "tomato": "토마토",
        "potato": "감자",
        "carrot": "당근",
        "onion": "양파",
        "lettuce": "상추",
        "cabbage": "양배추",

        // 음료
        "coffee": "커피",
        "tea": "차",
        "juice": "주스",
        "milk": "우유",
        "water": "물",
        "soda": "탄산음료",
        "beer": "맥주",
        "wine": "와인",

        // 디저트
        "cake": "케이크",
        "cookie": "쿠키",
        "ice cream": "아이스크림",
        "chocolate": "초콜릿",
        "candy": "사탕",
        "pie": "파이",
        "donut": "도넛",
        "muffin": "머핀",

        // 한식
        "kimchi": "김치",
        "bibimbap": "비빔밥",
        "bulgogi": "불고기",
        "tteokbokki": "떡볶이",

        // 기타
        "egg": "계란",
        "soup": "수프",
        "curry": "카레",
        "fried rice": "볶음밥",
        "dumpling": "만두",
        "spring roll": "스프링롤",
        "french fries": "감자튀김",
        "cheese": "치즈",
        "yogurt": "요거트",
        "cereal": "시리얼",
        "oatmeal": "오트밀",

        // 일반 분류
        "food": "음식",
        "meal": "식사",
        "dish": "요리",
        "snack": "간식",
        "dessert": "디저트",
        "appetizer": "애피타이저",
        "main course": "메인 요리",
        "side dish": "반찬",
        "breakfast": "아침식사",
        "lunch": "점심식사",
        "dinner": "저녁식사"
    ]

    // 영어 레이블을 한국어로 변환
    private func translateToKorean(_ englishLabel: String) -> String {
        let lowercased = englishLabel.lowercased()

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
        return englishLabel.capitalized
    }

    // 음식 + 텍스트 종합 분석
    func analyzeFoodImage(_ image: UIImage, completion: @escaping (Result<FoodAnalysisResult, Error>) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(.failure(NSError(domain: "VisionAnalyzer", code: -1, userInfo: [NSLocalizedDescriptionKey: "이미지 변환 실패"])))
            return
        }

        var foodItems: [String] = []
        var extractedText: [String] = []
        var maxConfidence: Float = 0.0

        let dispatchGroup = DispatchGroup()

        // 1. 물체 인식 (이미지 분류)
        dispatchGroup.enter()
        classifyObjects(cgImage: cgImage) { items, confidence in
            foodItems = items
            maxConfidence = max(maxConfidence, confidence)
            dispatchGroup.leave()
        }

        // 2. 텍스트 추출 (OCR)
        dispatchGroup.enter()
        extractText(cgImage: cgImage) { texts, confidence in
            extractedText = texts
            maxConfidence = max(maxConfidence, confidence)
            dispatchGroup.leave()
        }

        // 모든 분석 완료 후 결과 반환
        dispatchGroup.notify(queue: .main) {
            let result = FoodAnalysisResult(
                foodItems: foodItems,
                extractedText: extractedText,
                confidence: maxConfidence
            )
            completion(.success(result))
        }
    }

    // 이미지 분류 (음식 관련 항목 추출)
    private func classifyObjects(cgImage: CGImage, completion: @escaping ([String], Float) -> Void) {
        let request = VNClassifyImageRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ 이미지 분류 오류: \(error)")
                completion([], 0.0)
                return
            }

            guard let observations = request.results as? [VNClassificationObservation] else {
                completion([], 0.0)
                return
            }

            // 상위 5개 결과 (신뢰도 25% 이상)
            let englishItems = observations
                .filter { $0.confidence > 0.25 }
                .prefix(5)
                .map { $0.identifier }

            // 한국어로 번역
            let koreanItems = englishItems.map { self.translateToKorean($0) }

            let maxConfidence = observations.first?.confidence ?? 0.0

            print("✅ 이미지 분류 결과: \(koreanItems.joined(separator: ", ")) (신뢰도: \(maxConfidence))")
            completion(Array(koreanItems), maxConfidence)
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("❌ Vision Request 실행 오류: \(error)")
            completion([], 0.0)
        }
    }

    // 텍스트 추출 (OCR)
    private func extractText(cgImage: CGImage, completion: @escaping ([String], Float) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                print("❌ 텍스트 추출 오류: \(error)")
                completion([], 0.0)
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion([], 0.0)
                return
            }

            let texts = observations.compactMap { observation -> String? in
                guard let topCandidate = observation.topCandidates(1).first,
                      topCandidate.confidence > 0.5 else { return nil }
                return topCandidate.string
            }

            let maxConfidence = observations.compactMap { $0.topCandidates(1).first?.confidence }.max() ?? 0.0

            print("✅ 텍스트 추출 결과: \(texts.joined(separator: " ")) (신뢰도: \(maxConfidence))")
            completion(texts, maxConfidence)
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"] // 한글 + 영어
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("❌ Vision Request 실행 오류: \(error)")
            completion([], 0.0)
        }
    }
}
