//
//  AppLock.swift
//  RoutineCamera
//
//  앱 잠금 (세끼 프로). 켜 두면 앱이 뒤로 갔다가 돌아올 때 Face ID·Touch ID·기기 암호로 연다.
//  구독이 끝나면 잠그지 않는다 — 돈을 안 냈다고 내 기록에서 쫓겨나면 안 되므로.
//

import SwiftUI
import LocalAuthentication

enum AppLockAuthenticator {
    /// 이 기기에서 쓸 수 있는 생체 인증 이름 (설정 문구용)
    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default:       return String(localized: "기기 암호")
        }
    }

    /// 기기 암호까지 허용 — 생체 인증이 없거나 실패해도 주인이면 열 수 있다
    static func authenticate() async -> Bool {
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
