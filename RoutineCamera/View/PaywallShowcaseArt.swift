//
//  PaywallShowcaseArt.swift
//  RoutineCamera
//
//  페이월에서 옆으로 넘겨 보는 기능 그림 (LeeoKit `LeeoShowcase`).
//  스크린샷 대신 SwiftUI 로 그 기능이 적용된 화면을 줄여 그린다. 언어 · 다크 모드를 따라가고 용량이 들지 않는다.
//  장의 id 는 기능 키(`ProFeature.rawValue`)라 페이월이 고른 등급(플러스 · 프로)의 장만 보인다.
//  ⚠️ 그림 속 글자는 숫자 · 기호만. 문장은 그림 아래 한 줄(`leeoTitle` · `leeoDetail`)이 맡는다.
//

import SwiftUI
import LeeoKit

extension ProFeature {
    /// 페이월이 넘겨 볼 장. 막힌 기능(lead)이 있으면 그 장을 맨 앞에.
    static func showcases(leading lead: ProFeature?) -> [LeeoShowcase] {
        var all = plusFeatures + proFeatures
        if let lead, let i = all.firstIndex(of: lead) { all.insert(all.remove(at: i), at: 0) }
        return all.map { feature in
            LeeoShowcase(id: feature.rawValue, title: feature.leeoTitle, detail: feature.leeoDetail) { feature.art }
        }
    }

    @ViewBuilder
    fileprivate var art: some View {
        switch self {
        case .groupCreate:  GroupsArt()
        case .insights:     InsightsArt()
        case .appLock:      AppLockArt()
        case .habitHistory: HabitHistoryArt()
        case .customStamps: CustomStampsArt()
        case .mealMap:      MealMapArt()
        case .weeklyReport: WeeklyReportArt()
        case .pdfExport:    PDFExportArt()
        case .bulkSave:     BulkSaveArt()
        }
    }
}

// MARK: - 조각

/// 그림 속 밥 사진 한 칸 — 따뜻한 색 바탕에 숟가락 · 포크
private struct ArtMealTile: View {
    var hue: Double = 0.08
    var size: CGFloat = 54
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.95),
                                          Color(hue: hue + 0.04, saturation: 0.7, brightness: 0.8)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay { Image(systemName: "fork.knife").font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(.white.opacity(0.9)) }
    }
}

private struct ArtCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(12)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

// MARK: - 플러스

/// 그룹 여러 개: 그룹 카드마다 얼굴들
private struct GroupsArt: View {
    private let groups: [(Color, Int)] = [(.orange, 3), (.green, 4), (.blue, 2)]
    var body: some View {
        VStack(spacing: 8) {
            ForEach(groups.indices, id: \.self) { i in
                ArtCard {
                    HStack(spacing: -8) {
                        ForEach(0..<groups[i].1, id: \.self) { _ in
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                                .foregroundStyle(groups[i].0)
                                .background(Circle().fill(Color(uiColor: .systemBackground)))
                        }
                        Spacer()
                        ArtMealTile(hue: Double(i) * 0.1 + 0.05, size: 30)
                    }
                }
            }
        }
        .padding(16)
    }
}

/// 자세한 통계: 한 주의 막대와 자주 먹은 것
private struct InsightsArt: View {
    private let bars: [CGFloat] = [0.5, 0.8, 0.65, 1, 0.7, 0.9, 0.55]
    var body: some View {
        ArtCard {
            VStack(spacing: 12) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(bars.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(i == 3 ? Color.orange : Color.orange.opacity(0.35))
                            .frame(width: 18, height: 90 * bars[i])
                    }
                }
                .frame(height: 90, alignment: .bottom)
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        ArtMealTile(hue: 0.05 + Double(i) * 0.12, size: 34)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.headline.weight(.bold)).foregroundStyle(.green)
                }
            }
        }
        .padding(16)
    }
}

/// Face ID 잠금
private struct AppLockArt: View {
    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in ArtMealTile(hue: 0.06 + Double(i) * 0.1, size: 64) }
            }
            .blur(radius: 6)
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 96, height: 96)
                Image(systemName: "faceid").font(.system(size: 48)).foregroundStyle(Color.accentColor)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "lock.fill").font(.headline).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(Color.green, in: Circle()).offset(x: 8, y: 8)
            }
        }
        .padding(16)
    }
}

