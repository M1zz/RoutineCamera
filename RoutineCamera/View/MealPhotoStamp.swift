//
//  MealPhotoStamp.swift
//  RoutineCamera
//
//  사진 왼쪽 아래에 새기는 날짜·시간 "도장".
//  예전에는 카메라 화면 안에서 지금 시각을 굵은 기본 글꼴로만 새겼다. 사용자 피드백
//  "기록 날짜 · 시간을 (글꼴 포함) 편집하고 싶다"(2026-11-09) 로
//  - 찍을 때 고른 "먹은 시각" 으로 새기고
//  - 글꼴 · 시간 표시 · 켜고 끄기를 설정에서 고르며
//  - 찍은 뒤에도 날짜 · 시각 · 글꼴을 바꿔 다시 새길 수 있게 한다.
//
//  다시 새기려면 도장 아래 가려진 원본이 필요하다. 사진 전체를 한 장 더 두면 저장 공간이 두 배라,
//  도장이 들어가는 **아래쪽 띠(30%)** 만 깨끗한 원본으로 따로 남긴다 (MealStampBackingStore).
//  띠의 위쪽 경계를 16px 단위에 맞춰 두 JPEG 의 블록이 같은 자리에 놓이게 해, 다시 붙여도 이음새가 보이지 않는다.
//  예전 버전에서 찍은 사진은 띠가 없어 사진에 새긴 글자는 그대로 두고 기록의 날짜 · 시각만 바뀐다.
//

import SwiftUI
import UIKit
import os

// MARK: - 글꼴

/// 도장 글꼴. rawValue 는 저장값이라 바꾸지 않는다.
nonisolated enum MealStampFont: String, CaseIterable, Identifiable {
    /// 예전부터 쓰던 굵은 기본 글꼴 — 기본값이라 기존 사용자의 사진은 그대로다
    case system
    case rounded
    case serif
    case monospaced
    case handwriting
    case chalk

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return String(localized: "기본", comment: "Photo date stamp font: the default bold system font")
        case .rounded: return String(localized: "둥근", comment: "Photo date stamp font: rounded")
        case .serif: return String(localized: "명조", comment: "Photo date stamp font: serif")
        case .monospaced: return String(localized: "고정폭", comment: "Photo date stamp font: monospaced")
        case .handwriting: return String(localized: "손글씨", comment: "Photo date stamp font: handwriting style")
        case .chalk: return String(localized: "분필", comment: "Photo date stamp font: chalk style")
        }
    }

    /// 사진에 새길 때 쓰는 UIKit 글꼴. 기기에 없는 글꼴이면 기본 굵은 글꼴로 대신한다.
    func uiFont(size: CGFloat) -> UIFont {
        let bold = UIFont.boldSystemFont(ofSize: size)
        switch self {
        case .system:
            return bold
        case .rounded, .serif, .monospaced:
            let design: UIFontDescriptor.SystemDesign = self == .rounded ? .rounded : (self == .serif ? .serif : .monospaced)
            guard let descriptor = bold.fontDescriptor.withDesign(design) else { return bold }
            return UIFont(descriptor: descriptor, size: size)
        case .handwriting:
            return UIFont(name: "Noteworthy-Bold", size: size) ?? bold
        case .chalk:
            return UIFont(name: "ChalkboardSE-Bold", size: size) ?? bold
        }
    }

    /// 카메라 미리보기 · 설정 미리보기에서 같은 모양으로 보여 주기 위한 SwiftUI 글꼴
    func font(size: CGFloat) -> Font {
        switch self {
        case .system: return .system(size: size, weight: .bold)
        case .rounded: return .system(size: size, weight: .bold, design: .rounded)
        case .serif: return .system(size: size, weight: .bold, design: .serif)
        case .monospaced: return .system(size: size, weight: .bold, design: .monospaced)
        case .handwriting, .chalk: return Font(uiFont(size: size))
        }
    }
}

extension MealStampFont: StoredValue {}

// MARK: - 모양 설정

/// 도장을 어떻게 새길지. 설정 화면의 세 값을 한 번에 들고 다닌다.
nonisolated struct MealStampStyle: Equatable {
    var isEnabled: Bool
    var font: MealStampFont
    var showsTime: Bool

    /// 지금 설정값
    @MainActor static var current: MealStampStyle {
        let settings = SettingsManager.shared
        return MealStampStyle(isEnabled: settings.photoStampEnabled, font: settings.photoStampFont,
                              showsTime: settings.photoStampShowsTime)
    }
}

// MARK: - 새기기

