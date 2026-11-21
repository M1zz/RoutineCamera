//
//  AppTextDirection.swift
//  RoutineCamera
//
//  앱이 지금 쓰는 언어의 글 방향. 화면은 SwiftUI 가 저절로 뒤집지만,
//  사진에 새기는 날짜 도장 · PDF 처럼 직접 그리는 것은 이 값을 보고 오른쪽에서 왼쪽(아랍어)으로 놓는다.
//

import Foundation

nonisolated enum AppTextDirection {
    /// 앱 언어(번들이 고른 언어)가 오른쪽에서 왼쪽으로 쓰는 말인가
    static let isRightToLeft: Bool = {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale.Language(identifier: language).characterDirection == .rightToLeft
    }()
}
