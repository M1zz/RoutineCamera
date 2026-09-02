//
//  NotificationManager.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/11/25.
//

import Foundation
import UserNotifications
import Combine

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var notificationsEnabled = false

    @Published var breakfastTime: Date {
        didSet {
            saveTime(breakfastTime, forKey: "breakfastTime")
            if notificationsEnabled {
                scheduleMealNotifications()
            }
        }
    }

    @Published var lunchTime: Date {
        didSet {
            saveTime(lunchTime, forKey: "lunchTime")
            if notificationsEnabled {
                scheduleMealNotifications()
            }
        }
    }

    @Published var dinnerTime: Date {
        didSet {
            saveTime(dinnerTime, forKey: "dinnerTime")
            if notificationsEnabled {
                scheduleMealNotifications()
            }
        }
    }

    // "다 먹음" 알림 카테고리/액션 식별자 (알림에서 앱 안 열고 바로 처리)
    static let ateAllCategoryID = "ATE_ALL_REMINDER"
    static let ateAllActionID = "MARK_ATE_ALL"

    private init() {
        // 저장된 시간 불러오기 또는 기본값 설정
        self.breakfastTime = NotificationManager.loadTime(forKey: "breakfastTime") ?? NotificationManager.createTime(hour: 7, minute: 0)
        self.lunchTime = NotificationManager.loadTime(forKey: "lunchTime") ?? NotificationManager.createTime(hour: 12, minute: 0)
        self.dinnerTime = NotificationManager.loadTime(forKey: "dinnerTime") ?? NotificationManager.createTime(hour: 18, minute: 0)

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

    // 알림 권한 확인
    func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }

    // 알림 권한 요청
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

    // 식사 업로드 리마인드 알림 설정 (식사 시간 2시간 후)
    func scheduleMealNotifications() {
        // 기존 알림 삭제
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        guard notificationsEnabled else { return }

        let calendar = Calendar.current
        // 사용자가 "챙기고 싶은" 식사만 알림 (삼시세끼 전부 알림 스트레스 완화)
        let cared = SettingsManager.shared.caredMeals

        // 아침 리마인드 알림 (식사 시간 2시간 후)
        let breakfastComponents = calendar.dateComponents([.hour, .minute], from: breakfastTime)
        if cared.contains(.breakfast), let breakfastHour = breakfastComponents.hour, let breakfastMinute = breakfastComponents.minute {
            let reminderHour = (breakfastHour + 2) % 24
            scheduleReminderNotification(
                id: "breakfast-reminder",
                title: "🌅 아침 식사 기록 리마인드",
                body: "아직 아침 식사를 기록하지 않으셨네요. 지금 기록해보세요!",
                hour: reminderHour,
                minute: breakfastMinute
            )
        }

        // 점심 리마인드 알림 (식사 시간 2시간 후)
        let lunchComponents = calendar.dateComponents([.hour, .minute], from: lunchTime)
        if cared.contains(.lunch), let lunchHour = lunchComponents.hour, let lunchMinute = lunchComponents.minute {
            let reminderHour = (lunchHour + 2) % 24
            scheduleReminderNotification(
                id: "lunch-reminder",
                title: "☀️ 점심 식사 기록 리마인드",
                body: "아직 점심 식사를 기록하지 않으셨네요. 지금 기록해보세요!",
                hour: reminderHour,
                minute: lunchMinute
            )
        }

        // 저녁 리마인드 알림 (식사 시간 2시간 후)
        let dinnerComponents = calendar.dateComponents([.hour, .minute], from: dinnerTime)
        if cared.contains(.dinner), let dinnerHour = dinnerComponents.hour, let dinnerMinute = dinnerComponents.minute {
            let reminderHour = (dinnerHour + 2) % 24
            scheduleReminderNotification(
                id: "dinner-reminder",
                title: "🌙 저녁 식사 기록 리마인드",
                body: "아직 저녁 식사를 기록하지 않으셨네요. 지금 기록해보세요!",
                hour: reminderHour,
                minute: dinnerMinute
            )
        }
    }

    // 개별 리마인드 알림 스케줄링
    private func scheduleReminderNotification(id: String, title: String, body: String, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("리마인드 알림 스케줄링 오류 (\(id)): \(error)")
            } else {
                print("✅ 리마인드 알림 설정 완료 (\(id)): \(hour):\(minute)")
            }
        }
    }

    // 알림 비활성화
    func disableNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        notificationsEnabled = false
    }

    // 오늘 식사 기록 확인 후 알림 업데이트 (기록한 식사는 알림 취소)
    func updateNotificationsBasedOnRecords(meals: [MealType: MealRecord]) {
        guard notificationsEnabled else { return }

        var identifiersToRemove: [String] = []

        // 아침 기록했으면 아침 알림 취소
        if meals[.breakfast]?.isComplete ?? false {
            identifiersToRemove.append("breakfast-reminder")
        }

        // 점심 기록했으면 점심 알림 취소
        if meals[.lunch]?.isComplete ?? false {
            identifiersToRemove.append("lunch-reminder")
        }

        // 저녁 기록했으면 저녁 알림 취소
        if meals[.dinner]?.isComplete ?? false {
            identifiersToRemove.append("dinner-reminder")
        }

        if !identifiersToRemove.isEmpty {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
            print("✅ 기록된 식사 알림 취소: \(identifiersToRemove.joined(separator: ", "))")
        }
    }

    // 날짜가 바뀌었는지 확인하고 알림 재설정 (매일 자정 이후 첫 실행 시)
    func checkAndRescheduleIfNeeded() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 마지막으로 확인한 날짜 불러오기
        if let lastCheckDate = UserDefaults.standard.object(forKey: "lastNotificationCheckDate") as? Date {
            let lastCheck = calendar.startOfDay(for: lastCheckDate)

            // 날짜가 바뀌었으면 알림 재설정
            if today > lastCheck {
                print("📅 날짜 변경 감지: \(lastCheck) → \(today)")
                scheduleMealNotifications()
                UserDefaults.standard.set(today, forKey: "lastNotificationCheckDate")
            }
        } else {
            // 처음 실행 시
            UserDefaults.standard.set(today, forKey: "lastNotificationCheckDate")
        }
    }
}
