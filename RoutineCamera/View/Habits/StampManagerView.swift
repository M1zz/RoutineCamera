//
//  StampManagerView.swift
//  RoutineCamera
//
//  내 스탬프 고르기: 쓰는 스탬프를 빼고 순서를 바꾸고, 기본 스탬프를 더하고, 나만의 스탬프를 만든다(플러스).
//  스탬프를 빼도 지난 기록은 남는다 — 달력에서 그대로 보인다.
//

import SwiftUI
import RoutineCameraCore

struct StampManagerView: View {
    @ObservedObject private var habits = HabitStore.shared
    @ObservedObject private var subscription = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingCreate = false
    @State private var showingPaywall = false

    private var available: [Stamp] {
        Stamp.catalog.filter { candidate in !habits.stamps.contains { $0.id == candidate.id } }
    }

    var body: some View {
        List {
            Section {
                ForEach(habits.stamps) { stamp in
                    row(stamp)
                }
                .onDelete { offsets in
                    offsets.map { habits.stamps[$0] }.forEach(habits.remove)
                }
                .onMove(perform: habits.move)
            } header: {
                Text("쓰는 스탬프", comment: "Section: stamps in use")
            } footer: {
                Text("챙길 것은 먹은 날에, 줄일 것은 참은 날에 찍어요. 빼도 지난 기록은 남아요.",
                     comment: "Footer explaining how stamps work")
            }

            if !available.isEmpty {
                Section {
                    ForEach(available) { stamp in
                        Button {
                            withAnimation { habits.add(stamp) }
                        } label: {
                            HStack {
                                row(stamp)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("더 고르기", comment: "Section: more stamps to add")
                }
            }

            Section {
                Button {
                    if subscription.allows(.customStamps) { showingCreate = true } else { showingPaywall = true }
                } label: {
                    HStack {
                        Label(String(localized: "나만의 스탬프 만들기", comment: "Button: create a custom stamp"), systemImage: "plus")
                        Spacer()
                        if !subscription.allows(.customStamps) { ProBadge(feature: .customStamps) }
                    }
                }
            }
        }
        .navigationTitle(Text("스탬프 고르기", comment: "Button: choose which stamps to show"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "완료"), systemImage: "checkmark") { dismiss() }
            }
        }
        .sheet(isPresented: $showingCreate) {
            NavigationStack { StampCreateView() }
        }
        .proPaywall(isPresented: $showingPaywall, lead: .customStamps)
    }

    private func row(_ stamp: Stamp) -> some View {
        HStack(spacing: 12) {
            Text(stamp.symbol)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(stamp.displayName)
                    .foregroundStyle(.primary)
                Text(stamp.kind.title)
                    .font(.caption)
                    .foregroundStyle(stamp.kind.color)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 나만의 스탬프 만들기 — 이모지 하나, 이름, 챙길 것/줄일 것.
struct StampCreateView: View {
    @ObservedObject private var habits = HabitStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var symbol = "🍣"
    @State private var name = ""
    @State private var kind: Stamp.Kind = .more

    private static let symbols = [
        "🍣", "🥩", "🍗", "🦐", "🥦", "🥕", "🍅", "🌽", "🥬", "🍄", "🧄", "🫑",
        "🍌", "🍓", "🫐", "🍊", "🥝", "🍇", "🍠", "🥔", "🍜", "🍝", "🍕", "🍔",
        "🍰", "🍫", "🍩", "🍪", "🧋", "☕️", "🍵", "🍷", "🧂", "🥤", "🍦", "⭐️",
    ]

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Text(symbol)
                        .font(.largeTitle)
                    TextField(String(localized: "이름 (예: 연어, 라면 안 먹음)", comment: "Placeholder: custom stamp name"), text: $name)
                }
                Picker(String(localized: "종류", comment: "Picker: stamp kind"), selection: $kind) {
                    Text(Stamp.Kind.more.title).tag(Stamp.Kind.more)
                    Text(Stamp.Kind.less.title).tag(Stamp.Kind.less)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(kind.hint)
            }

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                    ForEach(Self.symbols, id: \.self) { candidate in
                        Button {
                            symbol = candidate
                        } label: {
                            Text(candidate)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle().fill(candidate == symbol ? Color.accentColor.opacity(0.2) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(candidate == symbol ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("모양", comment: "Section: stamp emoji")
            }
        }
        .navigationTitle(Text("나만의 스탬프", comment: "Title: create a custom stamp"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "취소"), role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "추가", comment: "Button: add the new stamp")) {
                    habits.add(.custom(symbol: symbol, name: String(trimmedName.prefix(20)), kind: kind))
                    dismiss()
                }
                .disabled(trimmedName.isEmpty)
            }
        }
    }
}
