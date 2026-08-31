//
//  DailySectionView.swift
//  RoutineCamera
//

import SwiftUI
import AVFoundation
import Photos

struct DailySectionView: View {
    let date: Date
    @ObservedObject var mealStore: MealRecordStore
    @ObservedObject private var settingsManager = SettingsManager.shared // "간식 보이기" 등 표시 설정 즉시 반영

    private var isToday: Bool {
        Calendar.current.isDate(date, inSameDayAs: Date())
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")

        if isToday {
            formatter.dateFormat = "MM월 dd일 (E)"
        } else {
            formatter.dateFormat = "MM월 dd일 (E)"
        }
        return formatter.string(from: date)
    }

    private var completionRate: Double {
        let meals = mealStore.getMeals(for: date)
        let recordedCount = meals.values.filter { $0.isComplete }.count
        return Double(recordedCount) / 3.0
    }

    var body: some View {
        let meals = mealStore.getMeals(for: date)
        let isPastDate = date < Calendar.current.startOfDay(for: Date())
        let isExerciseMode = SettingsManager.shared.albumType == .exercise
        let visibleCount = isExerciseMode
            ? getExerciseSlotsToShow(meals: meals).count
            : getMealsToShow(meals: meals).count
        let layout = calculateLayout(isExerciseMode: isExerciseMode, cardCount: visibleCount)

        VStack(spacing: 4) {
            mealPhotosRow(
                meals: meals,
                isPastDate: isPastDate,
                isExerciseMode: isExerciseMode,
                photoSize: layout.photoSize,
                spacing: layout.spacing,
                cardPadding: layout.cardPadding,
                cellHeight: layout.cellHeight
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: DatePositionPreferenceKey.self,
                    value: [date: geometry.frame(in: .named("scrollView")).minY]
                )
            }
        )
    }

    // 간식이 입력되어 있는지 확인
    private func hasSnacks(meals: [MealType: MealRecord]) -> Bool {
        return (meals[.snack1]?.isComplete ?? false) ||
               (meals[.snack2]?.isComplete ?? false) ||
               (meals[.snack3]?.isComplete ?? false)
    }

    // 현재 시간대에 맞는 식사 타입 3개 반환 (오늘 날짜용)
    // 순서: 아침 - 간식1 - 점심 - 저녁 - 간식2
    private func getMealsForCurrentTimeSlot() -> [MealType] {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let currentMinutes = hour * 60 + minute

        let notificationManager = NotificationManager.shared
        let lunchHour = calendar.component(.hour, from: notificationManager.lunchTime)
        let lunchMinute = calendar.component(.minute, from: notificationManager.lunchTime)
        let dinnerHour = calendar.component(.hour, from: notificationManager.dinnerTime)
        let dinnerMinute = calendar.component(.minute, from: notificationManager.dinnerTime)

        let lunchMinutes = lunchHour * 60 + lunchMinute
        let dinnerMinutes = dinnerHour * 60 + dinnerMinute

        // 현재 시간이 어느 시간대인지 판별
        if currentMinutes < lunchMinutes {
            // 아침 시간대: [아침, 간식1, 점심]
            return [.breakfast, .snack1, .lunch]
        } else if currentMinutes < dinnerMinutes {
            // 점심 시간대: [간식1, 점심, 간식2]
            return [.snack1, .lunch, .snack2]
        } else {
            // 저녁 시간대: [간식2, 저녁, 간식3]
            return [.snack2, .dinner, .snack3]
        }
    }

    // 동적 간식 칸 계산: "간식 보이기"가 꺼져 있으면 기록된 간식까지 모두 숨기고(오늘 행과 동일),
    // 켜져 있으면 기록된 간식 + 빈 간식 칸(기록 초대) 1개를 노출
    private func getSnacksToShow(meals: [MealType: MealRecord]) -> [MealType] {
        guard SettingsManager.shared.writeSnack else { return [] }

        var snacks: [MealType] = []

        for snack in [MealType.snack1, .snack2, .snack3] {
            if meals[snack]?.isComplete ?? false {
                snacks.append(snack)
            } else {
                snacks.append(snack)
                break
            }
        }

        return snacks
    }

    // 운동 모드에서 보여줄 칸: 그날 기록된 슬롯(시간순) + 지금 기록할 빈 칸 하나
    // (예전엔 항상 .breakfast 한 칸만 그려서 저녁에 운동해도 "아침" 칸에 들어갔다)
    private func getExerciseSlotsToShow(meals: [MealType: MealRecord]) -> [MealType] {
        let byTime = MealType.allCases.sorted { $0.typicalHour < $1.typicalHour }
        let recorded = byTime.filter { meals[$0]?.isComplete == true }

        // 지난 날에 이미 기록이 있으면 빈 칸을 덧붙이지 않는다 (못 채운 칸을 쌓지 않기 위함)
        guard isToday || recorded.isEmpty else { return recorded }

        // 새 기록을 받을 빈 칸 하나: 지금 시각의 슬롯, 이미 찼으면 그 뒤의 빈 슬롯
        let candidate = isToday ? MealType.inferred() : MealType.breakfast
        let emptySlot = recorded.contains(candidate)
            ? (byTime.first { $0.typicalHour > candidate.typicalHour && !recorded.contains($0) }
               ?? byTime.first { !recorded.contains($0) })
            : candidate

        guard let emptySlot else { return recorded }
        return (recorded + [emptySlot]).sorted { $0.typicalHour < $1.typicalHour }
    }

    // 표시할 식사 타입 배열 반환
    private func getMealsToShow(meals: [MealType: MealRecord]) -> [MealType] {
        if isToday {
            // 오늘: 모든 식사 타입 표시 (스크롤 가능)
            if SettingsManager.shared.writeSnack {
                return [.breakfast, .snack1, .lunch, .snack2, .dinner, .snack3]
            } else {
                return [.breakfast, .lunch, .dinner]
            }
        } else {
            // 과거/미래: 아침 점심 저녁 + 동적 간식
            return [.breakfast, .lunch, .dinner] + getSnacksToShow(meals: meals)
        }
    }

    // 현재 시간대에 맞는 주요 식사 타입 반환 (스크롤 위치용)
    private func getCurrentPrimaryMeal() -> MealType {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let currentMinutes = hour * 60 + minute

        let notificationManager = NotificationManager.shared
        let lunchHour = calendar.component(.hour, from: notificationManager.lunchTime)
        let lunchMinute = calendar.component(.minute, from: notificationManager.lunchTime)
        let dinnerHour = calendar.component(.hour, from: notificationManager.dinnerTime)
        let dinnerMinute = calendar.component(.minute, from: notificationManager.dinnerTime)

        let lunchMinutes = lunchHour * 60 + lunchMinute
        let dinnerMinutes = dinnerHour * 60 + dinnerMinute

        // 현재 시간이 어느 시간대인지 판별
        if currentMinutes < lunchMinutes {
            return .breakfast
        } else if currentMinutes < dinnerMinutes {
            return .lunch
        } else {
            return .dinner
        }
    }

    private func calculateLayout(isExerciseMode: Bool, cardCount: Int) -> (photoSize: CGFloat, spacing: CGFloat, cardPadding: CGFloat, cellHeight: CGFloat) {
        let screenWidth = UIScreen.appWidth
        let horizontalPadding: CGFloat = 16
        let cardPadding: CGFloat = 12 // 오늘 테두리와 사진 사이 여백 (8은 너무 타이트)
        let spacing: CGFloat = 4

        // 4칸 이상이면 3.35칸 기준으로 크기를 잡아 4번째 칸이 살짝 보이게 함
        // (가로로 더 스크롤할 수 있음을 시각적으로 암시)
        let photoCount: CGFloat
        if isExerciseMode {
            // 운동은 하루 1회가 보통이라 한 칸이면 크게, 여러 번 했으면 식단과 같은 규칙으로
            photoCount = cardCount <= 1 ? 1 : (cardCount > 3 ? 3.35 : CGFloat(cardCount))
        } else if cardCount > 3 {
            photoCount = 3.35
        } else {
            photoCount = 3
        }
        let availableWidth = screenWidth - horizontalPadding - (cardPadding * 2) - (spacing * (photoCount - 1))
        let photoSize = availableWidth / photoCount
        let cellHeight = photoSize + (cardPadding * 2) + 4

        return (photoSize, spacing, cardPadding, cellHeight)
    }

    @ViewBuilder
    private func mealPhotosRow(
        meals: [MealType: MealRecord],
        isPastDate: Bool,
        isExerciseMode: Bool,
        photoSize: CGFloat,
        spacing: CGFloat,
        cardPadding: CGFloat,
        cellHeight: CGFloat
    ) -> some View {
        // 표시할 칸이 3개보다 많으면 ScrollView 사용 (과거 날짜 포함)
        let visibleSlots = isExerciseMode ? getExerciseSlotsToShow(meals: meals) : getMealsToShow(meals: meals)
        let shouldUseScrollView = visibleSlots.count > 3

        Group {
            if shouldUseScrollView {
                // 칸이 3개보다 많으면 ScrollView 사용 (오늘 날짜 및 과거 날짜 포함)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: spacing) {
                            if isExerciseMode {
                                exerciseModePhotos(meals: meals, isPastDate: isPastDate, photoSize: photoSize)
                            } else {
                                dietModePhotos(meals: meals, isPastDate: isPastDate, photoSize: photoSize, spacing: spacing)
                            }
                        }
                        // 세로 패딩이 없으면 카드가 오늘 테두리 위아래에 딱 붙음
                        .padding(.horizontal, cardPadding)
                        .padding(.vertical, cardPadding)
                    }
                    .onAppear {
                        // 오늘 날짜인 경우에만 자동 스크롤
                        if isToday {
                            let currentMeal = isExerciseMode ? MealType.inferred() : getCurrentPrimaryMeal()
                            // 약간의 딜레이를 주어 레이아웃이 완료된 후 스크롤
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    proxy.scrollTo(currentMeal, anchor: .center)
                                }
                            }
                        }
                    }
                }
            } else {
                // 운동 모드 또는 3칸 이하 (3칸 고정)
                HStack(spacing: spacing) {
                    if isExerciseMode {
                        exerciseModePhotos(meals: meals, isPastDate: isPastDate, photoSize: photoSize)
                    } else {
                        dietModePhotos(meals: meals, isPastDate: isPastDate, photoSize: photoSize, spacing: spacing)
                    }
                }
                .padding(cardPadding)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isToday ? Color.blue.opacity(0.04) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isToday ? Color.blue.opacity(0.35) : Color.clear, lineWidth: 1.5)
        )
        .frame(height: cellHeight)
    }

    @ViewBuilder
    private func exerciseModePhotos(meals: [MealType: MealRecord], isPastDate: Bool, photoSize: CGFloat) -> some View {
        ForEach(getExerciseSlotsToShow(meals: meals), id: \.self) { slot in
            MealPhotoView(
                date: date,
                mealType: slot,
                mealRecord: meals[slot],
                mealStore: mealStore,
                isToday: isToday,
                photoSize: photoSize
            )
            .frame(width: photoSize, height: photoSize)
            .id(slot)
        }
    }

    @ViewBuilder
    private func dietModePhotos(meals: [MealType: MealRecord], isPastDate: Bool, photoSize: CGFloat, spacing: CGFloat) -> some View {
        let mealsToShow = getMealsToShow(meals: meals)

        ForEach(mealsToShow, id: \.self) { mealType in
            MealPhotoView(
                date: date,
                mealType: mealType,
                mealRecord: meals[mealType],
                mealStore: mealStore,
                isToday: isToday,
                photoSize: photoSize
            )
            .frame(width: photoSize, height: photoSize)
            .id(mealType) // ScrollViewReader가 스크롤할 수 있도록 ID 추가
        }
    }
}

// 식사 사진 뷰 (컴팩트한 정사각형)
