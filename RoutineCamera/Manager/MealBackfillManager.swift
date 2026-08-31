//
//  MealBackfillManager.swift
//  RoutineCamera
//
//  예전 기록을 CloudKit에 올리는 일회성 백필
//
//  왜 필요한가
//  - 평소 업로드는 "바뀐 날짜"만 올린다. 그래서 앱을 쓰기 시작하기 전이나
//    CloudKit 전환(1.0.4) 이전의 기록은 폰에만 있고 서버에는 없다.
//  - 친구 화면에서 오래된 날짜가 비어 보이는 원인이 이것이다.
//
//  원칙
//  - **사용자가 직접 실행**한다. 공개 DB에 이력 전체를 올리는 일이라 자동 실행하지 않는다.
//  - 이미 올라간 날짜는 건너뛴다. 확인은 `desiredKeys: []`로 사진을 받지 않고 존재만 본다.
//  - 중단해도 다음에 이어서 한다 (완료한 날짜를 저장).
//

import Foundation
import Combine

@MainActor
final class MealBackfillManager: ObservableObject {
    static let shared = MealBackfillManager()

    enum Range: String, CaseIterable, Identifiable {
        case quarter
        case year
        case all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .quarter: return "최근 3개월"
            case .year: return "최근 1년"
            case .all: return "전체 기록"
            }
        }

        /// nil = 제한 없음
        var days: Int? {
            switch self {
            case .quarter: return 90
            case .year: return 365
            case .all: return nil
            }
        }
    }

    struct Estimate {
        let dates: Int
        let photos: Int
        let megabytes: Int
    }

    @Published private(set) var isRunning = false
    @Published private(set) var processed = 0
    @Published private(set) var total = 0
    @Published private(set) var uploaded = 0
    @Published private(set) var skipped = 0
    @Published private(set) var failed = 0
    @Published private(set) var summary: String?

    /// 업로드 후 사진 한 장의 대략 크기 (긴 변 1024px, JPEG 0.6 기준)
    private let bytesPerPhotoEstimate = 100 * 1024
    private let completedKey = "mealBackfillCompletedDates_v1"
    private var isCancelled = false

    private init() {}

    // MARK: - 예상치

    func estimate(range: Range) -> Estimate {
        let dates = targetDates(range: range)
        let done = completedDates()

        var remainingDates = 0
        var photos = 0

        for date in dates {
            let key = dateKey(date)
            guard !done.contains(key) else { continue }

            let meals = MealRecordStore.shared.dietMeals(for: date)
            guard !meals.isEmpty else { continue }

            remainingDates += 1
            for meal in meals.values {
                if meal.beforeImageData != nil { photos += 1 }
                if meal.afterImageData != nil { photos += 1 }
            }
        }

        return Estimate(
            dates: remainingDates,
            photos: photos,
            megabytes: max(1, photos * bytesPerPhotoEstimate / 1024 / 1024)
        )
    }

    // MARK: - 실행

    func start(range: Range) async {
        guard !isRunning else { return }

        guard FriendManager.shared.isSignedIn else {
            summary = "iCloud 계정을 확인할 수 없습니다. 설정에서 iCloud에 로그인한 뒤 다시 시도해주세요."
            return
        }
        guard SettingsManager.shared.shareMealsToCloud else {
            summary = "먼저 설정에서 '내 식단 공유'를 켜주세요."
            return
        }

        isRunning = true
        isCancelled = false
        summary = nil
        processed = 0
        uploaded = 0
        skipped = 0
        failed = 0
        defer { isRunning = false }

        let dates = targetDates(range: range)
        total = dates.count

        var done = completedDates()

        // 이미 서버에 있는 날짜를 먼저 걸러낸다 (사진은 받지 않음)
        let toCheck = dates.filter { !done.contains(dateKey($0)) }
        let serverCounts: [String: Int]
        do {
            serverCounts = try await FriendManager.shared.uploadedMealCounts(dates: toCheck)
        } catch {
            print("ℹ️ [백필] 서버 확인 실패 — 전부 업로드 시도: \(error.localizedDescription)")
            serverCounts = [:]
        }

        for date in dates {
            if isCancelled { break }

            let key = dateKey(date)
            let meals = MealRecordStore.shared.dietMeals(for: date)

            // 기록이 없거나, 이미 올린 날이거나, 서버에 같은 수 이상 있으면 건너뛴다
            if meals.isEmpty || done.contains(key) || (serverCounts[key] ?? 0) >= meals.count {
                skipped += 1
                processed += 1
                done.insert(key)
                saveCompleted(done)
                continue
            }

            do {
                try await FriendManager.shared.uploadMyMeals(date: date, meals: meals)
                uploaded += 1
                done.insert(key)
                saveCompleted(done)
            } catch {
                failed += 1
                print("❌ [백필] \(key) 업로드 실패: \(error.localizedDescription)")
            }
            processed += 1
        }

        summary = makeSummary()
        print("🏁 [백필] \(summary ?? "")")
    }

    func cancel() {
        isCancelled = true
    }

    /// 완료 기록 초기화 (처음부터 다시 올리고 싶을 때)
    func resetProgress() {
        UserDefaults.standard.removeObject(forKey: completedKey)
        summary = nil
        processed = 0
        total = 0
        uploaded = 0
        skipped = 0
        failed = 0
    }

    // MARK: - 내부

    private func makeSummary() -> String {
        if isCancelled {
            return "중단했어요. \(uploaded)일 올림 · \(skipped)일 건너뜀. 다시 실행하면 이어서 올립니다."
        }
        if failed > 0 {
            return "\(uploaded)일 올림 · \(skipped)일 건너뜀 · \(failed)일 실패. 다시 실행하면 실패한 날만 재시도합니다."
        }
        if uploaded == 0 {
            return "이미 모두 올라가 있어요."
        }
        return "\(uploaded)일치를 올렸어요. 이제 친구가 그 날짜의 기록도 볼 수 있습니다."
    }

    private func targetDates(range: Range) -> [Date] {
        let all = MealRecordStore.shared.datesWithDietRecords
        guard let days = range.days else { return all }

        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: Date())) else {
            return all
        }
        return all.filter { $0 >= cutoff }
    }

    private func completedDates() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: completedKey) ?? [])
    }

    private func saveCompleted(_ dates: Set<String>) {
        UserDefaults.standard.set(Array(dates), forKey: completedKey)
    }

    private func dateKey(_ date: Date) -> String {
        FriendManager.shared.dateFormatter.string(from: date)
    }
}
