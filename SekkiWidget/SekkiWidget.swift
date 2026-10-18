//
//  SekkiWidget.swift
//  SekkiWidget (위젯 익스텐션 타깃)
//
//  홈 화면/잠금화면 위젯 — 오늘 챙긴 끼니(아침·점심·저녁 체크) + 앱 안 열고 "다 먹음" 원탭(인터랙티브 버튼).
//  오늘 식전만 찍어둔 끼니가 있으면 "○○ 먹는 중"으로 보여주고, 버튼이 그 기록을 마감한다.
//

import WidgetKit
import SwiftUI
import AppIntents
import RoutineCameraCore

struct SekkiEntry: TimelineEntry {
    let date: Date
    let todayCount: Int
    let inProgressMeal: String?   // 오늘 "먹는 중"인 끼니 (없으면 nil)
    var caredMeals: [String] = WidgetStateResolver.defaultCaredMeals  // 체크로 보여줄 끼니
    var recordedMeals: Set<String> = []                               // 오늘 기록한 끼니
    var snackCount = 0

    var isEating: Bool { inProgressMeal != nil }
    var caredDoneCount: Int { caredMeals.filter { recordedMeals.contains($0) }.count }
    var missingMeals: [String] { caredMeals.filter { !recordedMeals.contains($0) } }

    /// 잠금화면 한 줄/직사각 첫 줄에 쓰는 짧은 문구
    var shortLabel: String {
        if let meal = inProgressMeal { return "\(meal) 먹는 중" }
        if missingMeals.isEmpty { return "오늘 끼니 다 챙김" }
        return "남은 끼니 \(missingMeals.joined(separator: "·"))"
    }

    /// VoiceOver 용 — 어떤 끼니를 챙겼고 무엇이 남았는지
    var mealsAccessibilityLabel: String {
        let done = caredMeals.filter { recordedMeals.contains($0) }
        var parts = [done.isEmpty ? "오늘 챙긴 끼니 없음" : "\(done.joined(separator: ", ")) 챙김"]
        if !missingMeals.isEmpty { parts.append("\(missingMeals.joined(separator: ", ")) 기록 안 함") }
        if snackCount > 0 { parts.append("간식 \(snackCount)번") }
        return parts.joined(separator: ", ")
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
        return SekkiEntry(date: Date(),
                          todayCount: state.todayCount,
                          inProgressMeal: state.inProgressMeal,
                          caredMeals: state.caredMeals,
                          recordedMeals: state.recordedMeals,
                          snackCount: state.snackCount)
    }
}

/// 끼니 하나 — 기록했으면 채운 체크, 안 했으면 빈 원
private struct MealCheckMark: View {
    let meal: String
    let done: Bool
    var compact = false

    var body: some View {
        if compact {
            HStack(spacing: 2) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                Text(meal)
            }
            .font(.caption2)
            .foregroundStyle(done ? .primary : .secondary)
        } else {
            VStack(spacing: 3) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? Color.green : Color.secondary.opacity(0.6))
                Text(meal)
                    .font(.caption2.weight(done ? .semibold : .regular))
                    .foregroundStyle(done ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct SekkiWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: SekkiEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            // 잠금화면 원형 — 챙길 끼니 중 몇 끼를 챙겼는지 (먹는 중이면 모래시계)
            Gauge(value: Double(entry.caredDoneCount), in: 0...Double(max(entry.caredMeals.count, 1))) {
                Image(systemName: entry.isEating ? "hourglass" : "fork.knife")
            } currentValueLabel: {
                Text("\(entry.caredDoneCount)/\(entry.caredMeals.count)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccessibilityLabel(entry.mealsAccessibilityLabel)

        case .accessoryInline:
            // 잠금화면 한 줄 — 버튼을 넣을 수 없으므로 상태만 (탭하면 앱 열림)
            Label(entry.shortLabel, systemImage: entry.isEating ? "hourglass" : "fork.knife")

        case .accessoryRectangular:
            // 잠금화면 직사각 — 상태 + 다 먹음 버튼
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.shortLabel)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 6) {
                        ForEach(entry.caredMeals, id: \.self) { meal in
                            MealCheckMark(meal: meal, done: entry.recordedMeals.contains(meal), compact: true)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(entry.mealsAccessibilityLabel)
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
                    Text(entry.inProgressMeal.map { "\($0) 먹는 중" } ?? "오늘 식사")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    if entry.snackCount > 0 {
                        Text("간식 \(entry.snackCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                // 아침·점심·저녁 — 챙긴 끼니는 체크, 아직 기록 안 한 끼니는 빈 원
                HStack(spacing: 4) {
                    ForEach(entry.caredMeals, id: \.self) { meal in
                        MealCheckMark(meal: meal, done: entry.recordedMeals.contains(meal))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(entry.mealsAccessibilityLabel)
                Spacer(minLength: 0)
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
        .description("오늘 챙긴 끼니와 '다 먹음' 원탭")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
