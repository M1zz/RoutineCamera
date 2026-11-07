//
//  DayCheckInCard.swift
//  RoutineCamera
//
//  하루 한 장: 내 스탬프를 눌러 찍고, 물 · 카페인 잔 수를 센다.
//  홈 피드 맨 위(오늘)와 달력에서 고른 날에 같은 카드를 쓴다.
//

import SwiftUI
import RoutineCameraCore

struct DayCheckInCard: View {
    let date: Date
    @ObservedObject private var habits = HabitStore.shared
    @State private var showingStampManager = false

    /// 홈에서는 한 줄로 밀어 보고, 달력의 하루 화면에서는 모두 펼쳐 본다
    var wrapsStamps = false

    private var log: DayLog { habits.log(on: date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Calendar.current.isDateInToday(date)
                     ? String(localized: "오늘 챙긴 것", comment: "Check-in card title for today")
                     : String(localized: "이날 챙긴 것", comment: "Check-in card title for a past day"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    showingStampManager = true
                } label: {
                    Text("스탬프 고르기", comment: "Button: choose which stamps to show")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }

            stamps

            HStack(spacing: 10) {
                CupCounter(symbol: "drop.fill", color: .cyan,
                           title: String(localized: "물", comment: "Counter: glasses of water"),
                           count: log.water) { habits.addWater($0, on: date) }
                CupCounter(symbol: "cup.and.saucer.fill", color: .brown,
                           title: String(localized: "카페인", comment: "Counter: caffeinated drinks"),
                           count: log.caffeine) { habits.addCaffeine($0, on: date) }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showingStampManager) {
            NavigationStack { StampManagerView() }
        }
    }

    @ViewBuilder
    private var stamps: some View {
        if habits.stamps.isEmpty {
            Button {
                showingStampManager = true
            } label: {
                Label(String(localized: "스탬프를 골라 보세요", comment: "Empty stamps: prompt to choose stamps"), systemImage: "plus.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
        } else if wrapsStamps {
            FlowLayout(spacing: 8) { chips }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { chips }
            }
            .scrollClipDisabled()
        }
    }

    private var chips: some View {
        ForEach(habits.stamps) { stamp in
            StampChip(stamp: stamp, isOn: log.stamps.contains(stamp.id)) {
                withAnimation(.snappy(duration: 0.2)) { habits.toggle(stamp, on: date) }
            }
        }
    }
}

/// 스탬프 하나. 찍으면 색이 채워진다 (챙길 것은 초록, 줄일 것은 주황).
struct StampChip: View {
    let stamp: Stamp
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(stamp.symbol)
                Text(stamp.displayName)
                    .font(.subheadline.weight(isOn ? .semibold : .regular))
                    .lineLimit(1)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
            }
            .foregroundStyle(isOn ? stamp.kind.color : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isOn ? stamp.kind.color.opacity(0.18) : Color(.tertiarySystemBackground))
            )
            .overlay(
                Capsule().strokeBorder(isOn ? stamp.kind.color : Color(.separator), lineWidth: isOn ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel(stamp.displayName)
        .accessibilityValue(isOn ? Text("찍음", comment: "VoiceOver: stamp is marked") : Text("안 찍음", comment: "VoiceOver: stamp is not marked"))
        .accessibilityHint(stamp.kind.hint)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// 잔 수 세기. 숫자를 누르면 한 잔 더, − 로 한 잔 빼기.
struct CupCounter: View {
    let symbol: String
    let color: Color
    let title: String
    let count: Int
    let change: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button { change(-1) } label: {
                Image(systemName: "minus")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(.tertiarySystemBackground)))
            }
            .buttonStyle(.plain)
            .disabled(count == 0)
            .opacity(count == 0 ? 0.35 : 1)
            .accessibilityHidden(true)

            Button { change(1) } label: {
                // 이름이 길면(Caffeine 등) 잘라 보이지 않고 아이콘과 잔 수만 남긴다
                ViewThatFits(in: .horizontal) {
                    label(showsTitle: true)
                    label(showsTitle: false)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(color.opacity(count > 0 ? 0.15 : 0.06)))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.increase, trigger: count)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Text(String(localized: "\(count)잔", comment: "Number of cups/glasses")))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(1)
            case .decrement: change(-1)
            @unknown default: break
            }
        }
        .accessibilityHint(Text("위아래로 쓸어 잔 수를 바꿔요", comment: "VoiceOver hint: swipe up/down to change the cup count"))
    }

    private func label(showsTitle: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            if showsTitle {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 2)
            Text(String(localized: "\(count)잔", comment: "Number of cups/glasses"))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
        }
    }
}
