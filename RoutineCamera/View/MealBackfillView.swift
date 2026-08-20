//
//  MealBackfillView.swift
//  RoutineCamera
//
//  "예전 기록도 친구에게 공유하기" — 폰에만 있는 지난 기록을 iCloud에 올린다
//

import SwiftUI

struct MealBackfillView: View {
    @ObservedObject private var backfill = MealBackfillManager.shared
    @ObservedObject private var settingsManager = SettingsManager.shared

    @State private var range: MealBackfillManager.Range = .quarter
    @State private var estimate: MealBackfillManager.Estimate?

    var body: some View {
        Form {
            Section {
                Text("평소에는 새로 쓰거나 고친 기록만 올라갑니다. 그래서 앱을 쓰기 시작하기 전이나 예전 버전에서 남긴 기록은 이 폰에만 있고, 친구 화면에서는 비어 보일 수 있어요.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("올릴 범위")) {
                Picker("범위", selection: $range) {
                    ForEach(MealBackfillManager.Range.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(backfill.isRunning)

                if let estimate {
                    if estimate.dates == 0 {
                        Label("올릴 기록이 없어요. 이미 모두 공유된 상태입니다.", systemImage: "checkmark.circle")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(estimate.dates)일 · 사진 \(estimate.photos)장")
                                .font(.system(size: 15, weight: .semibold))
                            Text("업로드 약 \(estimate.megabytes)MB 예상 · Wi-Fi에서 실행하는 걸 권합니다")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section {
                if backfill.isRunning {
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView(value: Double(backfill.processed),
                                     total: Double(max(backfill.total, 1)))

                        Text("\(backfill.processed) / \(backfill.total)일 처리 · 올림 \(backfill.uploaded) · 건너뜀 \(backfill.skipped)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(role: .destructive) {
                            backfill.cancel()
                        } label: {
                            Text("중단")
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        _Concurrency.Task {
                            await backfill.start(range: range)
                            estimate = backfill.estimate(range: range)
                        }
                    } label: {
                        Label("예전 기록 올리기", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(!settingsManager.shareMealsToCloud || (estimate?.dates ?? 0) == 0)
                }

                if let summary = backfill.summary {
                    Text(summary)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            } footer: {
                if !settingsManager.shareMealsToCloud {
                    Text("설정의 '내 식단 공유'가 꺼져 있어 올릴 수 없습니다.")
                        .foregroundColor(.orange)
                } else {
                    Text("중단해도 다음에 이어서 올립니다. 이미 올라간 날짜는 사진을 다시 보내지 않고 건너뜁니다.")
                }
            }

            Section {
                Button("올린 기록 초기화") {
                    backfill.resetProgress()
                    estimate = backfill.estimate(range: range)
                }
                .foregroundColor(.secondary)
                .disabled(backfill.isRunning)
            } footer: {
                Text("어디까지 올렸는지에 대한 기록만 지웁니다. 서버에 올라간 기록은 지워지지 않아요.")
            }
        }
        .navigationTitle("예전 기록 공유")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            estimate = backfill.estimate(range: range)
        }
        .onChange(of: range) { _, newValue in
            estimate = backfill.estimate(range: newValue)
        }
    }
}
