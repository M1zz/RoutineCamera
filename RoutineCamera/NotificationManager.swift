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

    // 식사 시간 알림 설정
    func scheduleMealNotifications() {
        // 기존 알림 삭제
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        guard notificationsEnabled else { return }

        let calendar = Calendar.current

        // 아침 알림
        let breakfastComponents = calendar.dateComponents([.hour, .minute], from: breakfastTime)
        scheduleNotification(
            id: "breakfast",
            title: "🌅 아침 식사 기록",
            body: "오늘의 아침 식사 사진을 찍어보세요!",
            hour: breakfastComponents.hour ?? 7,
            minute: breakfastComponents.minute ?? 0
        )

        // 점심 알림
        let lunchComponents = calendar.dateComponents([.hour, .minute], from: lunchTime)
        scheduleNotification(
            id: "lunch",
            title: "☀️ 점심 식사 기록",
            body: "점심 식사 사진을 찍어보세요!",
            hour: lunchComponents.hour ?? 12,
            minute: lunchComponents.minute ?? 0
        )

        // 저녁 알림
        let dinnerComponents = calendar.dateComponents([.hour, .minute], from: dinnerTime)
        scheduleNotification(
            id: "dinner",
            title: "🌙 저녁 식사 기록",
            body: "저녁 식사 사진을 찍어보세요!",
            hour: dinnerComponents.hour ?? 18,
            minute: dinnerComponents.minute ?? 0
        )
    }

    // 개별 알림 스케줄링
    private func scheduleNotification(id: String, title: String, body: String, hour: Int, minute: Int) {
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
                print("알림 스케줄링 오류 (\(id)): \(error)")
            }
        }
    }

    // 알림 비활성화
    func disableNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        notificationsEnabled = false
    }
}
