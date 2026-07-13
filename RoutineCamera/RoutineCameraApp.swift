//
//  RoutineCameraApp.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/11/25.
//

import SwiftUI
import FirebaseCore
import FirebaseDatabase
import FirebaseAppCheck
import FirebaseMessaging
import UserNotifications

@main
struct RoutineCameraApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {

  // 피드백 푸시(FCM) 사용 여부.
  // 활성화 조건: ① Firebase Console에 APNs 키 등록 ② Blaze 전환 + functions 배포
  // ③ entitlements에 aps-environment 추가 (FIREBASE_SETUP.md "피드백 푸시 알림 설정" 참고)
  // 조건이 안 갖춰진 상태에서 켜면 실기기 서명/푸시 등록이 실패하므로 꺼 둠
  static let feedbackPushEnabled = false

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

    // App Check 설정
    #if DEBUG
    // 디버그 환경: Debug Provider 사용
    let providerFactory = AppCheckDebugProviderFactory()
    AppCheck.setAppCheckProviderFactory(providerFactory)
    print("🔐 [Firebase] App Check 디버그 프로바이더 활성화")
    print("   💡 디버그 토큰은 Xcode 콘솔에 출력됩니다")
    #else
    // 프로덕션: DeviceCheck 사용 (iOS 11+)
    let providerFactory = DeviceCheckProviderFactory()
    AppCheck.setAppCheckProviderFactory(providerFactory)
    print("🔐 [Firebase] App Check DeviceCheck 프로바이더 활성화 (프로덕션)")
    #endif

    // Firebase 초기화
    FirebaseApp.configure()
    print("🔥 [Firebase] Firebase 초기화 완료")

    // Firebase Realtime Database의 offline persistence 비활성화
    // "client offline with no active listeners" 경고 방지
    Database.database().isPersistenceEnabled = false
    print("💾 [Firebase] Offline persistence 비활성화")

    // App Check 토큰 모니터링 (디버그용)
    setupAppCheckMonitoring()

    // FCM(서버 경유) 푸시 — Firebase 콘솔 설정(APNs 키/Blaze) 완료 전까지 비활성화
    if Self.feedbackPushEnabled {
      Messaging.messaging().delegate = self
      print("📬 [FCM] 피드백 푸시 활성화")
    } else {
      print("📬 [FCM] 피드백 푸시 비활성화 상태 (feedbackPushEnabled = false)")
    }

    // CloudKit 피드백 핑 푸시 수신용 원격 알림 등록
    // (CloudKit 구독 푸시는 APNs 키 업로드 없이 Apple이 배달하므로 항상 등록)
    application.registerForRemoteNotifications()

    // 포그라운드에서도 알림 배너 표시 (로컬 식사 리마인드에도 적용)
    UNUserNotificationCenter.current().delegate = self

    return true
  }

  // APNs 토큰 → FCM에 전달
  func application(_ application: UIApplication,
                   didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Messaging.messaging().apnsToken = deviceToken
    print("📬 [FCM] APNs 토큰 등록 완료")
  }

  func application(_ application: UIApplication,
                   didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ [FCM] APNs 등록 실패: \(error.localizedDescription)")
  }

  private func setupAppCheckMonitoring() {
    // App Check 토큰 가져오기 시도 (디버그 로깅용)
    #if DEBUG
    _Concurrency.Task {
      do {
        // 디버그 토큰 강제 새로고침으로 콘솔에 출력
        let token = try await AppCheck.appCheck().token(forcingRefresh: true)
        print("✅ [App Check] 토큰 획득 성공")
        print("   📝 토큰: \(token.token.prefix(20))...")
        print("   ⏰ 만료 시간: \(token.expirationDate)")
        print("")
        print("⚠️ ================================================================")
        print("⚠️ 디버그 토큰을 Firebase Console에 등록하세요!")
        print("⚠️ 1. Firebase Console → App Check → Debug tokens")
        print("⚠️ 2. 위의 'Debug token:' 메시지에서 토큰 복사")
        print("⚠️ 3. Firebase Console에 등록")
        print("⚠️ ================================================================")
        print("")
      } catch {
        print("❌ [App Check] 토큰 획득 실패: \(error.localizedDescription)")
        print("")
        print("🔥 ================================================================")
        print("🔥 Firebase App Check 403 에러 해결 방법:")
        print("🔥 ")
        print("🔥 1. Firebase Console (console.firebase.google.com)")
        print("🔥 2. 프로젝트: sekki-24285")
        print("🔥 3. Build → App Check")
        print("🔥 4. Realtime Database의 'Enforcement'를 OFF로 변경")
        print("🔥    또는 'Monitor' 모드로 변경")
        print("🔥 ")
        print("🔥 또는 디버그 토큰을 등록하세요:")
        print("🔥 - Xcode 콘솔에서 'Debug token:' 검색")
        print("🔥 - Firebase Console → App Check → Debug tokens에 등록")
        print("🔥 ================================================================")
        print("")

        if let nsError = error as NSError? {
          print("   🔍 에러 코드: \(nsError.code)")
          print("   🔍 에러 도메인: \(nsError.domain)")
          print("   🔍 상세 정보: \(nsError.userInfo)")
        }
      }
    }
    #else
    // 프로덕션에서도 기본 로깅
    _Concurrency.Task {
      do {
        let token = try await AppCheck.appCheck().token(forcingRefresh: false)
        print("✅ [App Check] 토큰 획득 성공 (만료: \(token.expirationDate))")
      } catch {
        print("❌ [App Check] 토큰 획득 실패: \(error.localizedDescription)")
      }
    }
    #endif
  }
}

// MARK: - FCM 토큰 수신
extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    guard let token = fcmToken else { return }
    print("📬 [FCM] 토큰 수신: \(token.prefix(16))...")
    // 로그인 전이면 보관해 두었다가 로그인 시 업로드됨
    _Concurrency.Task { @MainActor in
      FriendManager.shared.saveFCMToken(token)
    }
  }
}

// MARK: - 포그라운드에서도 푸시 배너 표시
extension AppDelegate: UNUserNotificationCenterDelegate {
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    return [.banner, .sound, .badge]
  }
}
