//
//  RoutineCameraApp.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/11/25.
//

import SwiftUI
import UserNotifications
import LeeoKit

@main
struct RoutineCameraApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        LeeoEngagement.shared.registerLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .leeoSatisfactionCheck(RoutineCameraSpec.self)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

    // CloudKit 피드백 푸시 수신용 원격 알림 등록
    // (CloudKit 구독 푸시는 APNs 키 업로드·서버 없이 Apple이 배달)
    application.registerForRemoteNotifications()

    // 포그라운드에서도 알림 배너 표시 (로컬 식사 리마인드에도 적용)
    UNUserNotificationCenter.current().delegate = self

    return true
  }

  func application(_ application: UIApplication,
                   didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    print("📡 [Push] 원격 알림 등록 완료")
  }

  func application(_ application: UIApplication,
                   didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ [Push] 원격 알림 등록 실패: \(error.localizedDescription)")
  }
}

// MARK: - 포그라운드에서도 푸시 배너 표시
extension AppDelegate: UNUserNotificationCenterDelegate {
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    return [.banner, .sound, .badge]
  }

  // 알림의 "다 먹음" 액션 처리 — 앱을 열지 않고 기록만 남긴다
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse) async {
    guard response.actionIdentifier == NotificationManager.ateAllActionID else { return }
    let info = response.notification.request.content.userInfo
    guard let raw = info["mealType"] as? String, let mealType = MealType(rawValue: raw) else { return }
    let date = (info["date"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) } ?? Date()
    await MainActor.run {
      MealRecordStore.shared.recordAteAll(date: date, mealType: mealType)
    }
  }
}
