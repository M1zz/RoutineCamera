//
//  SettingsManager.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/12/25.
//

import Foundation
import Combine

// 앨범 타입 정의
enum AlbumType: String, CaseIterable, Codable {
    case diet = "식단"
    case exercise = "운동"

    var symbolName: String {
        switch self {
        case .diet: return "fork.knife"
        case .exercise: return "figure.run"
        }
    }
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var albumType: AlbumType {
        didSet {
            UserDefaults.standard.set(albumType.rawValue, forKey: "albumType")
        }
    }

    @Published var autoSaveToPhotoLibrary: Bool {
        didSet {
            UserDefaults.standard.set(autoSaveToPhotoLibrary, forKey: "autoSaveToPhotoLibrary")
        }
    }
    
    @Published var writeSnack: Bool {
        didSet {
            print("writeSnack", writeSnack)
            UserDefaults.standard.set(writeSnack, forKey: "writeSnack")
        }
    }
    

    @Published var showRemainingPhotoCount: Bool {
        didSet {
            UserDefaults.standard.set(showRemainingPhotoCount, forKey: "showRemainingPhotoCount")
        }
    }

    @Published var showMemoIcon: Bool {
        didSet {
            UserDefaults.standard.set(showMemoIcon, forKey: "showMemoIcon")
        }
    }

    @Published var showAlbumSwitcher: Bool {
        didSet {
            UserDefaults.standard.set(showAlbumSwitcher, forKey: "showAlbumSwitcher")
        }
    }

    // 순간 피드(슬롯 없는 시간순 사진 일기) 사용 여부. false면 기존 격자 화면.
    @Published var useMomentsFeed: Bool {
        didSet {
            UserDefaults.standard.set(useMomentsFeed, forKey: "useMomentsFeed")
        }
    }

    // 사용자가 "챙기고 싶은" 식사 — 이 식사만 리마인드 알림을 받는다.
    // 삼시세끼 전부 알림으로 인한 스트레스를 줄이기 위함.
    @Published var caredMeals: Set<MealType> {
        didSet {
            UserDefaults.standard.set(caredMeals.map { $0.rawValue }, forKey: "caredMeals")
            // 변경 즉시 알림 재설정
            NotificationManager.shared.scheduleMealNotifications()
        }
    }

    // "챙길 식사"를 한 번이라도 골랐는지 (첫 실행 프롬프트 노출 판단)
    @Published var hasConfiguredCaredMeals: Bool {
        didSet {
            UserDefaults.standard.set(hasConfiguredCaredMeals, forKey: "hasConfiguredCaredMeals")
        }
    }

    @Published var shareMealsToCloud: Bool {
        didSet {
            UserDefaults.standard.set(shareMealsToCloud, forKey: "shareMealsToFirebase") // 기존 설정값 유지를 위해 키 이름은 그대로 둠
        }
    }

    @Published var autoOpenCamera: Bool {
        didSet {
            UserDefaults.standard.set(autoOpenCamera, forKey: "autoOpenCamera")
        }
    }

    @Published var autoFoodAnalysis: Bool {
        didSet {
            UserDefaults.standard.set(autoFoodAnalysis, forKey: "autoFoodAnalysis")
        }
    }

    // 무료 식단 분석 횟수 (기본 5회)
    @Published var freeAnalysisCount: Int {
        didSet {
            UserDefaults.standard.set(freeAnalysisCount, forKey: "freeAnalysisCount")
        }
    }

    @Published var nickname: String = "사용자" {
        didSet {
            UserDefaults.standard.set(nickname, forKey: "userNickname")
            // CloudKit에도 저장
            saveNicknameToCloud()
        }
    }

    // 앱을 처음 실행한 날 (이 날 이전의 과거 날짜는 "거른 끼니"로 판정하지 않음)
    // 한 번 저장되면 바뀌지 않음
    let appStartDate: Date

