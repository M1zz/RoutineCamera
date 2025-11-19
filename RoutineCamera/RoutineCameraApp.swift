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

    return true
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
