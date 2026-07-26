//
//  FoodTagsView.swift
//  RoutineCamera
//

import SwiftUI
import AVFoundation
import Photos

struct FoodTagsView: View {
    let foodItems: [String]
    let description: String?
    @Binding var showFullAnalysis: Bool

    private let maxPreviewTags = 5 // 미리보기에 표시할 최대 태그 수

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 음식 태그 (칩 형태)
            let tagsToShow = showFullAnalysis ? foodItems : Array(foodItems.prefix(maxPreviewTags))

            FlowLayout(spacing: 6) {
                ForEach(tagsToShow, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 14))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                }
            }

            // 설명 (있을 경우)
            if let desc = description, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(showFullAnalysis ? nil : 2)
            }

            // 전체보기/접기 버튼
            if foodItems.count > maxPreviewTags || (description != nil && !description!.isEmpty) {
                Button(action: {
                    withAnimation {
                        showFullAnalysis.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(showFullAnalysis ? "접기" : "전체보기")
                            .font(.system(size: 13))
                        Image(systemName: showFullAnalysis ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
        }
    }
}

// Flow Layout (태그를 자동으로 줄바꿈하는 레이아웃)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let subviewSize = subview.sizeThatFits(.unspecified)

                if x + subviewSize.width > maxWidth && x > 0 {
                    // 다음 줄로 넘어감
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, subviewSize.height)
                x += subviewSize.width + spacing
            }

            size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

#Preview {
    ContentView()
}

