//
//  FeedbackThreadView.swift
//  RoutineCamera
//
//  한 끼니에 달린 피드백을 대화처럼 보여 주는 공용 뷰.
//
//  예전에는 친구 식단에서 응원을 "쓰기"만 되고 다시 볼 수 없었다.
//  내가 방금 뭘 남겼는지도, 다른 친구가 뭐라 했는지도 안 보여서 한 번 쓰면 끝이었다.
//  이 뷰는 내 식단(PhotoDetailView)과 친구 식단(QuickFeedbackView 등) 양쪽에서 같이 쓴다.
//
//  이모지 반응은 위에 모아서 세고(👍 2), 글은 아래에 시간순으로 쌓는다.
//  반응인지 글인지 가르는 규칙은 RoutineCameraCore.FeedbackContent 에 있다(테스트 있음).
//

import SwiftUI
import RoutineCameraCore

// MARK: - 반응 고르기 줄

/// 이모지를 눌러 바로 반응을 남기는 줄
struct ReactionBar: View {
    /// 내가 이미 남긴 반응들 (누르면 눌린 상태로 보인다)
    var mine: Set<String> = []
    var isSending: Bool = false
    let onPick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FeedbackContent.reactionPalette, id: \.self) { emoji in
                    Button {
                        onPick(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 22))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(mine.contains(emoji)
                                          ? Color.orange.opacity(0.18)
                                          : Color(.systemGray6))
                            )
                            .overlay(
                                Circle()
                                    .stroke(mine.contains(emoji) ? Color.orange : Color.clear,
                                            lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                    .accessibilityLabel("\(emoji) 반응 남기기")
                    .accessibilityAddTraits(mine.contains(emoji) ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .opacity(isSending ? 0.5 : 1)
    }
}

// MARK: - 반응 요약 (👍 2 · 🎉 1)

/// 같은 이모지끼리 묶어 개수와 함께 보여 준다
struct ReactionSummary: View {
    let feedbacks: [MealFeedback]
    let myUserId: String

    private struct Group: Identifiable {
        let emoji: String
        let names: [String]
        let containsMine: Bool
        var id: String { emoji }
        var count: Int { names.count }
    }

    private var groups: [Group] {
        // 시간순으로 먼저 나온 이모지가 앞에 오도록 순서를 유지한다
        var order: [String] = []
        var buckets: [String: [MealFeedback]] = [:]

        for feedback in feedbacks {
            guard let emoji = FeedbackContent.reactionEmoji(feedback.content) else { continue }
            if buckets[emoji] == nil {
                buckets[emoji] = []
                order.append(emoji)
            }
            buckets[emoji]?.append(feedback)
        }

        return order.compactMap { emoji in
            guard let items = buckets[emoji] else { return nil }
            return Group(
                emoji: emoji,
                names: items.map { $0.authorId == myUserId ? "나" : $0.authorNickname },
                containsMine: items.contains { $0.authorId == myUserId }
            )
        }
    }

    var body: some View {
        let groups = self.groups
        if !groups.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(groups) { group in
                        HStack(spacing: 4) {
                            Text(group.emoji)
                                .font(.system(size: 15))
                            if group.count > 1 {
                                Text("\(group.count)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(group.containsMine
                                      ? Color.orange.opacity(0.15)
                                      : Color(.systemGray6))
                        )
                        .overlay(
                            Capsule()
                                .stroke(group.containsMine ? Color.orange.opacity(0.6) : Color.clear,
                                        lineWidth: 1)
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(group.emoji) \(group.names.joined(separator: ", "))")
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}

// MARK: - 글 하나

private struct FeedbackBubble: View {
    let feedback: MealFeedback
    let isMine: Bool

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
            HStack(spacing: 6) {
                if isMine { Spacer(minLength: 0) }
                Text(isMine ? "나" : feedback.authorNickname)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isMine ? .green : .blue)
                Text(feedback.createdAt, style: .relative)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                if !isMine && !feedback.isRead {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                }
                if !isMine { Spacer(minLength: 0) }
            }

            Text(feedback.content)
                .font(.system(size: 14))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
                .multilineTextAlignment(isMine ? .trailing : .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isMine ? Color.green.opacity(0.12) : Color.blue.opacity(0.1))
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isMine ? "내가 남긴 글" : "\(feedback.authorNickname)님의 글"): \(feedback.content)")
    }
}

// MARK: - 스레드 본체

/// 이미 불러온 피드백 목록을 그린다. 로딩은 호출하는 쪽이 맡는다.
struct FeedbackThreadView: View {
    let feedbacks: [MealFeedback]
    let myUserId: String
    var isLoading: Bool = false
    /// 불러오기에 실패했을 때 사유 (nil이면 정상)
    var errorMessage: String? = nil
    /// 아무것도 없을 때 보여 줄 문구
    var emptyText: String = "아직 남긴 응원이 없어요"

    private var messages: [MealFeedback] {
        feedbacks.filter { !FeedbackContent.isReaction($0.content) }
    }

    private var hasReactions: Bool {
        feedbacks.contains { FeedbackContent.isReaction($0.content) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isLoading && feedbacks.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("불러오는 중…")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            } else if feedbacks.isEmpty {
                Text(emptyText)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            } else {
                if hasReactions {
                    ReactionSummary(feedbacks: feedbacks, myUserId: myUserId)
                }
                if !messages.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(messages) { feedback in
                            FeedbackBubble(feedback: feedback,
                                           isMine: feedback.authorId == myUserId)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 친구 식단에 붙이는 응원 섹션 (반응 + 대화 + 쓰기)

/// 친구의 한 끼니에 대한 응원 전체 — 이모지 반응 줄, 지금까지의 대화, 글 쓰기.
///
/// 빠른 피드백 시트(`QuickFeedbackView`)와 상세 화면(`FriendMealDetailView`)이
/// 같은 것을 보여 줘야 해서 한 곳에 모았다.
@MainActor
struct FriendFeedbackSection: View {
    let friendId: String
    let date: Date
    let mealType: MealType

    @StateObject private var friendManager = FriendManager.shared
    @State private var feedbackText: String = ""
    @State private var isSubmitting = false
    @State private var feedbacks: [MealFeedback] = []
    @State private var isLoadingThread = false
    @State private var threadError: String?
    @State private var sendError: String?

    /// 내가 이미 남긴 이모지 반응 — 반응 줄에 눌린 상태로 보여 준다
    private var myReactions: Set<String> {
        Set(feedbacks
            .filter { $0.authorId == friendManager.myUserId }
            .compactMap { FeedbackContent.reactionEmoji($0.content) })
    }

    private var trimmedText: String {
        feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 이모지 반응 — 누르면 바로 전송된다
            VStack(alignment: .leading, spacing: 6) {
                Text("반응")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                ReactionBar(mine: myReactions, isSending: isSubmitting) { emoji in
                    toggleReaction(emoji)
                }
            }

            // 지금까지 오간 응원 (내가 남긴 것도 여기 보인다)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("남긴 응원")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    if isLoadingThread && !feedbacks.isEmpty {
                        ProgressView().scaleEffect(0.6)
                    }
                }

                FeedbackThreadView(
                    feedbacks: feedbacks,
                    myUserId: friendManager.myUserId,
                    isLoading: isLoadingThread,
                    errorMessage: threadError,
                    emptyText: "아직 아무도 응원을 남기지 않았어요"
                )
            }

            Divider()

            // 글로 남기기
            VStack(alignment: .leading, spacing: 8) {
                Text("응원 남기기")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextEditor(text: $feedbackText)
                    .frame(height: 110)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )

                if let sendError {
                    Label(sendError, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    send(trimmedText)
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text("보내기")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(trimmedText.isEmpty ? Color.gray : Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(trimmedText.isEmpty || isSubmitting)
            }
        }
        .task { await loadThread() }
    }

    /// 이모지는 토글이다 — 이미 남긴 걸 다시 누르면 취소된다.
    /// 그러지 않으면 한 사람이 👍 를 세 번 눌러 "👍 3" 이 되어 버린다.
    private func toggleReaction(_ emoji: String) {
        let existing = feedbacks.first {
            $0.authorId == friendManager.myUserId && FeedbackContent.reactionEmoji($0.content) == emoji
        }

        guard let existing else {
            send(emoji)
            return
        }

        isSubmitting = true
        sendError = nil
        Task {
            do {
                try await friendManager.removeMyFeedback(id: existing.id)
                await loadThread()
            } catch {
                sendError = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    /// 반응·글 모두 같은 경로로 보낸다 (둘 다 Feedback 레코드다).
    /// 보낸 뒤 화면을 닫지 않고 스레드를 다시 불러온다 — 방금 남긴 게 목록에 뜨는 걸 봐야
    /// "남겼다"가 확인된다. 예전에는 알림창만 뜨고 닫혀서 확인할 방법이 없었다.
    private func send(_ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSubmitting else { return }

        isSubmitting = true
        sendError = nil
        Task {
            do {
                try await friendManager.addFeedback(
                    to: friendId, date: date, mealType: mealType, content: trimmed
                )
                if trimmed == trimmedText { feedbackText = "" }
                await loadThread()
            } catch {
                sendError = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func loadThread() async {
        isLoadingThread = true
        threadError = nil
        do {
            feedbacks = try await friendManager.getFeedbackThread(
                ownerId: friendId, date: date, mealType: mealType
            )
        } catch {
            threadError = error.localizedDescription
        }
        isLoadingThread = false
    }
}
