//
//  SekkiWidget.swift
//  SekkiWidget (위젯 익스텐션 타깃)
//
//  홈 화면/잠금화면 위젯 — "오늘 N개 기록" + 앱 안 열고 "다 먹음" 원탭(인터랙티브 버튼).
//  오늘 식전만 찍어둔 끼니가 있으면 "○○ 먹는 중"으로 보여주고, 버튼이 그 기록을 마감한다.
//

import WidgetKit
import SwiftUI
import AppIntents

struct SekkiEntry: TimelineEntry {
    let date: Date
    let todayCount: Int
    let inProgressMeal: String?   // 오늘 "먹는 중"인 끼니 (없으면 nil)

    var isEating: Bool { inProgressMeal != nil }

    /// 잠금화면 한 줄/원형에 쓰는 짧은 문구
    var shortLabel: String {
        if let meal = inProgressMeal { return "\(meal) 먹는 중" }
        return "오늘 \(todayCount)개"
    }
}

struct SekkiProvider: TimelineProvider {
    func placeholder(in context: Context) -> SekkiEntry {
        SekkiEntry(date: Date(), todayCount: 0, inProgressMeal: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SekkiEntry) -> Void) {
        completion(entryNow())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SekkiEntry>) -> Void) {
        // 다음 갱신은 한 시간 뒤 또는 자정 중 이른 쪽 — 자정에 "오늘 N개"가 0으로 리셋돼야 한다.
        let now = Date()
        let nextHour = now.addingTimeInterval(3600)
        let midnight = Calendar.current.nextDate(after: now,
                                                 matching: DateComponents(hour: 0, minute: 0),
                                                 matchingPolicy: .nextTime) ?? nextHour
        completion(Timeline(entries: [entryNow()], policy: .after(min(nextHour, midnight))))
    }

    private func entryNow() -> SekkiEntry {
        let state = SekkiWidgetStore.currentState()
        return SekkiEntry(date: Date(), todayCount: state.todayCount, inProgressMeal: state.inProgressMeal)
    }
}

struct SekkiWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: SekkiEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            // 잠금화면 원형 — 먹는 중이면 모래시계, 아니면 오늘 기록 수
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: entry.isEating ? "hourglass" : "fork.knife")
                        .font(.caption2)
                    Text("\(entry.todayCount)")
                        .font(.headline)
                }
            }
            .widgetAccessibilityLabel("오늘 \(entry.todayCount)개 기록")

        case .accessoryInline:
            // 잠금화면 한 줄 — 버튼을 넣을 수 없으므로 상태만 (탭하면 앱 열림)
            Label(entry.shortLabel, systemImage: entry.isEating ? "hourglass" : "fork.knife")

        case .accessoryRectangular:
            // 잠금화면 직사각 — 상태 + 다 먹음 버튼
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.shortLabel)
                        .font(.headline)
                    Text(entry.isEating ? "다 먹었으면 오른쪽 탭" : "먹은 순간")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(intent: LogAteAllWidgetIntent()) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("다 먹음 기록")
            }

        default: // systemSmall (홈 화면)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: entry.isEating ? "hourglass" : "fork.knife")
                        .foregroundStyle(entry.isEating ? .orange : .secondary)
                    Text("오늘 \(entry.todayCount)개")
                        .font(.headline)
                    Spacer()
                }
                Text(entry.inProgressMeal.map { "\($0) 먹는 중" } ?? "먹은 순간을 툭 남겨요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(intent: LogAteAllWidgetIntent()) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("다 먹음")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("다 먹음 기록")
            }
        }
    }
}

private extension View {
    // 잠금화면 원형처럼 텍스트가 짧을 때 VoiceOver 문구를 보강
    func widgetAccessibilityLabel(_ label: String) -> some View {
        accessibilityElement(children: .ignore).accessibilityLabel(label)
    }
}

struct SekkiWidget: Widget {
    let kind = "SekkiWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SekkiProvider()) { entry in
            SekkiWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("세끼")
        .description("오늘 기록 수와 '다 먹음' 원탭")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
