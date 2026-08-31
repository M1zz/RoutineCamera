//
//  FriendMealCache.swift
//  RoutineCamera
//
//  친구·그룹 식단의 로컬 영구 캐시
//
//  설계 의도
//  - **지난 날짜의 기록은 바뀌지 않는다** → 한 번 받아오면 만료 없이 계속 쓴다.
//    오늘/최근 3일만 짧게 만료시켜 새 기록을 반영한다.
//  - **기록이 없는 날도 "없음"으로 캐시**한다. 그러지 않으면 빈 날을 화면에 들를 때마다
//    CloudKit에 다시 물어보게 된다.
//  - 사진은 JSON 옆에 파일로 저장하고, 캐시 디렉터리는 시스템이 임의로 지우는
//    Caches가 아니라 Application Support에 둔다 (iCloud 백업에서는 제외).
//  - 사진이 쌓이므로 총 용량 상한을 두고, 넘으면 오래 전에 받은 것부터 통째로 지운다.
//

import Foundation

final class FriendMealCache {
    static let shared = FriendMealCache()

    /// 총 용량 상한. 넘으면 오래된 항목부터 정리한다.
    private let budgetBytes = 300 * 1024 * 1024
    /// 정리 시 여기까지 줄인다
    private let budgetLowWatermark = 0.7

    private let root: URL
    private let fileManager = FileManager.default
    private var savesSinceCleanup = 0

    private init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent("FriendMealsCache", isDirectory: true)

        migrateFromCachesDirectoryIfNeeded()

        if !fileManager.fileExists(atPath: root.path) {
            try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        excludeFromBackup()
    }

    // MARK: - 읽기 / 쓰기

    /// 캐시된 기록. 없거나 만료됐으면 nil.
    /// 빈 딕셔너리는 "그 날은 기록이 없다"는 캐시된 사실이다.
    func load(friendId: String, dateString: String, date: Date) -> [MealType: MealRecord]? {
        let key = Self.cacheKey(friendId: friendId, dateString: dateString)
        let fileURL = root.appendingPathComponent("\(key).json")

        guard let data = try? Data(contentsOf: fileURL),
              let cached = try? JSONDecoder().decode(CachedMealsData.self, from: data) else {
            return nil
        }

        guard isFresh(cachedAt: cached.cachedAt, recordDate: date) else {
            remove(key: key)
            return nil
        }

        var meals: [MealType: MealRecord] = [:]
        for (rawMealType, info) in cached.meals {
            guard let mealType = MealType(rawValue: rawMealType) else { continue }

            let beforeData = info.beforeImageFileName.flatMap { try? Data(contentsOf: root.appendingPathComponent($0)) }
            let afterData = info.afterImageFileName.flatMap { try? Data(contentsOf: root.appendingPathComponent($0)) }

            meals[mealType] = MealRecord(
                date: info.date,
                mealType: mealType,
                beforeImageData: beforeData,
                afterImageData: afterData,
                memo: info.memo,
                recordedWithoutPhoto: false,
                hidePhotoCountBadge: false,
                capturedAt: info.capturedAt
            )
        }
        return meals
    }

    /// 기록 저장. **빈 값도 저장**해서 기록 없는 날을 다시 조회하지 않게 한다.
    func save(friendId: String, dateString: String, meals: [MealType: MealRecord]) {
        let key = Self.cacheKey(friendId: friendId, dateString: dateString)
        var mealsInfo: [String: CachedMealInfo] = [:]

        for (mealType, record) in meals {
            var beforeImageFileName: String?
            var afterImageFileName: String?

            if let beforeData = record.beforeImageData {
                let name = "\(key)_\(mealType.rawValue)_before.jpg"
                if (try? beforeData.write(to: root.appendingPathComponent(name))) != nil {
                    beforeImageFileName = name
                }
            }
            if let afterData = record.afterImageData {
                let name = "\(key)_\(mealType.rawValue)_after.jpg"
                if (try? afterData.write(to: root.appendingPathComponent(name))) != nil {
                    afterImageFileName = name
                }
            }

            mealsInfo[mealType.rawValue] = CachedMealInfo(
                date: record.date,
                memo: record.memo,
                beforeImageFileName: beforeImageFileName,
                afterImageFileName: afterImageFileName,
                capturedAt: record.capturedAt
            )
        }

        let payload = CachedMealsData(meals: mealsInfo, cachedAt: Date())
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: root.appendingPathComponent("\(key).json"))

