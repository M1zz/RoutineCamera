//
//  SettingsManager.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/12/25.
//

import Foundation
import Combine
import RoutineCameraCore
import os

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

    /// 화면에 보이는 이름 — rawValue("식단"/"운동")는 저장값이라 그대로 두고, 화면에는 이것을 쓴다
    var displayName: String {
        switch self {
        case .diet: return String(localized: "식단", comment: "Album name: meal log")
        case .exercise: return String(localized: "운동", comment: "Album name: workout log")
        }
    }

    /// 친구 화면에서 쓰는 이름 ("식단"보다 "음식"이 운동과 나란히 놓였을 때 읽기 쉽다)
    var shareTitle: String {
        switch self {
        case .diet: return String(localized: "음식", comment: "Friends screen tab: friends' food entries")
        case .exercise: return String(localized: "운동", comment: "Album name: workout log")
        }
    }

    /// 사진 앱에 만드는 앨범 이름 (사용자 언어로)
    var photoAlbumName: String {
        switch self {
        case .diet: return String(localized: "세끼식단", comment: "Photos album name for meal photos")
        case .exercise: return String(localized: "세끼운동", comment: "Photos album name for workout photos")
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

    // 저장되는 설정은 한 줄씩 — 기본값 · 저장 · 화면 갱신은 @Stored 가 맡는다

    // 기록 저장소가 바뀜을 구독하므로 이것만 @Published 로 둔다
    @Published var albumType: AlbumType = Stored.load("albumType", default: .diet) {
        didSet { UserDefaults.standard.set(albumType.rawValue, forKey: "albumType") }
    }
    @Stored("autoSaveToPhotoLibrary") var autoSaveToPhotoLibrary = true
    /// 찍은 곳 함께 남기기 (기본 끔 — 켤 때 위치 권한을 묻는다)
    @Stored("recordPlace") var recordPlace = false
    @Stored("writeSnack") var writeSnack = true

    // 사진 왼쪽 아래에 새기는 날짜 도장 (MealPhotoStamp). 기본값은 예전과 같은 모양 — 켬 · 기본 글꼴 · 시간 포함
    @Stored("photoStampEnabled") var photoStampEnabled = true
    @Stored("photoStampFont") var photoStampFont = MealStampFont.system
    @Stored("photoStampShowsTime") var photoStampShowsTime = true

    // 식후 사진을 남길지. 끄면 식전 한 장으로 기록이 끝나고,
    // 식후 촬영 안내·"다 드셨어요?" 알림·남은 사진 뱃지가 모두 사라진다.
    @Stored("useAfterPhoto") var useAfterPhoto = true {
        didSet {
            // 이미 예약된 "다 드셨어요?" 알림도 정리한다
            if !useAfterPhoto { NotificationManager.shared.cancelAllAteAllReminders() }
        }
    }

    @Stored("showRemainingPhotoCount") var showRemainingPhotoCount = true
    @Stored("showMemoIcon") var showMemoIcon = true
    @Stored("showAlbumSwitcher") var showAlbumSwitcher = true
    // 순간 피드(슬롯 없는 시간순 사진 일기) 사용 여부. false면 격자 화면.
    @Stored("useMomentsFeed") var useMomentsFeed = true

    // 사용자가 "챙기고 싶은" 식사 — 이 식사만 리마인드 알림을 받는다.
    // 삼시세끼 전부 알림으로 인한 스트레스를 줄이기 위함.
    @Published var caredMeals: Set<MealType> {
        didSet {
            UserDefaults.standard.set(caredMeals.map { $0.rawValue }, forKey: "caredMeals")
            // 변경 즉시 알림 재설정
            NotificationManager.shared.scheduleMealNotifications()
            // 위젯의 아침·점심·저녁 체크도 바뀐 끼니로
            MealRecordStore.shared.publishWidgetSnapshot()
        }
    }

    // "챙길 식사"를 한 번이라도 골랐는지 (첫 실행 프롬프트 노출 판단)
    @Stored("hasConfiguredCaredMeals") var hasConfiguredCaredMeals = false
    // 키 이름은 예전 그대로 둔다 — 바꾸면 이미 끈 사람의 설정이 사라진다
    @Stored("shareMealsToFirebase") var shareMealsToCloud = true
    @Stored("autoOpenCamera") var autoOpenCamera = true
    @Stored("autoFoodAnalysis") var autoFoodAnalysis = false
    // 앱 잠금 (세끼 프로) — 앱을 열 때 Face ID·Touch ID·기기 암호를 묻는다
    @Stored("appLockEnabled") var appLockEnabled = false

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

    /// 친구에게 보일 이름을 직접 정했는지 — 안 정했으면 친구 화면이 처음 한 번 묻는다
    var hasChosenNickname: Bool {
        UserDefaults.standard.string(forKey: "userNickname") != nil && displayNickname != "사용자"
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

        // 챙길 식사 로드 (기본값: 삼시세끼 — 기존 동작 유지, 프롬프트로 조정 유도)
        if let raw = UserDefaults.standard.array(forKey: "caredMeals") as? [String] {
            self.caredMeals = Set(raw.compactMap { MealType(rawValue: $0) })
        } else {
            self.caredMeals = [.breakfast, .lunch, .dinner]
        }

        // 닉네임 로드 (기본값: "사용자")
        self.nickname = UserDefaults.standard.string(forKey: "userNickname") ?? "사용자"
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
                Log.friends.info("닉네임 CloudKit 저장 완료: \(self.nickname)")
            } catch {
                Log.friends.error("닉네임 CloudKit 저장 실패: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - 저장되는 설정 한 칸

/// UserDefaults 에 저장되는 설정 한 칸. 읽을 때 저장된 값(없으면 기본값), 쓸 때 저장하고 화면에 알린다.
/// `@Published` + `didSet { UserDefaults.set }` 을 칸마다 되풀이하던 것을 한 곳으로 모았다.
/// 저장할 수 있는 값: Bool · String · Int · Double, 또는 그런 원시값을 가진 enum.
@propertyWrapper
struct Stored<Value: StoredValue> {
    let key: String
    private var value: Value

    init(wrappedValue defaultValue: Value, _ key: String) {
        self.key = key
        self.value = Self.load(key, default: defaultValue)
    }

    static func load(_ key: String, default defaultValue: Value) -> Value {
        UserDefaults.standard.object(forKey: key).flatMap(Value.init(storedObject:)) ?? defaultValue
    }

    @available(*, unavailable, message: "@Stored 는 ObservableObject 클래스 안에서만 쓴다")
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    static subscript<Owner: ObservableObject>(
        _enclosingInstance owner: Owner,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<Owner, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<Owner, Stored<Value>>
    ) -> Value where Owner.ObjectWillChangePublisher == ObservableObjectPublisher {
        get { owner[keyPath: storageKeyPath].value }
        set {
            owner.objectWillChange.send()
            owner[keyPath: storageKeyPath].value = newValue
            UserDefaults.standard.set(newValue.storedObject, forKey: owner[keyPath: storageKeyPath].key)
        }
    }
}

/// UserDefaults 에 그대로 넣고 꺼낼 수 있는 값
protocol StoredValue {
    init?(storedObject: Any)
    var storedObject: Any { get }
}

extension Bool: StoredValue {
    init?(storedObject: Any) { guard let v = storedObject as? Bool else { return nil }; self = v }
    var storedObject: Any { self }
}

extension String: StoredValue {
    init?(storedObject: Any) { guard let v = storedObject as? String else { return nil }; self = v }
    var storedObject: Any { self }
}

extension StoredValue where Self: RawRepresentable, RawValue == String {
    init?(storedObject: Any) {
        guard let raw = storedObject as? String else { return nil }
        self.init(rawValue: raw)
    }
    var storedObject: Any { rawValue }
}

extension AlbumType: StoredValue {}
