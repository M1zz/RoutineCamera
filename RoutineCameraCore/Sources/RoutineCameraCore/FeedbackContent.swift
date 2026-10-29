//
//  FeedbackContent.swift
//  RoutineCameraCore
//
//  피드백 본문 해석 — 이모지 반응인지 글인지 가른다.
//
//  이모지 반응을 CloudKit 에 별도 필드로 두지 않고 기존 Feedback.content 에 그대로 담는다.
//  운영 스키마를 건드리지 않아도 되고, 아직 업데이트하지 않은 친구의 앱에서도
//  "🎉" 가 그냥 짧은 메시지로 읽히기 때문이다(깨지지 않는다).
//  대신 "이 글이 이모지뿐인가"를 이 파일이 판정한다.
//

import Foundation

public enum FeedbackContent: Sendable {

    /// 반응 고르기 줄에 띄우는 기본 이모지.
    /// 식사 기록에 남길 만한 말들로 골랐다 — 잘했다·맛있겠다·응원.
    public static let reactionPalette: [String] = ["👍", "🔥", "😍", "👏", "🤤", "💪", "🎉", "🥲"]

    /// 반응으로 볼 이모지 개수 상한. 이보다 길면 글로 취급한다.
    /// ("👍👍👍👍👍" 같은 도배를 반응 칩으로 크게 띄우지 않기 위함)
    public static let maxReactionCount = 3

    /// 본문이 이모지로만 이뤄져 있는지 (= 반응으로 표시할지)
    public static func isReaction(_ content: String) -> Bool {
        reactionEmoji(content) != nil
    }

    /// 반응이면 다듬은 이모지 문자열, 아니면 nil
    public static func reactionEmoji(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 사이에 낀 공백은 무시한다 ("👍 🔥" 도 반응)
        let clusters = trimmed.filter { !$0.isWhitespace }
        guard !clusters.isEmpty, clusters.count <= maxReactionCount else { return nil }
        guard clusters.allSatisfy(isEmojiCluster) else { return nil }

        return String(clusters)
    }

    /// 알림·목록에 한 줄로 줄여 보여줄 요약
    public static func preview(_ content: String, limit: Int = 40) -> String {
        let trimmed = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

    /// 문자 하나(= 자소 클러스터)가 이모지인지.
    ///
    /// `isEmoji` 만 보면 안 된다 — 숫자 "1" 도 이모지 표현(1️⃣)이 가능해서 true 다.
    /// 그래서 이모지 표현이 기본값인 스칼라(`isEmojiPresentation`)이거나,
    /// 이모지로 만들어 주는 변이 선택자(FE0F)가 실제로 붙어 있을 때만 인정한다.
    private static func isEmojiCluster(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return false }
        guard first.properties.isEmoji else { return false }
        if first.properties.isEmojiPresentation { return true }
        // 예: "❤️"(2764 FE0F), "1️⃣"(0031 FE0F 20E3)
        return scalars.contains { $0.value == 0xFE0F }
    }
}
