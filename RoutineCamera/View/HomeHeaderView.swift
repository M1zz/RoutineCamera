//
//  HomeHeaderView.swift
//  RoutineCamera
//

import SwiftUI
import AVFoundation
import Photos

struct HomeHeaderView: View {
    let date: Date // 현재 보이는 날짜
    @ObservedObject var mealStore: MealRecordStore
    @ObservedObject var goalManager: GoalManager
    @ObservedObject var settingsManager: SettingsManager
    let onStatisticsTap: () -> Void
    let onFriendsTap: () -> Void
    let onSettingsTap: () -> Void
    let onTodayTap: () -> Void

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter.string(from: date)
    }

    private var isToday: Bool {
        Calendar.current.isDate(date, inSameDayAs: Date())
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // 날짜 (탭하면 오늘로 이동)
                HStack(spacing: 6) {
                    Text(dateString)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .layoutPriority(1)
                .contentShape(Rectangle())
                .onTapGesture { onTodayTap() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("현재 \(dateString)\(isToday ? ", 오늘" : "")")
                .accessibilityHint("두 번 탭하여 오늘 날짜로 이동")
                .accessibilityAddTraits(.isButton)

                Spacer(minLength: 8)

                // 앨범 타입 전환 (설정에서 켠 경우에만)
                if settingsManager.showAlbumSwitcher {
                    Button(action: {
                        withAnimation {
                            settingsManager.albumType = settingsManager.albumType == .diet ? .exercise : .diet
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: settingsManager.albumType.symbolName)
                                .font(.system(size: 12))
                            Text(settingsManager.albumType.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .fixedSize()
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(.systemGray6)))
                    }
                    .accessibilityLabel("기록 모드 전환")
                    .accessibilityValue("현재 \(settingsManager.albumType.rawValue) 모드")
                    .accessibilityHint("두 번 탭하여 \(settingsManager.albumType == .diet ? "운동" : "식단") 모드로 전환")
                }

                // 통계·친구·설정을 하나의 "..." 메뉴로 통합 (헤더 공간 확보)
                Menu {
                    Button(action: onStatisticsTap) {
                        Label("통계", systemImage: "chart.bar.fill")
                    }
                    Button(action: onFriendsTap) {
                        Label("친구", systemImage: "person.2.fill")
                    }
                    Button(action: onSettingsTap) {
                        Label("설정", systemImage: "gearshape.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 21))
                        .foregroundColor(.gray)
                }
                .accessibilityLabel("더 보기")
                .accessibilityHint("통계, 친구, 설정 메뉴를 엽니다")
            }

            // 목표 진행률 (켠 경우에만, 한 줄)
            // 연속(끊기면 리셋)이 아니라 누적 기록일 기준 — 하루 놓쳐도 바가 줄지 않는다.
            if goalManager.goalEnabled {
                let recordedDays = mealStore.getTotalRecordedDays()
                let progress = goalManager.getProgress(currentStreak: recordedDays)
                let achieved = goalManager.isGoalAchieved(currentStreak: recordedDays)

                HStack(spacing: 10) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.systemGray5))
                                .frame(height: 6)

                            Capsule()
                                .fill(achieved ? Color.green : Color.blue)
                                .frame(width: geometry.size.width * CGFloat(progress), height: 6)
                        }
                    }
                    .frame(height: 6)

                    Text("\(recordedDays)/\(goalManager.goalDays)일")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("목표 진행률")
                .accessibilityValue("\(goalManager.goalDays)일 목표 중 \(recordedDays)일 기록, \(Int((progress * 100).rounded()))퍼센트 달성\(achieved ? ", 목표 달성 완료" : "")")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .bottom)
    }
}


// MARK: - 개발자 문의
