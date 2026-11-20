//
//  PlaceTipBanner.swift
//  RoutineCamera
//
//  쓰는 요령 한 줄: "찍은 곳 함께 남기기" 가 설정 안쪽에 꺼진 채로 있어 모르고 지나가는 사람에게 어쩌다 알려 준다.
//
//  누구에게: 식단을 사흘 넘게 기록했고 아직 찍은 곳을 켜지 않은 사람.
//  얼마나 드물게: 뜬 날 하루만 보이고 30일 쉰다. 세 번까지. 닫으면 다시 뜨지 않는다.
//
//  ⚠️ 모달이 아니다. 목록 위에 얹힐 뿐 기록을 막지 않는다.
//

import SwiftUI
import RoutineCameraCore

struct PlaceTipBanner: View {
    @ObservedObject var mealStore: MealRecordStore
    @ObservedObject private var settings = SettingsManager.shared
    @AppStorage("tip.place.showCount") private var showCount = 0
    @AppStorage("tip.place.shownOn") private var shownOn = ""        // 마지막으로 뜬 날 (DayKey)
    @AppStorage("tip.place.restUntil") private var restUntil = 0.0   // 이때까지 쉰다 (1970 기준 초)

    private static let maxShows = 3
    private static let rest: TimeInterval = 30 * 24 * 60 * 60
    private static let minRecordedDays = 3

    private var today: String { DayKey.string(from: Date()) }

    private var shows: Bool {
        guard settings.albumType == .diet, !settings.recordPlace else { return false }
        if shownOn == today { return showCount <= Self.maxShows }   // 오늘 뜬 것은 오늘 하루 그대로
        return showCount < Self.maxShows
            && Date().timeIntervalSince1970 >= restUntil
            && mealStore.getTotalRecordedDays() >= Self.minRecordedDays
    }

    var body: some View {
        if shows {
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("어디서 먹었는지도 함께 남길 수 있어요", comment: "Tip banner: meals can also record where they were eaten")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button {
                    settings.recordPlace = true
                    MealLocationProvider.shared.requestAuthorizationIfNeeded()
                } label: {
                    Text("켜기", comment: "Tip banner button: turn the feature on")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(Color.accentColor))
                }
                Button {
                    withAnimation { showCount = Self.maxShows + 1 }   // 닫으면 다시 뜨지 않는다
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("닫기")
            }
            .buttonStyle(.plain)
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .onAppear {
                // 오늘 처음 떴으면 한 번으로 세고, 내일부터 30일 쉰다
                guard shownOn != today else { return }
                shownOn = today
                showCount += 1
                restUntil = Date().timeIntervalSince1970 + Self.rest
            }
        }
    }
}
