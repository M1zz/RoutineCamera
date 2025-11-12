//
//  SettingsManager.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/12/25.
//

import Foundation
import Combine

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

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

    private init() {
        // 기본값은 true (기존 동작 유지)
        self.autoSaveToPhotoLibrary = UserDefaults.standard.object(forKey: "autoSaveToPhotoLibrary") as? Bool ?? true
        self.showRemainingPhotoCount = UserDefaults.standard.object(forKey: "showRemainingPhotoCount") as? Bool ?? true
        self.showMemoIcon = UserDefaults.standard.object(forKey: "showMemoIcon") as? Bool ?? true
    }
}