/// 지난 달력 · 스탬프 기록: 달력 칸마다 스탬프
private struct HabitHistoryArt: View {
    private let stamped: Set<Int> = [1, 2, 3, 5, 6, 8, 9, 10, 11, 13, 15, 16, 17, 18, 19, 22, 23, 24, 26, 27]
    var body: some View {
        ArtCard {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(1...28, id: \.self) { day in
                    ZStack {
                        Circle().fill(stamped.contains(day) ? Color.orange.opacity(0.85) : Color.secondary.opacity(0.12))
                        if stamped.contains(day) {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                        } else {
                            Text(verbatim: "\(day)").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 24)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Text(verbatim: "20").font(.headline.weight(.heavy)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4).background(Color.orange, in: Capsule()).offset(x: 6, y: -10)
        }
        .padding(20)
    }
}

/// 나만의 스탬프: 여러 색 도장
private struct CustomStampsArt: View {
    private let stamps: [(String, Color)] = [("leaf.fill", .green), ("flame.fill", .red), ("drop.fill", .blue),
                                             ("star.fill", .yellow), ("heart.fill", .pink), ("moon.fill", .purple)]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
            ForEach(stamps.indices, id: \.self) { i in
                ZStack {
                    Image(systemName: "seal.fill").font(.system(size: 58)).foregroundStyle(stamps[i].1.opacity(0.85))
                    Image(systemName: stamps[i].0).font(.title2.weight(.bold)).foregroundStyle(.white)
                }
                .rotationEffect(.degrees(Double(i % 3 - 1) * 8))
            }
        }
        .padding(20)
    }
}

// MARK: - 프로

/// 밥 지도: 지도 위에 찍은 곳마다 핀
private struct MealMapArt: View {
    private let pins: [CGPoint] = [CGPoint(x: 0.25, y: 0.35), CGPoint(x: 0.6, y: 0.25), CGPoint(x: 0.45, y: 0.65), CGPoint(x: 0.78, y: 0.6)]
    var body: some View {
        GeometryReader { g in
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.green.opacity(0.12))
                Path { p in
                    p.move(to: CGPoint(x: 0, y: g.size.height * 0.5)); p.addLine(to: CGPoint(x: g.size.width, y: g.size.height * 0.42))
                    p.move(to: CGPoint(x: g.size.width * 0.35, y: 0)); p.addLine(to: CGPoint(x: g.size.width * 0.52, y: g.size.height))
                }
                .stroke(Color.secondary.opacity(0.3), lineWidth: 8)
                ForEach(pins.indices, id: \.self) { i in
                    VStack(spacing: 0) {
                        ArtMealTile(hue: 0.05 + Double(i) * 0.09, size: 36)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 2))
                        Image(systemName: "triangle.fill").font(.system(size: 9)).foregroundStyle(.white).rotationEffect(.degrees(180)).offset(y: -2)
                    }
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                    .position(x: g.size.width * pins[i].x, y: g.size.height * pins[i].y)
                }
            }
        }
        .padding(16)
    }
}

/// 주간 리포트: 지난 주가 한 장으로, 월요일 알림
private struct WeeklyReportArt: View {
    var body: some View {
        ArtCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(.orange)
                    Capsule().fill(Color.primary.opacity(0.7)).frame(width: 80, height: 8)
                    Spacer()
                    Image(systemName: "bell.badge.fill").foregroundStyle(.red)
                }
                HStack(spacing: 5) {
                    ForEach(0..<7, id: \.self) { i in ArtMealTile(hue: 0.03 + Double(i) * 0.05, size: 32) }
                }
                HStack(spacing: 6) {
                    Capsule().fill(Color.orange).frame(width: 120, height: 8)
                    Capsule().fill(Color.secondary.opacity(0.3)).frame(width: 60, height: 8)
                }
            }
        }
        .padding(16)
    }
}

/// PDF 내보내기: 기록이 문서 한 장으로
private struct PDFExportArt: View {
    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: 6) {
                        ArtMealTile(hue: 0.05 + Double(i) * 0.1, size: 26)
                        Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 60, height: 6)
                    }
                }
            }
            .padding(12)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
            .overlay(alignment: .topTrailing) {
                Text(verbatim: "PDF").font(.caption.weight(.heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(Color.red, in: Capsule()).offset(x: 10, y: -10)
            }
            Image(systemName: "square.and.arrow.up").font(.title.weight(.semibold)).foregroundStyle(Color.accentColor)
        }
        .padding(16)
    }
}

/// 한꺼번에 저장: 사진 여러 장이 사진 앱으로
private struct BulkSaveArt: View {
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    ArtMealTile(hue: 0.04 + Double(i) * 0.08, size: 70)
                        .rotationEffect(.degrees(Double(i - 2) * 7))
                        .offset(x: CGFloat(i) * 6, y: CGFloat(i) * -4)
                        .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
                }
            }
            Image(systemName: "arrow.right").font(.title2.weight(.bold)).foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .frame(width: 76, height: 76)
                .overlay { Image(systemName: "photo.on.rectangle.angled").font(.system(size: 34)).foregroundStyle(.orange) }
                .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
        }
        .padding(16)
    }
}
