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

    @Published var autoFoodAnalysis: Bool {
        didSet {
            UserDefaults.standard.set(autoFoodAnalysis, forKey: "autoFoodAnalysis")
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
        self.showRemainingPhotoCount = UserDefaults.standard.object(forKey: "showRemainingPhotoCount") as? Bool ?? true
        self.showMemoIcon = UserDefaults.standard.object(forKey: "showMemoIcon") as? Bool ?? true
        self.showAlbumSwitcher = UserDefaults.standard.object(forKey: "showAlbumSwitcher") as? Bool ?? true

        // 자동 음식 분석 기본값은 false (API 비용 절약)
        self.autoFoodAnalysis = UserDefaults.standard.object(forKey: "autoFoodAnalysis") as? Bool ?? false
    }
}