        savesSinceCleanup += 1
        if savesSinceCleanup >= 50 {
            savesSinceCleanup = 0
            enforceBudget()
        }
    }

    /// 특정 날짜 캐시 무효화 (강제 새로고침용)
    func invalidate(friendId: String, dateString: String) {
        remove(key: Self.cacheKey(friendId: friendId, dateString: dateString))
    }

    func clearAll() {
        guard let files = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? fileManager.removeItem(at: file)
        }
        print("🗑️ [캐시] 전체 삭제 완료")
    }

    var totalBytes: Int {
        guard let files = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    // MARK: - 만료 정책

    /// 지난 날짜의 기록은 더 이상 바뀌지 않으므로 만료시키지 않는다.
    private func isFresh(cachedAt: Date, recordDate: Date) -> Bool {
        let age = Date().timeIntervalSince(cachedAt)
        let dayGap = Calendar.current.dateComponents([.day],
                                                     from: Calendar.current.startOfDay(for: recordDate),
                                                     to: Calendar.current.startOfDay(for: Date())).day ?? 0
        switch dayGap {
        case ..<1:   return age < 15 * 60        // 오늘 — 15분
        case 1...3:  return age < 6 * 60 * 60    // 최근 3일 — 6시간
        default:     return true                  // 그 이전 — 만료 없음
        }
    }

    // MARK: - 용량 관리

    /// 상한을 넘으면 오래 전에 받은 항목부터(JSON + 사진 통째로) 지운다.
    func enforceBudget() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        var total = 0
        var entries: [(key: String, bytes: Int, modified: Date)] = []
        var sizes: [String: Int] = [:]
        var dates: [String: Date] = [:]

        for file in files {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let bytes = values?.fileSize ?? 0
            let modified = values?.contentModificationDate ?? .distantPast
            total += bytes

            let key = Self.groupKey(fileName: file.lastPathComponent)
            sizes[key, default: 0] += bytes
            dates[key] = min(dates[key] ?? modified, modified)
        }

        guard total > budgetBytes else { return }

        entries = sizes.map { (key: $0.key, bytes: $0.value, modified: dates[$0.key] ?? .distantPast) }
            .sorted { $0.modified < $1.modified }

        let target = Int(Double(budgetBytes) * budgetLowWatermark)
        var freed = 0

        for entry in entries {
            guard total - freed > target else { break }
            remove(key: entry.key)
            freed += entry.bytes
        }

        print("🧹 [캐시] 용량 정리: \(total / 1024 / 1024)MB → \((total - freed) / 1024 / 1024)MB")
    }

    // MARK: - 내부

    private func remove(key: String) {
        guard let files = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix(key) {
            try? fileManager.removeItem(at: file)
        }
    }

    private static func cacheKey(friendId: String, dateString: String) -> String {
        "\(friendId)_\(dateString)"
    }

    /// 파일 이름에서 (친구, 날짜) 단위 키를 뽑는다. 사진 파일은 "<키>_<끼니>_before.jpg" 형태.
    private static func groupKey(fileName: String) -> String {
        if fileName.hasSuffix(".json") { return String(fileName.dropLast(".json".count)) }
        for suffix in ["_before.jpg", "_after.jpg"] where fileName.hasSuffix(suffix) {
            let withoutSuffix = String(fileName.dropLast(suffix.count))
            // 끼니 이름 한 조각을 더 떼어낸다
            if let range = withoutSuffix.range(of: "_", options: .backwards) {
                return String(withoutSuffix[withoutSuffix.startIndex..<range.lowerBound])
            }
            return withoutSuffix
        }
        return fileName
    }

    /// 예전 위치(Caches)의 캐시를 그대로 옮겨온다. Caches는 시스템이 임의로 지운다.
    private func migrateFromCachesDirectoryIfNeeded() {
        let legacy = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FriendMealsCache", isDirectory: true)

        guard fileManager.fileExists(atPath: legacy.path),
              !fileManager.fileExists(atPath: root.path) else { return }

        do {
            try fileManager.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: legacy, to: root)
            print("📦 [캐시] Caches → Application Support 이관 완료")
        } catch {
            print("❌ [캐시] 이관 실패: \(error.localizedDescription)")
        }
    }

    private func excludeFromBackup() {
        var url = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
