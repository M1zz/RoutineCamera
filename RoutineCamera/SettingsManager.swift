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

    /// 친구 화면에서 쓰는 이름 ("식단"보다 "음식"이 운동과 나란히 놓였을 때 읽기 쉽다)
    var shareTitle: String {
        switch self {
        case .diet: return "음식"
        case .exercise: return "운동"
        }
    }

    /// CloudKit `Meal` 레코드 이름의 접미사.
    ///
    /// 식단은 **접미사가 없다** — 1.0.7까지 올라간 레코드가 그 이름이라 그대로 둬야
    /// 아직 업데이트하지 않은 친구의 앱에서도 계속 보인다.
    /// 운동은 `_ex` 를 붙여 같은 날 같은 끼니라도 식단과 겹치지 않게 한다.
    /// (레코드는 쿼리가 아니라 이름으로 직접 가져오므로 운영 스키마를 건드릴 필요가 없다)
    var recordSuffix: String {
        switch self {
        case .diet: return ""
        case .exercise: return "_ex"
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
    

    // 식후 사진을 남길지. 끄면 식전 한 장으로 기록이 끝나고,
    // 식후 촬영 안내·"다 드셨어요?" 알림·남은 사진 뱃지가 모두 사라진다.
    @Published var useAfterPhoto: Bool {
        didSet {
            UserDefaults.standard.set(useAfterPhoto, forKey: "useAfterPhoto")
            if !useAfterPhoto {
                // 이미 예약된 "다 드셨어요?" 알림도 정리한다
                NotificationManager.shared.cancelAllAteAllReminders()
            }
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

    // 친구·그룹 화면에서 상대에게 보이는 이름
    @Published var nickname: String = "사용자" {
        didSet {
            guard nickname != oldValue else { return }
            UserDefaults.standard.set(nickname, forKey: "userNickname")
            // CloudKit에도 저장 (한 글자마다 올리지 않도록 잠시 모았다가)
            scheduleNicknameSync()
        }
    }

    /// 화면에 표시할 이름. 공백만 남았거나 비어 있으면 기본값으로 보여준다.
    var displayNickname: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "사용자" : trimmed
    }

    /// 편집을 마쳤을 때 부르는 커밋. 앞뒤 공백을 정리하고, 빈 이름은 기본값으로 되돌린다.
    func commitNickname(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        nickname = trimmed.isEmpty ? "사용자" : String(trimmed.prefix(20))
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
        // 기본값 true (기존 식전·식후 흐름 유지)
        self.useAfterPhoto = UserDefaults.standard.object(forKey: "useAfterPhoto") as? Bool ?? true
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

    // 타이핑 중에는 CloudKit 왕복을 하지 않는다 — 마지막 입력에서 1초 쉬면 그때 한 번만 올린다
    private var nicknameSyncTask: Task<Void, Never>?

    private func scheduleNicknameSync() {
        nicknameSyncTask?.cancel()
        nicknameSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.saveNicknameToCloud()
        }
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
