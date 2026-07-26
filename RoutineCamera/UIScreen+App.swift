//
//  UIScreen+App.swift
//  RoutineCamera
//
//  iOS 26에서 deprecated된 UIScreen.main 대체 — 현재 연결된 윈도우 씬의 화면 너비.
//

import UIKit

extension UIScreen {
    /// 현재 활성 윈도우 씬의 화면 너비 (UIScreen.main deprecated 대체). 없으면 기본값 393.
    static var appWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width ?? 393
    }
}
