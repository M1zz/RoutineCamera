//
//  RoutineCameraApp.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/11/25.
//

import SwiftUI
import UserNotifications
import CloudKit
import LeeoKit

@main
struct RoutineCameraApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 사용량 기록 · 크래시 진단 · 익명 사용 통계. 실패해도 앱 동작에는 영향이 없다.
        LeeoKit.bootstrap(RoutineCameraSpec.self)
        // 세끼 프로 — 시작할 때 스토어를 띄워 구독 권한과 갱신(환불·만료·다른 기기 구매)을 계속 따라간다
        _ = SubscriptionManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .leeoSatisfactionCheck(RoutineCameraSpec.self)
                .appLockOverlay()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await SubscriptionManager.shared.refresh() }
                // 받은 친구 요청 점이 앱을 다시 열 때마다 맞도록
                Task { await FriendManager.shared.refreshSocialGraph() }
            }
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

    #if DEBUG
    if let dir = ProcessInfo.processInfo.environment["SEED_SCREENSHOT_DIR"] {
        SettingsManager.shared.albumType = .exercise
        MealRecordStore.shared.clearAllData()
        SettingsManager.shared.albumType = .diet
        MealRecordStore.shared.generateScreenshotData(photoDirectory: dir)
    }
    #endif

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

  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse) async {
    let info = response.notification.request.content.userInfo

    if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
      // 친구 기록 알림(CloudKit 푸시)을 누르면 친구 화면으로
      if let notification = CKNotification(fromRemoteNotificationDictionary: info),
         notification.subscriptionID?.hasPrefix(FriendManager.friendMealSubscriptionPrefix) == true {
        await MainActor.run { NotificationManager.shared.requestedFriendsScreen = true }
        return
      }

      // 식사 전 알림을 누르면 그 끼니 카메라를 바로 연다
      if info["kind"] as? String == NotificationManager.mealReminderKind,
         let raw = info["mealType"] as? String, let mealType = MealType(rawValue: raw) {
        await MainActor.run { NotificationManager.shared.requestedCameraMeal = mealType }
        return
      }
    }

    // 알림의 "다 먹음" 액션 처리 — 앱을 열지 않고 기록만 남긴다
    guard response.actionIdentifier == NotificationManager.ateAllActionID else { return }
    guard let raw = info["mealType"] as? String, let mealType = MealType(rawValue: raw) else { return }
    let date = (info["date"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) } ?? Date()
    await MainActor.run {
      MealRecordStore.shared.recordAteAll(date: date, mealType: mealType)
    }
  }
}
