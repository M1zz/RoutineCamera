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

    /// 화면에 보일 끼니 이름 — 간식1·2·3 은 "간식"
    static func displayName(_ meal: String) -> String {
        switch MealType(rawValue: meal) {
        case .breakfast: return String(localized: "아침", comment: "Meal name: breakfast")
        case .lunch:     return String(localized: "점심", comment: "Meal name: lunch")
        case .dinner:    return String(localized: "저녁", comment: "Meal name: dinner")
        case .snack1, .snack2, .snack3: return String(localized: "간식", comment: "Meal name: snack")
        case nil:        return meal
        }
    }
    var caredDoneCount: Int { caredMeals.filter { recordedMeals.contains($0) }.count }
    var missingMeals: [String] { caredMeals.filter { !recordedMeals.contains($0) } }

    /// 잠금화면 한 줄/직사각 첫 줄에 쓰는 짧은 문구
    var shortLabel: String {
        if let meal = inProgressMeal {
            return String(localized: "\(Self.displayName(meal)) 먹는 중", comment: "Widget: currently eating this meal; argument is the meal name")
        }
        if missingMeals.isEmpty { return String(localized: "오늘 끼니 다 챙김", comment: "Widget: all of today's meals are logged") }
        let names = missingMeals.map(Self.displayName).joined(separator: "·")
        return String(localized: "남은 끼니 \(names)", comment: "Widget: meals not yet logged today; argument is a list of meal names")
    }

    /// VoiceOver 용 — 어떤 끼니를 챙겼고 무엇이 남았는지
    var mealsAccessibilityLabel: String {
        let done = caredMeals.filter { recordedMeals.contains($0) }.map(Self.displayName).joined(separator: ", ")
        let missing = missingMeals.map(Self.displayName).joined(separator: ", ")
        var parts = [done.isEmpty
                     ? String(localized: "오늘 챙긴 끼니 없음", comment: "Widget VoiceOver: no meals logged today")
                     : String(localized: "\(done) 챙김", comment: "Widget VoiceOver: these meals are logged; argument is a list of meal names")]
        if !missing.isEmpty {
            parts.append(String(localized: "\(missing) 기록 안 함", comment: "Widget VoiceOver: these meals are not logged; argument is a list of meal names"))
        }
        if snackCount > 0 {
            parts.append(String(localized: "간식 \(snackCount)번", comment: "Widget VoiceOver: number of snacks logged today"))
        }
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
                Text(SekkiEntry.displayName(meal))
            }
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(done ? .primary : .secondary)
        } else {
            VStack(spacing: 3) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? Color.green : Color.secondary.opacity(0.6))
                Text(SekkiEntry.displayName(meal))
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
                    Text(entry.inProgressMeal.map { String(localized: "\(SekkiEntry.displayName($0)) 먹는 중", comment: "Widget: currently eating this meal; argument is the meal name") }
                         ?? String(localized: "오늘 식사", comment: "Widget title: today's meals"))
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
                // 작은 위젯에서 아주 큰 글씨면 '다 먹음' 버튼이 밀려 잘린다 — 위젯 안 글씨는 여기까지만 키운다
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("세끼")
        .description("오늘 챙긴 끼니와 '다 먹음' 원탭")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
