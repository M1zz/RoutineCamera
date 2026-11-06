//
//  MealThumbnail.swift
//  RoutineCamera
//
//  기록 사진을 칸 크기로 작게 풀어 보여 준다.
//  예전에는 칸마다 body 안에서 JPEG 를 메인에서 풀었다. 기록이 하나만 바뀌어도 보이는 칸이
//  전부 다시 그려지며 사진을 다시 풀어 스크롤과 화면 전환이 버벅였다.
//  이제 푸는 일은 메인 밖에서 한 번만 하고, 푼 그림은 기억해 둔다.
//

import SwiftUI

struct MealThumbnail<Placeholder: View>: View {
    private let data: Data
    private let maxPixel: CGFloat
    private let key: NSString
    private let placeholder: Placeholder
    @State private var image: UIImage?

    /// - Parameter id: 사진의 주인(기록 id 등). 같은 id·같은 크기의 사진이면 이미 푼 그림을 다시 쓴다.
    init(id: some CustomStringConvertible, data: Data, maxPixel: CGFloat,
         @ViewBuilder placeholder: () -> Placeholder) {
        self.data = data
        self.maxPixel = maxPixel
        self.key = "\(id)-\(data.count)-\(Int(maxPixel))" as NSString
        self.placeholder = placeholder()
        // 이미 푼 적이 있으면 첫 화면부터 바로 보인다 (스크롤해 돌아올 때 깜빡이지 않게)
        _image = State(initialValue: MealThumbnailCache.shared.object(forKey: key))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: key) { await load() }
    }

    private func load() async {
        if let cached = MealThumbnailCache.shared.object(forKey: key) {
            image = cached
            return
        }
        let (data, maxPixel) = (data, maxPixel)
        let decoded = await Task.detached(priority: .userInitiated) {
            MealImageResizer.downsampledImage(from: data, maxPixel: maxPixel)
        }.value
        guard !Task.isCancelled else { return }
        if let decoded {
            MealThumbnailCache.shared.setObject(decoded, forKey: key, cost: decoded.pixelBytes)
        }
        image = decoded
    }
}

/// 푼 썸네일을 기억해 둔다. 메모리가 모자라면 시스템이 알아서 비운다.
private enum MealThumbnailCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 80 * 1024 * 1024
        return cache
    }()
}

private extension UIImage {
    var pixelBytes: Int {
        guard let cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
