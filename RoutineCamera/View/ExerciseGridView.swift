//
//  ExerciseGridView.swift
//  RoutineCamera
//
//  운동 앨범 메인 화면 — 인스타그램 피드처럼 3열 정사각형 격자.
//  운동은 끼니 구분이 없고 사진 한 장이 곧 기록이라, 한 화면에 최대한 많은 날을 보여준다.
//  (날짜별 한 줄 격자는 하루에 큰 사진 한 장, 순간 피드는 72pt 썸네일 목록이라 몇 날밖에 안 보였다)
//  칸마다 날짜를 얹어 사진만 훑어도 언제 운동했는지 읽힌다. 격자 자체는 식단과 함께 쓰는 MealPhotoGrid.
//

import SwiftUI
import RoutineCameraCore

struct ExerciseGridView: View {
    @ObservedObject var mealStore: MealRecordStore

    @State private var recordingMealType: MealType?
    @State private var recordingPhotoType: MealPhotoView.PhotoType = .before

    var body: some View {
        Group {
            if MealPhotoGrid<EmptyView>.hasRecords(in: mealStore) {
                MealPhotoGrid(mealStore: mealStore)
            } else {
                emptyState
            }
        }
        // 기록 버튼은 하단 고정 (스크롤해도 항상 보임)
        .safeAreaInset(edge: .bottom) {
            recordButton
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .background(.bar)
        }
        .sheet(item: $recordingMealType) { mealType in
            CameraPickerView(
                date: Date(),
                mealType: mealType,
                mealStore: mealStore,
                selectedPhotoType: $recordingPhotoType
            )
        }
    }

    // MARK: - 기록하기 버튼

    private var recordButton: some View {
        Button {
            recordingPhotoType = .before
            recordingMealType = slotForNewRecord()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "figure.run")
                    .scaledFont(size: 17, weight: .semibold)
                Text("운동 기록하기")
                    .scaledFont(size: 17, weight: .semibold)
                Spacer()
            }
            .foregroundColor(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(Color.solidGreen)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("운동 기록하기")
        .accessibilityHint("두 번 탭하여 사진으로 기록")
    }

    /// 새 운동을 담을 오늘의 슬롯: 지금 시각의 슬롯, 이미 찼으면 그 뒤의 빈 슬롯.
    /// 운동은 끼니가 아니라서 같은 시간대에 두 번 해도 앞 기록을 덮으면 안 된다.
    private func slotForNewRecord() -> MealType {
        let today = mealStore.getMeals(for: Calendar.current.startOfDay(for: Date()))
        let candidate = MealType.inferred()
        guard today[candidate]?.isComplete == true else { return candidate }
        let byTime = MealType.allCases.sorted { $0.typicalHour < $1.typicalHour }
        let isEmpty: (MealType) -> Bool = { today[$0]?.isComplete != true }
        return byTime.first { $0.typicalHour > candidate.typicalHour && isEmpty($0) }
            ?? byTime.first(where: isEmpty)
            ?? candidate
    }

    // MARK: - 빈 상태

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "figure.run.circle")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.5))
            VStack(spacing: 6) {
                Text("아직 운동 기록이 없어요")
                    .font(.title3.weight(.semibold))
                Text("운동한 날 사진 한 장이면 충분해요.\n모아 보면 꾸준함이 한눈에 보여요.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }
}
