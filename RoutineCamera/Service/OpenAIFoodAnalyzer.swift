//
//  OpenAIFoodAnalyzer.swift
//  RoutineCamera
//
//  OpenAI Vision API를 사용한 고정밀 음식 분석
//

import Foundation
import UIKit

// OpenAI API 응답 구조
struct OpenAIResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let message: Message
    }

    struct Message: Codable {
        let content: String
    }
}

// OpenAI 음식 분석 결과
struct OpenAIFoodResult {
    let foodName: String
    let ingredients: [String]
    let description: String

    var summary: String {
        var result = "🍽️ 음식: \(foodName)"

        if !ingredients.isEmpty {
            result += "\n📋 재료: \(ingredients.joined(separator: ", "))"
        }

        if !description.isEmpty {
            result += "\n💬 \(description)"
        }

        return result
    }
}

class OpenAIFoodAnalyzer {
    static let shared = OpenAIFoodAnalyzer()

    private init() {}

    // OpenAI API 키 (설정에서 가져오기)
    private var apiKey: String {
        return UserDefaults.standard.string(forKey: "OpenAI_API_Key") ?? ""
    }

    // API 키 설정 여부 확인
    var isConfigured: Bool {
        return !apiKey.isEmpty
    }

    // API 키 저장
    func setAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "OpenAI_API_Key")
    }

    // 음식 이미지 분석
    func analyzeFood(image: UIImage) async throws -> OpenAIFoodResult {
        guard isConfigured else {
            throw NSError(domain: "OpenAIFoodAnalyzer", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "OpenAI API 키가 설정되지 않았습니다."])
        }

        // 1. 이미지를 JPEG로 압축하고 Base64로 인코딩
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "OpenAIFoodAnalyzer", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "이미지 변환 실패"])
        }

        let base64Image = imageData.base64EncodedString()

        // 2. API 요청 준비
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 3. 프롬프트 구성
        let prompt = """
        이 음식 사진을 분석해서 다음 정보를 JSON 형식으로 답변해주세요:

        {
          "foodName": "음식 이름 (한국어)",
          "ingredients": ["재료1", "재료2", "재료3"],
          "description": "간단한 설명 (한 줄)"
        }

        주의사항:
        - 음식 이름은 정확하고 구체적으로 (예: "김치찌개", "불고기 덮밥")
        - 재료는 주요 재료만 3~5개 정도
        - 설명은 한 줄로 간단히
        - 반드시 JSON 형식으로만 답변
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 500
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // 4. API 호출
        let (data, response) = try await URLSession.shared.data(for: request)

        // 5. 응답 확인
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenAIFoodAnalyzer", code: -3,
                         userInfo: [NSLocalizedDescriptionKey: "잘못된 응답"])
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ OpenAI API Error: \(errorMessage)")
            throw NSError(domain: "OpenAIFoodAnalyzer", code: httpResponse.statusCode,
                         userInfo: [NSLocalizedDescriptionKey: "API 오류: \(httpResponse.statusCode)"])
        }

        // 6. 응답 파싱
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = openAIResponse.choices.first?.message.content else {
            throw NSError(domain: "OpenAIFoodAnalyzer", code: -4,
                         userInfo: [NSLocalizedDescriptionKey: "응답 파싱 실패"])
        }

        print("✅ OpenAI 응답: \(content)")

        // 7. JSON 파싱 (코드 블록 제거)
        let jsonString = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let foodName = json["foodName"] as? String else {
            throw NSError(domain: "OpenAIFoodAnalyzer", code: -5,
                         userInfo: [NSLocalizedDescriptionKey: "JSON 파싱 실패"])
        }

        let ingredients = json["ingredients"] as? [String] ?? []
        let description = json["description"] as? String ?? ""

        return OpenAIFoodResult(
            foodName: foodName,
            ingredients: ingredients,
            description: description
        )
    }
}
