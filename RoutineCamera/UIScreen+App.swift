//
//  UIScreen+App.swift
//  RoutineCamera
//
//  iOS 26에서 deprecated된 UIScreen.main 대체 — 현재 연결된 윈도우 씬의 화면 너비.
//

import UIKit
import LeeoKit

extension UIScreen {
    /// 현재 활성 윈도우 씬의 화면 너비 (UIScreen.main deprecated 대체). 없으면 기본값 393.
    static var appWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width ?? 393
    }
}

extension FoldLayout {
    /// 목록 칸 크기를 잴 폭. 접혀 있으면 지금처럼 화면 폭, 아이폰 듀오를 폈으면 고르는 쪽 판 폭.
    /// 가로로 폈을 때 화면 폭으로 재면 칸이 접힌 선을 넘는다.
    var appWidth: CGFloat {
        isUnfolded ? choosePaneSize.width : UIScreen.appWidth
    }
}
