//
//  SekkiWidget.swift
//  SekkiWidget (위젯 익스텐션 타깃)
//
//  잠금화면/홈 위젯 — "오늘 N개 기록" + 앱 안 열고 "다 먹음" 원탭(인터랙티브 버튼).
//

import WidgetKit
import SwiftUI
import AppIntents

struct SekkiEntry: TimelineEntry {
    let date: Date
    let todayCount: Int
}

struct SekkiProvider: TimelineProvider {
    func placeholder(in context: Context) -> SekkiEntry {
        SekkiEntry(date: Date(), todayCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (SekkiEntry) -> Void) {
        completion(SekkiEntry(date: Date(), todayCount: SekkiWidgetStore.todayRecordCount()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SekkiEntry>) -> Void) {
        let entry = SekkiEntry(date: Date(), todayCount: SekkiWidgetStore.todayRecordCount())
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct SekkiWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: SekkiEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "fork.knife")
                        .font(.caption2)
                    Text("\(entry.todayCount)")
                        .font(.headline)
                }
            }

        case .accessoryRectangular:
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("오늘 \(entry.todayCount)개")
                        .font(.headline)
                    Text("먹은 순간")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(intent: LogAteAllWidgetIntent()) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }

        default: // systemSmall
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(.secondary)
                    Text("오늘 \(entry.todayCount)개")
                        .font(.headline)
                    Spacer()
                }
                Text("먹은 순간을 툭 남겨요")
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
            }
        }
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
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}
