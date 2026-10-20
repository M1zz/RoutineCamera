//
//  UserSafety.swift
//  RoutineCamera
//
//  친구 끊기 · 차단 · 신고. 친구 목록, 친구 기록 화면, 댓글에서 같은 흐름을 쓴다.
//  다른 사람이 올린 사진·글을 보는 앱이라, 누구든 바로 차단하고 신고할 수 있어야 한다.
//

import SwiftUI

/// 무엇을 할지 고를 대상
struct SafetyTarget: Identifiable, Equatable {
    let userId: String
    let code: String
    let name: String
    /// 신고할 때 함께 보낼 글 (댓글을 신고할 때)
    var content: String? = nil
    /// 친구 목록에서 열었으면 "친구 끊기" 도 보여 준다
    var isFriend = false

    var id: String { userId + (content ?? "") }
}

private struct UserSafetyModifier: ViewModifier {
    @Binding var target: SafetyTarget?
    @State private var reportTarget: SafetyTarget?
    @State private var blockTarget: SafetyTarget?
    @State private var resultMessage: String?

    private static let reportReasons = [
        String(localized: "스팸이나 광고"),
        String(localized: "괴롭힘이나 혐오 표현"),
        String(localized: "부적절한 사진이나 글"),
        String(localized: "기타"),
    ]

    func body(content: Content) -> some View {
        content
            // 1단계 — 무엇을 할지
            .confirmationDialog(target?.name ?? "", isPresented: present($target), titleVisibility: .visible,
                                presenting: target) { t in
                if t.isFriend {
                    Button("친구 끊기", role: .destructive) { run(t, String(localized: "\(t.name)님과 친구를 끊었어요.", comment: "Result: you unfriended this person")) {
                        try await FriendManager.shared.removeFriend(friendId: t.userId)
                    } }
                }
                // 첫 창이 닫힌 뒤에 다음 창을 띄운다 (바로 띄우면 나타나지 않는다)
                Button("차단하기", role: .destructive) { afterDismiss { blockTarget = t } }
                Button("신고하기") { afterDismiss { reportTarget = t } }
                Button("취소", role: .cancel) {}
            }
            // 차단 확인
            .confirmationDialog("\(blockTarget?.name ?? "")님을 차단할까요?", isPresented: present($blockTarget),
                                titleVisibility: .visible, presenting: blockTarget) { t in
                Button("차단하기", role: .destructive) { run(t, String(localized: "\(t.name)님을 차단했어요.", comment: "Result: you blocked this person")) {
                    try await FriendManager.shared.blockUser(id: t.userId, code: t.code, name: t.name)
                } }
                Button("취소", role: .cancel) {}
            } message: { _ in
                Text("서로 친구가 아니게 되고, 이 사람이 남긴 댓글과 반응이 보이지 않아요. 코드로 다시 추가하면 풀려요.")
            }
            // 신고 사유
            .confirmationDialog("신고 사유를 골라 주세요", isPresented: present($reportTarget),
                                titleVisibility: .visible, presenting: reportTarget) { t in
                ForEach(Self.reportReasons, id: \.self) { reason in
                    Button(reason) { run(t, String(localized: "신고했어요. 확인한 뒤 조치할게요.", comment: "Result: report sent and will be reviewed")) {
                        try await FriendManager.shared.reportUser(id: t.userId, name: t.name,
                                                                  reason: reason, content: t.content)
                    } }
                }
                Button("취소", role: .cancel) {}
            } message: { _ in
                Text("신고 내용은 개발자에게 바로 전달돼요. 상대에게는 알리지 않아요.")
            }
            .alert(resultMessage ?? "", isPresented: present($resultMessage)) {
                Button("확인", role: .cancel) {}
            }
    }

    private func run(_ t: SafetyTarget, _ success: String, _ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                resultMessage = success
            } catch {
                resultMessage = String(localized: "처리하지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.")
            }
        }
    }

    private func afterDismiss(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: action)
    }

    private func present<T>(_ binding: Binding<T?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil },
                set: { if !$0 { binding.wrappedValue = nil } })
    }
}

extension View {
    /// target 을 넣으면 끊기·차단·신고를 고르는 창이 뜬다
    func userSafetyActions(_ target: Binding<SafetyTarget?>) -> some View {
        modifier(UserSafetyModifier(target: target))
    }
}