nonisolated enum MealPhotoStamp {
    /// 다시 새길 때 덮는 아래쪽 띠의 높이 (사진 높이 대비). 여백 8% + 두 줄(각 약 7%) 이 넉넉히 들어간다
    static let backingFraction: CGFloat = 0.3
    /// JPEG 블록(4:2:0 이면 16px) 경계에 맞춘다 — 띠를 다시 붙여도 이음새가 생기지 않게
    private static let blockAlignment: CGFloat = 16
    /// 기록 사진의 JPEG 품질 (CameraPickerView 가 저장할 때와 같다)
    static let jpegQuality: CGFloat = 0.8

    /// 도장에 적을 두 줄. 시간을 끄면 time 은 nil.
    /// - Parameter includeSeconds: 카메라 화면처럼 흐르는 "지금" 을 보여 줄 때만 초를 붙인다 (예전과 같은 모양)
    static func lines(for date: Date, style: MealStampStyle, includeSeconds: Bool) -> (date: String, time: String?) {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMMdEEEE")
        let dateString = formatter.string(from: date)
        guard style.showsTime else { return (dateString, nil) }
        formatter.setLocalizedDateFormatFromTemplate(includeSeconds ? "jmmss" : "jmm")
        return (dateString, formatter.string(from: date))
    }

    /// 깨끗한 사진에 날짜 · 시간을 새긴다. 도장이 꺼져 있으면 그대로 돌려준다.
    static func apply(to image: UIImage, date: Date, style: MealStampStyle, includeSeconds: Bool = false) -> UIImage {
        guard style.isEnabled else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            draw(on: context.cgContext, size: image.size, date: date, style: style, includeSeconds: includeSeconds)
        }
    }

    /// 다시 새기기 위해 남겨 두는 띠 — 깨끗한 원본의 아래쪽 30% 를 JPEG 로
    static func backing(of clean: UIImage) -> Data? {
        let rect = backingRect(for: clean.size, scale: clean.scale)
        guard rect.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = clean.scale
        format.opaque = true
        let band = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            clean.draw(at: CGPoint(x: 0, y: -rect.minY))
        }
        return band.jpegData(compressionQuality: jpegQuality)
    }

    /// 이미 새겨진 사진에 띠를 덮고 새 날짜 · 글꼴로 다시 새긴다. 도장이 꺼져 있으면 글자 없이 띠만 덮는다(도장이 지워진다).
    static func restamp(stamped: Data, backing: Data, date: Date, style: MealStampStyle) -> Data? {
        guard let image = UIImage(data: stamped), let band = UIImage(data: backing) else { return nil }
        return restamp(stamped: image, backing: band, date: date, style: style).jpegData(compressionQuality: jpegQuality)
    }

    /// 미리보기용 — 줄인 사진과 줄인 띠로도 같은 자리에 그린다
    static func restamp(stamped image: UIImage, backing band: UIImage, date: Date, style: MealStampStyle) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            // 띠는 아래쪽에 맞춰 폭에 맞게 그린다 (미리보기처럼 둘의 크기가 달라도 자리가 같다)
            let bandHeight = band.size.height * (image.size.width / band.size.width)
            band.draw(in: CGRect(x: 0, y: image.size.height - bandHeight, width: image.size.width, height: bandHeight))
            if style.isEnabled {
                draw(on: context.cgContext, size: image.size, date: date, style: style, includeSeconds: false)
            }
        }
    }

    // MARK: 내부

    /// 띠의 자리 (포인트). 위쪽 경계가 픽셀로 16 의 배수가 되게 한다
    private static func backingRect(for size: CGSize, scale: CGFloat) -> CGRect {
        let heightPixels = size.height * scale
        var topPixels = (heightPixels * (1 - backingFraction)).rounded(.down)
        topPixels -= topPixels.truncatingRemainder(dividingBy: blockAlignment)
        let top = topPixels / scale
        return CGRect(x: 0, y: top, width: size.width, height: size.height - top)
    }

    /// 왼쪽 아래에 흰 글자 + 검은 그림자. 자리 · 크기 · 그림자는 예전 코드와 같아 기존 사진과 모양이 같다
    private static func draw(on context: CGContext, size: CGSize, date: Date, style: MealStampStyle, includeSeconds: Bool) {
        let text = lines(for: date, style: style, includeSeconds: includeSeconds)
        let fontSize = min(size.width, size.height) * 0.06
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white,
            .font: style.font.uiFont(size: fontSize)
        ]
        let margin = min(size.width, size.height) * 0.08
        let lineSpacing: CGFloat = 6

        context.setShadow(offset: .zero, blur: 3, color: UIColor.black.cgColor)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        var bottom = size.height - margin
        if let time = text.time {
            let timeSize = time.size(withAttributes: attributes)
            time.draw(in: CGRect(x: margin, y: bottom - timeSize.height, width: timeSize.width, height: timeSize.height),
                      withAttributes: attributes)
            bottom -= timeSize.height + lineSpacing
        }
        let dateSize = text.date.size(withAttributes: attributes)
        text.date.draw(in: CGRect(x: margin, y: bottom - dateSize.height, width: dateSize.width, height: dateSize.height),
                       withAttributes: attributes)
    }
}

