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

    // App Check 설정 (디버그 모드)
    #if DEBUG
    let providerFactory = AppCheckDebugProviderFactory()
    AppCheck.setAppCheckProviderFactory(providerFactory)
    print("🔐 [Firebase] App Check 디버그 프로바이더 활성화")
    #endif

    // Firebase 초기화
    FirebaseApp.configure()
    print("🔥 [Firebase] Firebase 초기화 완료")

    // Firebase Realtime Database의 offline persistence 비활성화
    // "client offline with no active listeners" 경고 방지
    Database.database().isPersistenceEnabled = false
    print("💾 [Firebase] Offline persistence 비활성화")

    return true
  }
}
