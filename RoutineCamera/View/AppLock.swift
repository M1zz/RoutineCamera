//
//  AppLock.swift
//  RoutineCamera
//
//  앱 잠금 (세끼 프로). 켜 두면 앱이 뒤로 갔다가 돌아올 때 Face ID·Touch ID·기기 암호로 연다.
//  구독이 끝나면 잠그지 않는다 — 돈을 안 냈다고 내 기록에서 쫓겨나면 안 되므로.
//

import SwiftUI
import LocalAuthentication
import LeeoKit

/// 메인 액터에 묶지 않는다. LAContext 는 물을 때마다 시스템과 동기로 왕복하는데,
/// 1.2.2 에서 잠금 화면을 그리는 중(메인)에 그 왕복이 막혀 워치독에 죽었다.
nonisolated enum AppLockAuthenticator {
    /// 이 기기에서 쓸 수 있는 생체 인증 이름 (설정 · 잠금 화면 문구용).
    /// 한 번만 묻는다 — 기기의 생체 인증 종류는 실행 중에 바뀌지 않는다.
    static let biometryName: String = {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default:       return String(localized: "기기 암호")
        }
    }()

    /// 앱 시작 때 백그라운드에서 미리 물어 둔다. 화면이 처음 읽을 때는 이미 답이 있다.
    static func warmUp() {
        DispatchQueue.global(qos: .utility).async { _ = biometryName }
    }

    /// 기기 암호까지 허용 — 생체 인증이 없거나 실패해도 주인이면 열 수 있다
    /// 메인 밖에서 돈다(@concurrent) — canEvaluatePolicy 도 시스템 왕복이다.
    @concurrent static func authenticate() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // 기기 암호조차 없으면 잠글 방법이 없다 — 열어 준다
            return true
        }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                  localizedReason: String(localized: "세끼 잠금 해제"))) ?? false
    }
}

private struct AppLockOverlay: ViewModifier {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var subscription = SubscriptionManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLocked = true
    @State private var isAuthenticating = false

    private var lockActive: Bool { settings.appLockEnabled && subscription.allows(.appLock) }

    func body(content: Content) -> some View {
        content
            .overlay {
                if lockActive && isLocked {
                    lockScreen
                        // 아이폰 듀오를 펴도 잠금 안내가 접힌 선 위에 서지 않게 고르는 쪽 판에
                        .foldConfined()
                        .transition(.opacity)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard lockActive else { return }
                switch phase {
                case .background:
                    isLocked = true
                case .active:
                    if isLocked { unlock() }
                default:
                    break
                }
            }
            .onAppear {
                if lockActive { unlock() } else { isLocked = false }
            }
            .onChange(of: settings.appLockEnabled) { _, enabled in
                // 방금 켠 사람을 바로 잠그지 않는다 — 다음에 돌아올 때부터
                if enabled { isLocked = false }
            }
    }

    private var lockScreen: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                Text("세끼가 잠겨 있어요")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Button {
                    unlock()
                } label: {
                    Label("\(AppLockAuthenticator.biometryName)로 열기", systemImage: "faceid")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundColor(.white)
                }
                .disabled(isAuthenticating)
            }
            .padding(32)
        }
    }

    private func unlock() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task {
            let ok = await AppLockAuthenticator.authenticate()
            withAnimation(.easeOut(duration: 0.2)) {
                isLocked = !ok
            }
            isAuthenticating = false
        }
    }
}

extension View {
    func appLockOverlay() -> some View {
        modifier(AppLockOverlay())
    }
}