// MARK: - 원본 띠 보관

/// 카메라로 찍은 사진의 "도장 아래 원본 띠" 를 기록 id 별 파일로 둔다.
/// 사진 파일 폴더와 따로 두어 기록 저장이 파일을 정리할 때 휩쓸리지 않는다. iCloud 에는 올리지 않는다
/// (CloudKit 스키마에 필드를 더해야 해서, 복원한 기기에서는 다시 새기기만 안 된다).
nonisolated final class MealStampBackingStore: @unchecked Sendable {
    static let shared = MealStampBackingStore()

    private let directory: URL?
    private let queue = DispatchQueue(label: "com.ysoup.RoutineCamera.stamp-backing", qos: .utility)

    private init() {
        let fileManager = FileManager.default
        let base = fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        directory = base?.appendingPathComponent("MealImages", isDirectory: true)
            .appendingPathComponent("StampBacking", isDirectory: true)
    }

    private func url(for recordID: UUID, kind: String) -> URL? {
        directory?.appendingPathComponent("\(recordID.uuidString)_\(kind).jpg")
    }

    /// 이 사진을 다시 새길 수 있는지 (띠가 남아 있는지)
    func exists(for recordID: UUID, kind: String) -> Bool {
        guard let url = url(for: recordID, kind: kind) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func load(for recordID: UUID, kind: String) -> Data? {
        guard let url = url(for: recordID, kind: kind) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    /// 띠를 쓴다. nil 이면 지운다 — 사진이 (앨범 사진 등으로) 바뀌었으면 옛 띠를 붙이면 안 되므로 꼭 지운다
    func save(_ data: Data?, for recordID: UUID, kind: String) {
        guard let url = url(for: recordID, kind: kind) else { return }
        queue.async {
            do {
                if let data {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: url, options: .atomic)
                } else if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            } catch {
                Log.store.error("도장 원본 띠 저장 실패: \(String(describing: error))")
            }
        }
    }

    /// 기록을 지울 때 식전 · 식후 띠를 함께 지운다
    func remove(for recordID: UUID) {
        for kind in ["before", "after"] { save(nil, for: recordID, kind: kind) }
    }

    /// 어느 기록도 가리키지 않는 띠를 정리한다 (앱을 켤 때 한 번)
    func prune(keeping recordIDs: Set<UUID>) {
        guard let directory else { return }
        queue.async {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
            var removed = 0
            for name in names {
                let idPart = name.split(separator: "_").first.map(String.init) ?? ""
                guard let id = UUID(uuidString: idPart), !recordIDs.contains(id) else { continue }
                if (try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))) != nil { removed += 1 }
            }
            if removed > 0 { Log.store.info("기록에서 빠진 도장 원본 띠 \(removed)개 정리") }
        }
    }
}

// MARK: - 미리보기

/// 설정 · 날짜 편집 화면에서 도장이 어떻게 보일지 — 사진 대신 따뜻한 바탕 위에 같은 글꼴 · 자리로 그린다
struct MealStampPreview: View {
    var style: MealStampStyle
    var date: Date = Date()

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let text = MealPhotoStamp.lines(for: date, style: style, includeSeconds: false)
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(red: 0.96, green: 0.70, blue: 0.42), Color(red: 0.62, green: 0.36, blue: 0.20)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if style.isEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text.date)
                        if let time = text.time { Text(time) }
                    }
                    .font(style.font.font(size: max(side * 0.06, 12)))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 3)
                    .shadow(color: .black, radius: 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(side * 0.08)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(previewLabel)
    }

    private var previewLabel: Text {
        guard style.isEnabled else {
            return Text("날짜 도장 없음", comment: "Accessibility label of the stamp preview when stamping is turned off")
        }
        let text = MealPhotoStamp.lines(for: date, style: style, includeSeconds: false)
        return Text(verbatim: "\(text.date) \(text.time ?? "")")
    }
}
