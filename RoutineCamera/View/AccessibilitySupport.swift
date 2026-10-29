//
//  AccessibilitySupport.swift
//  RoutineCamera
//

import SwiftUI

// MARK: - 더 큰 텍스트

extension View {
    /// `.font(.system(size:))` 와 같은 모양이되, 설정 ▸ 손쉬운 사용 ▸ 더 큰 텍스트를 따라 함께 커진다.
    /// 기본 크기(Large)에서는 지정한 size 그대로라 디자인이 바뀌지 않는다.
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design))
    }
}

private struct ScaledSystemFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let scaled = UIFontMetrics.default.scaledValue(for: size, compatibleWith: traits)
        content.font(.system(size: scaled, weight: weight, design: design))
    }
}

// MARK: - 충분한 대비

extension Color {
    /// 흰 글자를 얹는 초록·주황 바탕. 시스템 초록·주황은 흰 글자와 대비가 2:1 남짓이라 한 톤 깊게 쓴다.
    static let solidGreen = Color(red: 0.14, green: 0.54, blue: 0.24)
    static let solidOrange = Color(red: 0.75, green: 0.33, blue: 0.0)
}
