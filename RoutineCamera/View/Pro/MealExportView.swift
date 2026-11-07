//
//  MealExportView.swift
//  RoutineCamera
//
//  세끼 프로 — 기간을 골라 기록을 밖으로 꺼낸다.
//  PDF: 사진 · 시각 · 메모 · 찍은 곳을 날짜별로 (영양사 · 트레이너에게 보내기).
//  사진 한꺼번에 저장: 그동안 찍은 사진을 사진앱 앨범에 한 번에.
//

import SwiftUI
import CoreLocation
import RoutineCameraCore

struct MealExportView: View {
    enum Kind { case pdf, photos }

    let kind: Kind
    @ObservedObject var mealStore: MealRecordStore
    @State private var period: MealPeriod = .lastWeek
    @State private var isWorking = false
    @State private var progress = 0
    @State private var pdfURL: URL?
    @State private var resultMessage: String?

    private var records: [MealRecord] { mealStore.records.completed(in: period.interval()) }

    var body: some View {
        let records = records
        let photoCount = records.reduce(0) { $0 + $1.photos.count }
        Form {
            Section {
                Picker("기간", selection: $period) {
                    ForEach(MealPeriod.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent(String(localized: "담길 기록", comment: "Export: label for what the chosen period includes"), value: String(localized: "\(records.count)끼 · 사진 \(photoCount)장",
                                                   comment: "Export: meals and photos in the chosen period"))
            } footer: {
                Text(kind == .pdf
                     ? "사진, 시각, 메모, 찍은 곳을 날짜별로 정리한 PDF를 만들어요."
                     : "고른 기간의 사진을 사진앱 '\(SettingsManager.shared.albumType.photoAlbumName)' 앨범에 저장해요.")
            }

            Section {
                switch kind {
                case .pdf:
                    if let pdfURL {
                        ShareLink(item: pdfURL) { Label("PDF 보내기", systemImage: "square.and.arrow.up") }
                    } else {
                        actionButton("PDF 만들기", systemImage: "doc.richtext", disabled: records.isEmpty) {
                            await makePDF(records)
                        }
                    }
                case .photos:
                    actionButton("사진앱에 저장", systemImage: "square.and.arrow.down.on.square", disabled: photoCount == 0) {
                        await savePhotos(records, total: photoCount)
                    }
                }
            } footer: {
                if isWorking, kind == .photos {
                    Text("\(progress) / \(photoCount)장 저장 중…", comment: "Export: bulk save progress")
                } else if let resultMessage {
                    Text(resultMessage)
                }
            }
        }
        .navigationTitle(kind == .pdf ? "PDF로 내보내기" : "사진 한꺼번에 저장")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: period) { _, _ in
            pdfURL = nil
            resultMessage = nil
        }
    }

    private func actionButton(_ title: LocalizedStringKey, systemImage: String, disabled: Bool,
                              action: @escaping () async -> Void) -> some View {
        Button {
            Task {
                isWorking = true
                await action()
                isWorking = false
            }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                if isWorking {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(disabled || isWorking)
    }

    // MARK: - PDF

    private func makePDF(_ records: [MealRecord]) async {
        let entries = records.map { record in
            MealPDFEntry(date: record.sortDate,
                         title: record.mealType.displayName,
                         memo: record.memo.flatMap { $0.isEmpty ? nil : $0 },
                         place: record.place?.name,
                         note: record.photos.isEmpty
                            ? (record.ateAll ? String(localized: "다 먹음")
                               : String(localized: "friend.loggedNoPhoto", defaultValue: "사진 없이 기록", comment: "Friend status: logged a meal without a photo"))
                            : nil,
                         photos: record.photos)
        }
        let header = MealPDFHeader(
            title: String(localized: "세끼 식사 기록", comment: "PDF export title"),
            subtitle: "\(period.title) · " + String(localized: "\(records.count)끼 · 사진 \(entries.reduce(0) { $0 + $1.photos.count })장",
                                                   comment: "Export: meals and photos in the chosen period")
        )
        let fileName = String(localized: "세끼 기록", comment: "PDF export file name") + " " + Date().formatted(.iso8601.year().month().day()) + ".pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let made = await Task.detached(priority: .userInitiated) {
            (try? MealPDFRenderer.render(header: header, entries: entries, to: url)) != nil
        }.value
        if made {
            pdfURL = url
            resultMessage = nil
        } else {
            resultMessage = String(localized: "PDF를 만들지 못했어요. 다시 시도해 주세요.")
        }
    }

    // MARK: - 사진 한꺼번에 저장

    private func savePhotos(_ records: [MealRecord], total: Int) async {
        progress = 0
        resultMessage = nil
        let album = SettingsManager.shared.albumType.photoAlbumName
        var saved = 0
        for record in records {
            let location = record.place.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
            for data in record.photos {
                // 풀지 않고 저장해 둔 JPEG 그대로 넣는다 (몇백 장이어도 메모리가 늘지 않는다)
                let ok = await withCheckedContinuation { continuation in
                    MealAlbumSaver.save(data, toAlbum: album, location: location) { continuation.resume(returning: $0) }
                }
                progress += 1
                if ok {
                    saved += 1
                } else if saved == 0 {
                    // 첫 장부터 실패하면 권한이 없는 것이다 — 나머지도 실패하니 멈춘다
                    resultMessage = String(localized: "사진앱에 저장하지 못했어요. 설정 앱에서 사진 접근을 허용해 주세요.")
                    return
                }
            }
        }
        resultMessage = String(localized: "\(saved)장을 '\(album)' 앨범에 저장했어요.", comment: "Export: bulk save finished (count, album)")
    }
}

// MARK: - PDF 그리기 (메인 밖에서 돈다)

nonisolated struct MealPDFHeader: Sendable {
    let title: String
    let subtitle: String
}

nonisolated struct MealPDFEntry: Sendable {
    let date: Date
    let title: String
    let memo: String?
    let place: String?
    /// 사진이 없을 때 대신 쓰는 말 ("다 먹음" 등)
    let note: String?
    let photos: [Data]
}

nonisolated enum MealPDFRenderer {
    private static let page = CGRect(x: 0, y: 0, width: 595, height: 842)   // A4
    private static let margin: CGFloat = 40
    private static let photoSide: CGFloat = 96
    private static let rowHeight: CGFloat = photoSide + 16

    static func render(header: MealPDFHeader, entries: [MealPDFEntry], to url: URL) throws {
        let dayFormatter = DateFormatter()
        dayFormatter.setLocalizedDateFormatFromTemplate("yMMMdEEEE")
        let timeFormatter = DateFormatter()
        timeFormatter.setLocalizedDateFormatFromTemplate("jmm")
        let calendar = Calendar.current

        let renderer = UIGraphicsPDFRenderer(bounds: page)
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            var y = margin
            y = draw(header.title, font: .boldSystemFont(ofSize: 22), at: y)
            y = draw(header.subtitle, font: .systemFont(ofSize: 12), color: .gray, at: y) + 12

            var currentDay: Date?
            for entry in entries {
                let day = calendar.startOfDay(for: entry.date)
                let needsDayHeader = day != currentDay
                let needed = rowHeight + (needsDayHeader ? 34 : 0)
                if y + needed > page.height - margin {
                    context.beginPage()
                    y = margin
                }
                if needsDayHeader {
                    currentDay = day
                    y = draw(dayFormatter.string(from: day), font: .boldSystemFont(ofSize: 15), at: y + 8) + 6
                }
                drawRow(entry, time: timeFormatter.string(from: entry.date), at: y, in: context.cgContext)
                y += rowHeight
            }
        }
    }

    @discardableResult
    private static func draw(_ text: String, font: UIFont, color: UIColor = .black, at y: CGFloat) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let width = page.width - margin * 2
        let height = ceil(attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                  options: [.usesLineFragmentOrigin], context: nil).height)
        attributed.draw(with: CGRect(x: margin, y: y, width: width, height: height), options: [.usesLineFragmentOrigin], context: nil)
        return y + height
    }

    private static func drawRow(_ entry: MealPDFEntry, time: String, at y: CGFloat, in cg: CGContext) {
        var x = margin
        for data in entry.photos.prefix(2) {
            let rect = CGRect(x: x, y: y, width: photoSide, height: photoSide)
            if let image = MealImageResizer.downsampledImage(from: data, maxPixel: photoSide * 3) {
                cg.saveGState()
                UIBezierPath(roundedRect: rect, cornerRadius: 8).addClip()
                // 가운데를 채워 그린다 (정사각형 칸)
                let scale = max(rect.width / image.size.width, rect.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                      width: size.width, height: size.height))
                cg.restoreGState()
            }
            x += photoSide + 8
        }
        if entry.photos.isEmpty { x = margin }

        let textWidth = page.width - margin - x
        let text = NSMutableAttributedString(string: "\(entry.title)  \(time)\n",
                                             attributes: [.font: UIFont.boldSystemFont(ofSize: 13), .foregroundColor: UIColor.black])
        let detail: [String] = [entry.note, entry.place.map { "📍 \($0)" }, entry.memo].compactMap { $0 }
        if !detail.isEmpty {
            text.append(NSAttributedString(string: detail.joined(separator: "\n"),
                                           attributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkGray]))
        }
        text.draw(with: CGRect(x: x, y: y, width: textWidth, height: photoSide),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)

        // 줄 사이 구분선
        cg.setStrokeColor(UIColor(white: 0.9, alpha: 1).cgColor)
        cg.setLineWidth(0.5)
        cg.move(to: CGPoint(x: margin, y: y + photoSide + 8))
        cg.addLine(to: CGPoint(x: page.width - margin, y: y + photoSide + 8))
        cg.strokePath()
    }
}
