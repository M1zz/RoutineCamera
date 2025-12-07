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

    @Published var shareMealsToFirebase: Bool {
        didSet {
            UserDefaults.standard.set(shareMealsToFirebase, forKey: "shareMealsToFirebase")
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
            // Firebase에도 저장
            saveNicknameToFirebase()
        }
    }

    private init() {
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

        // Firebase 공유 기본값은 true (자동 싱크 활성화)
        self.shareMealsToFirebase = UserDefaults.standard.object(forKey: "shareMealsToFirebase") as? Bool ?? true

        // 자동 카메라 열기 기본값은 true (기존 동작 유지)
        self.autoOpenCamera = UserDefaults.standard.object(forKey: "autoOpenCamera") as? Bool ?? true

        // 자동 음식 분석 기본값은 false (API 비용 절약)
        self.autoFoodAnalysis = UserDefaults.standard.object(forKey: "autoFoodAnalysis") as? Bool ?? false

        // 무료 식단 분석 횟수 로드 (기본값: 5회)
        self.freeAnalysisCount = UserDefaults.standard.object(forKey: "freeAnalysisCount") as? Int ?? 5

        // 닉네임 로드 (기본값: "사용자")
        self.nickname = UserDefaults.standard.string(forKey: "userNickname") ?? "사용자"

        print("⚙️ [SettingsManager] 초기화 완료")
        print("   - Firebase 공유: \(self.shareMealsToFirebase)")
        print("   - 자동 카메라: \(self.autoOpenCamera)")
        print("   - 자동 음식 분석: \(self.autoFoodAnalysis)")
        print("   - 무료 분석 잔여: \(self.freeAnalysisCount)회")
        print("   - 닉네임: \(self.nickname)")
    }

    // Firebase에 닉네임 저장
    private func saveNicknameToFirebase() {
        // FriendManager를 통해 Firebase에 저장
        Task {
            do {
                try await FriendManager.shared.saveMyNickname(nickname)
                print("✅ [SettingsManager] 닉네임 Firebase 저장 완료: \(nickname)")
            } catch {
                print("❌ [SettingsManager] 닉네임 Firebase 저장 실패: \(error)")
            }
        }
    }
}
