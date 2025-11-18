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

    private init() {
        // 저장된 시간 불러오기 또는 기본값 설정
        self.breakfastTime = NotificationManager.loadTime(forKey: "breakfastTime") ?? NotificationManager.createTime(hour: 7, minute: 0)
        self.lunchTime = NotificationManager.loadTime(forKey: "lunchTime") ?? NotificationManager.createTime(hour: 12, minute: 0)
        self.dinnerTime = NotificationManager.loadTime(forKey: "dinnerTime") ?? NotificationManager.createTime(hour: 18, minute: 0)

        checkNotificationStatus()
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

        // 아침 리마인드 알림 (식사 시간 2시간 후)
        let breakfastComponents = calendar.dateComponents([.hour, .minute], from: breakfastTime)
        if let breakfastHour = breakfastComponents.hour, let breakfastMinute = breakfastComponents.minute {
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
        if let lunchHour = lunchComponents.hour, let lunchMinute = lunchComponents.minute {
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
        if let dinnerHour = dinnerComponents.hour, let dinnerMinute = dinnerComponents.minute {
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
