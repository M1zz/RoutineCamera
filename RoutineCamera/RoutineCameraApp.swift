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
    // 프로덕션: App Attest 사용 (iOS 14+)
    if #available(iOS 14.0, *) {
        let providerFactory = AppAttestProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        print("🔐 [Firebase] App Check App Attest 프로바이더 활성화 (프로덕션)")
    } else {
        // iOS 14 미만: DeviceCheck 사용
        let providerFactory = DeviceCheckProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        print("🔐 [Firebase] App Check DeviceCheck 프로바이더 활성화 (프로덕션)")
    }
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

    return true
  }

  private func setupAppCheckMonitoring() {
    // App Check 토큰 가져오기 시도 (디버그 로깅용)
    #if DEBUG
    _Concurrency.Task {
      do {
        let token = try await AppCheck.appCheck().token(forcingRefresh: false)
        print("✅ [App Check] 토큰 획득 성공")
        print("   📝 토큰: \(token.token.prefix(20))...")
        print("   ⏰ 만료 시간: \(token.expirationDate)")
      } catch {
        print("❌ [App Check] 토큰 획득 실패: \(error.localizedDescription)")
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
