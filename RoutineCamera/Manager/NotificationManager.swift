//
//  NotificationManager.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/11/25.
//

import Foundation
import UserNotifications
import Combine
import RoutineCameraCore

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    /// 시스템 알림 권한이 허용돼 있는지
    @Published var notificationsEnabled = false

    /// 식사 전 촬영 알림을 받을지 (사용자 설정).
    /// 권한과 따로 저장한다 — 예전엔 둘이 한 값이라, 껐다가 앱을 다시 열면 권한이 있다는 이유로 켜진 것처럼 보였다.
    @Published var mealRemindersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(mealRemindersEnabled, forKey: "mealRemindersEnabled")
            scheduleMealNotifications()
        }
    }

    /// 식사 시간 몇 분 전에 알릴지
    @Published var reminderLeadMinutes: Int {
        didSet {
            UserDefaults.standard.set(reminderLeadMinutes, forKey: "mealReminderLeadMinutes")
            scheduleMealNotifications()
        }
    }

    static let leadMinuteOptions = [0, 5, 10, 15, 30]

    @Published var breakfastTime: Date {
        didSet {
            saveTime(breakfastTime, forKey: "breakfastTime")
            scheduleMealNotifications()
        }
    }

    @Published var lunchTime: Date {
        didSet {
            saveTime(lunchTime, forKey: "lunchTime")
            scheduleMealNotifications()
        }
    }

    @Published var dinnerTime: Date {
        didSet {
            saveTime(dinnerTime, forKey: "dinnerTime")
            scheduleMealNotifications()
        }
    }

    /// 식사 전 알림을 눌러 들어왔을 때 열어야 할 끼니 카메라
    @Published var requestedCameraMeal: MealType?
    /// 친구 기록 알림을 눌러 들어왔을 때 친구 화면을 열어야 하는지
    @Published var requestedFriendsScreen = false

    // "다 먹음" 알림 카테고리/액션 식별자 (알림에서 앱 안 열고 바로 처리)
    static let ateAllCategoryID = "ATE_ALL_REMINDER"
    static let ateAllActionID = "MARK_ATE_ALL"
    /// 식사 전 알림의 userInfo["kind"]
    nonisolated static let mealReminderKind = "mealReminder"
    /// 예전(식사 2시간 뒤, 매일 반복) 알림 식별자 — 새 방식으로 바꾸며 지운다
    private static let legacyReminderIDs: Set<String> = ["breakfast-reminder", "lunch-reminder", "dinner-reminder"]

    /// 알림 다시 걸기를 한 줄로 세운다. 겹쳐 돌면 앞선 작업이 방금 지운 알림을 도로 걸 수 있다.
    private var reminderRefreshTask: _Concurrency.Task<Void, Never>?

    private init() {
        // 저장된 시간 불러오기 또는 기본값 설정
        self.breakfastTime = NotificationManager.loadTime(forKey: "breakfastTime") ?? NotificationManager.createTime(hour: 7, minute: 0)
        self.lunchTime = NotificationManager.loadTime(forKey: "lunchTime") ?? NotificationManager.createTime(hour: 12, minute: 0)
        self.dinnerTime = NotificationManager.loadTime(forKey: "dinnerTime") ?? NotificationManager.createTime(hour: 18, minute: 0)
        self.mealRemindersEnabled = UserDefaults.standard.object(forKey: "mealRemindersEnabled") as? Bool ?? true
        self.reminderLeadMinutes = UserDefaults.standard.object(forKey: "mealReminderLeadMinutes") as? Int ?? 10

        checkNotificationStatus()
        registerNotificationCategories()
    }

    // "다 먹음" 액션 카테고리 등록 — 알림 배너에서 앱을 열지 않고 바로 '다 먹음' 탭 가능
    func registerNotificationCategories() {
        let ateAll = UNNotificationAction(
            identifier: NotificationManager.ateAllActionID,
            title: "다 먹음",
            options: []  // .foreground 없음 = 앱 안 열고 백그라운드 처리
        )
        let category = UNNotificationCategory(
            identifier: NotificationManager.ateAllCategoryID,
            actions: [ateAll],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // 식전만 찍었을 때, 잠시 후 "다 드셨어요?" 알림 → 알림에서 바로 '다 먹음' 원탭
    func scheduleAteAllReminder(date: Date, mealType: MealType, afterMinutes: Double = 90) {
        guard notificationsEnabled else { return }
        // 식후 기록을 쓰지 않는 사용자에게는 마감을 재촉하지 않는다
        guard SettingsManager.shared.useAfterPhoto else { return }
        let content = UNMutableNotificationContent()
        content.title = "🍽️ 다 드셨어요?"
        content.body = "\(mealType.rawValue), 다 먹었으면 여기서 바로 남겨요."
        content.sound = .default
        content.categoryIdentifier = NotificationManager.ateAllCategoryID
        content.userInfo = [
            "mealType": mealType.rawValue,
            "date": date.timeIntervalSince1970
        ]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(afterMinutes * 60, 1), repeats: false)
        let dayKey = Calendar.current.startOfDay(for: date).timeIntervalSince1970
        let id = "ateall-\(mealType.rawValue)-\(dayKey)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("다먹음 리마인더 오류: \(error)")
            }
        }
    }

    // 다먹음/식후가 확정되면 해당 리마인더 취소
    func cancelAteAllReminder(date: Date, mealType: MealType) {
        let dayKey = Calendar.current.startOfDay(for: date).timeIntervalSince1970
        let id = "ateall-\(mealType.rawValue)-\(dayKey)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    // 예약돼 있는 "다 드셨어요?" 알림 전부 취소 (식후 기록을 끌 때)
    func cancelAllAteAllReminders() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix("ateall-") }
            guard !ids.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            print("🔕 [알림] 다먹음 리마인더 \(ids.count)건 취소")
        }
    }

    private static func createTime(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    private static func loadTime(forKey key: String) -> Date? {
        return UserDefaults.standard.object(forKey: key) as? Date
    }

    private func saveTime(_ time: Date, forKey key: String) {
        UserDefaults.standard.set(time, forKey: key)
    }

    // 알림 권한 확인 — 확인이 끝나면 식사 전 알림도 그 상태에 맞춰 다시 건다
    func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            DispatchQueue.main.async {
                self.notificationsEnabled = authorized
                self.scheduleMealNotifications()
            }
        }
    }

    // 알림 권한 요청 (이미 정해졌으면 다시 묻지 않고 바로 답이 온다)
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.notificationsEnabled = granted
                completion(granted)
            }

            if let error = error {
                print("알림 권한 요청 오류: \(error)")
            }
        }
    }

    // MARK: - 식사 전 촬영 알림

    /// 식사 전 촬영 알림을 앞으로 며칠 치 다시 건다.
    ///
    /// 예전엔 식사 **2시간 뒤**에 매일 반복 알림을 걸고, 기록하면 그 반복 알림을 통째로 지웠다.
    /// 그래서 한 번 기록한 끼니는 다음 날부터 알림이 오지 않았고, 다시 걸 때
    /// `removeAllPendingNotificationRequests` 로 "다 드셨어요?" 알림까지 지워졌다.
    /// 이제는 날짜별 일회성 알림을 식사 시간 전에 건다 — 오늘 기록한 끼니는 오늘 것만 빠진다.
    ///
    /// 앱을 열 때·앱으로 돌아올 때·기록이 바뀔 때·설정이 바뀔 때 부른다.
    /// - Parameter recordedToday: 오늘 이미 기록한 끼니. nil 이면 저장소에서 읽는다
    ///   (저장소가 저장 중에 부를 때는 직접 넘겨, 초기화 도중 저장소를 다시 부르지 않게 한다).
    func scheduleMealNotifications(recordedToday: Set<MealType>? = nil) {
        let calendar = Calendar.current
        var planned: [PlannedMealReminder] = []

        if notificationsEnabled && mealRemindersEnabled {
            let cared = SettingsManager.shared.caredMeals
            let slots = [(MealType.breakfast, breakfastTime), (MealType.lunch, lunchTime), (MealType.dinner, dinnerTime)]
                .filter { cared.contains($0.0) }
                .map { meal, time in
                    MealReminderSlot(mealKey: Self.key(for: meal),
                                     hour: calendar.component(.hour, from: time),
                                     minute: calendar.component(.minute, from: time))
                }
            let recorded = recordedToday ?? Self.completedMealsToday()
            planned = MealReminderPlanner.plan(slots: slots,
                                               leadMinutes: reminderLeadMinutes,
                                               now: Date(),
                                               recordedToday: Set(recorded.map { Self.key(for: $0) }),
                                               calendar: calendar)
        }

        let lead = reminderLeadMinutes
        let previous = reminderRefreshTask
        reminderRefreshTask = _Concurrency.Task {
            await previous?.value

            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let stale = pending.map(\.identifier).filter {
                $0.hasPrefix(MealReminderPlanner.identifierPrefix) || Self.legacyReminderIDs.contains($0)
            }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            for reminder in planned {
                guard let meal = Self.mealType(forKey: reminder.mealKey) else { continue }
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: reminder.identifier,
                                                    content: Self.reminderContent(for: meal, day: reminder.day, leadMinutes: lead),
                                                    trigger: trigger)
                do {
                    try await center.add(request)
                } catch {
                    print("❌ [알림] 식사 전 알림 예약 실패 (\(reminder.identifier)): \(error)")
                }
            }
            print("⏰ [알림] 식사 전 알림 \(planned.count)건 예약 (이전 \(stale.count)건 교체)")
        }
    }

    private static func reminderContent(for meal: MealType, day: Date, leadMinutes: Int) -> UNMutableNotificationContent {
        let emoji: String
        switch meal {
        case .breakfast: emoji = "🌅"
        case .lunch: emoji = "☀️"
        case .dinner: emoji = "🌙"
        default: emoji = "🍽️"
        }

        let content = UNMutableNotificationContent()
        content.title = leadMinutes == 0 ? "\(emoji) \(meal.rawValue) 시간이에요" : "\(emoji) 곧 \(meal.rawValue) 시간이에요"
        content.body = "먹기 전에 사진 한 장 남겨요. 누르면 바로 카메라가 열려요."
        content.sound = .default
        content.threadIdentifier = "meal-reminder"
        content.userInfo = [
            "kind": mealReminderKind,
            "mealType": meal.rawValue,
            "date": day.timeIntervalSince1970
        ]
        return content
    }

    /// 오늘 이미 기록을 마친 끼니 (식단 기준 — 식사 알림은 식단 전용)
    private static func completedMealsToday() -> Set<MealType> {
        Set(MealRecordStore.shared.dietMeals(for: Date()).filter { $0.value.isComplete }.keys)
    }

    // 알림 식별자에 한글이 들어가지 않도록 끼니의 영문 case 이름을 키로 쓴다
    private static func key(for meal: MealType) -> String {
        "\(meal)"
    }

    private static func mealType(forKey key: String) -> MealType? {
        MealType.allCases.first { "\($0)" == key }
    }
}