    private init() {
        // 첫 실행일 로드 또는 최초 저장 (시작일 이전 날짜를 실패로 처리하지 않기 위함)
        if let storedStart = UserDefaults.standard.object(forKey: "appStartDate") as? Date {
            self.appStartDate = storedStart
        } else {
            let today = Calendar.current.startOfDay(for: Date())
            self.appStartDate = today
            UserDefaults.standard.set(today, forKey: "appStartDate")
        }

        // 앨범 타입 로드 (기본값: 식단)
        if let albumTypeString = UserDefaults.standard.string(forKey: "albumType"),
           let albumType = AlbumType(rawValue: albumTypeString) {
            self.albumType = albumType
        } else {
            self.albumType = .diet
        }

        // 기본값은 true (기존 동작 유지)
        self.autoSaveToPhotoLibrary = UserDefaults.standard.object(forKey: "autoSaveToPhotoLibrary") as? Bool ?? true
        self.writeSnack = UserDefaults.standard.object(forKey: "writeSnack") as? Bool ?? true
        self.showRemainingPhotoCount = UserDefaults.standard.object(forKey: "showRemainingPhotoCount") as? Bool ?? true
        self.showMemoIcon = UserDefaults.standard.object(forKey: "showMemoIcon") as? Bool ?? true
        self.showAlbumSwitcher = UserDefaults.standard.object(forKey: "showAlbumSwitcher") as? Bool ?? true
        // 순간 피드 기본 ON (새 경험). 기존 격자를 원하면 설정에서 끄기.
        self.useMomentsFeed = UserDefaults.standard.object(forKey: "useMomentsFeed") as? Bool ?? true

        // 식단 공유 기본값은 true (자동 싱크 활성화)
        self.shareMealsToCloud = UserDefaults.standard.object(forKey: "shareMealsToFirebase") as? Bool ?? true

        // 자동 카메라 열기 기본값은 true (기존 동작 유지)
        self.autoOpenCamera = UserDefaults.standard.object(forKey: "autoOpenCamera") as? Bool ?? true

        // 자동 음식 분석 기본값은 false (API 비용 절약)
        self.autoFoodAnalysis = UserDefaults.standard.object(forKey: "autoFoodAnalysis") as? Bool ?? false

        // 무료 식단 분석 횟수 로드 (기본값: 5회)
        self.freeAnalysisCount = UserDefaults.standard.object(forKey: "freeAnalysisCount") as? Int ?? 5

        // 챙길 식사 로드 (기본값: 삼시세끼 — 기존 동작 유지, 프롬프트로 조정 유도)
        if let raw = UserDefaults.standard.array(forKey: "caredMeals") as? [String] {
            self.caredMeals = Set(raw.compactMap { MealType(rawValue: $0) })
        } else {
            self.caredMeals = [.breakfast, .lunch, .dinner]
        }
        self.hasConfiguredCaredMeals = UserDefaults.standard.bool(forKey: "hasConfiguredCaredMeals")

        // 닉네임 로드 (기본값: "사용자")
        self.nickname = UserDefaults.standard.string(forKey: "userNickname") ?? "사용자"

        print("⚙️ [SettingsManager] 초기화 완료")
        print("   - 식단 공유: \(self.shareMealsToCloud)")
        print("   - 자동 카메라: \(self.autoOpenCamera)")
        print("   - 자동 음식 분석: \(self.autoFoodAnalysis)")
        print("   - 무료 분석 잔여: \(self.freeAnalysisCount)회")
        print("   - 닉네임: \(self.nickname)")
    }

    // CloudKit에 닉네임 저장
    private func saveNicknameToCloud() {
        Task { @MainActor in
            do {
                try await FriendManager.shared.saveMyNickname(nickname)
                print("✅ [SettingsManager] 닉네임 CloudKit 저장 완료: \(nickname)")
            } catch {
                print("❌ [SettingsManager] 닉네임 CloudKit 저장 실패: \(error)")
            }
        }
    }
}
