//
//  DynamicIslandOverlay.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/18/25.
//

import SwiftUI
import UIKit
import Combine

// 다이나믹 아일랜드 위를 걷는 캐릭터 오버레이
@available(iOS 16.1, *)
class DynamicIslandOverlayManager {
    static let shared = DynamicIslandOverlayManager()

    private var overlayWindow: UIWindow?
    private var hostingController: UIHostingController<DynamicIslandCharacterView>?
    private var walkTimer: Timer?
    private weak var mealStore: MealStore?
    private weak var settingsManager: SettingsManager?

    private init() {}

    // 오버레이 시작
    func start(mealStore: MealStore, settingsManager: SettingsManager) {
        print("🚀 [DynamicIslandOverlay] start() 함수 호출됨!")

        guard overlayWindow == nil else {
            print("⚠️ [DynamicIslandOverlay] 이미 오버레이가 존재함, overlayWindow: \(String(describing: overlayWindow))")
            return
        }

        print("🎬 [DynamicIslandOverlay] 오버레이 시작 시도...")

        // 메인 스레드에서 실행
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                print("❌ [DynamicIslandOverlay] self가 nil임")
                return
            }

            // 모든 씬 확인
            let scenes = UIApplication.shared.connectedScenes
            print("📱 [DynamicIslandOverlay] 연결된 씬 개수: \(scenes.count)")

            for (index, scene) in scenes.enumerated() {
                print("   씬 \(index): \(type(of: scene)), activationState: \(scene.activationState.rawValue)")
            }

            // 윈도우 씬 찾기
            guard let windowScene = scenes.first as? UIWindowScene else {
                print("❌ [DynamicIslandOverlay] WindowScene을 찾을 수 없음")
                return
            }

            print("✅ [DynamicIslandOverlay] WindowScene 발견!")
            print("   - coordinateSpace: \(windowScene.coordinateSpace.bounds)")
            print("   - windows 개수: \(windowScene.windows.count)")

            // 새 윈도우 생성
            let window = UIWindow(windowScene: windowScene)
            window.windowLevel = .statusBar + 1 // 상태바 위에 표시
            window.backgroundColor = .clear
            window.isUserInteractionEnabled = false // 터치 이벤트 통과

            // 참조 저장
            self.mealStore = mealStore
            self.settingsManager = settingsManager

            // SwiftUI 뷰를 UIHostingController로 감싸기
            let characterView = DynamicIslandCharacterView(
                mealStore: mealStore,
                settingsManager: settingsManager
            )
            let hostingController = UIHostingController(rootView: characterView)
            hostingController.view.backgroundColor = .clear

            window.rootViewController = hostingController
            window.isHidden = false // 윈도우 보이기
            window.makeKeyAndVisible() // 명확하게 보이도록

            self.overlayWindow = window
            self.hostingController = hostingController

            print("✅ [DynamicIslandOverlay] 오버레이 윈도우 생성 완료!")
            print("   - windowLevel: \(window.windowLevel.rawValue)")
            print("   - isHidden: \(window.isHidden)")
            print("   - isKeyWindow: \(window.isKeyWindow)")
            print("   - frame: \(window.frame)")
            print("   - bounds: \(window.bounds)")
            print("   - rootViewController: \(String(describing: window.rootViewController))")

            // 0.5초 후 다시 확인
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("🔍 [DynamicIslandOverlay] 0.5초 후 상태 확인:")
                print("   - isHidden: \(window.isHidden)")
                print("   - alpha: \(window.alpha)")
                print("   - superview: \(String(describing: window.superview))")
            }
        }
    }

    // 오버레이 종료
    func stop() {
        walkTimer?.invalidate()
        walkTimer = nil

        DispatchQueue.main.async {
            self.overlayWindow?.isHidden = true
            self.overlayWindow = nil
            self.hostingController = nil
            print("✅ [DynamicIslandOverlay] 오버레이 종료됨")
        }
    }
}

// 캐릭터 뷰
struct DynamicIslandCharacterView: View {
    @StateObject private var viewModel: MultiCharacterViewModel

    init(mealStore: MealStore, settingsManager: SettingsManager) {
        _viewModel = StateObject(wrappedValue: MultiCharacterViewModel(
            count: 30,
            mealStore: mealStore,
            settingsManager: settingsManager
        ))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 동적으로 증가하는 캐릭터 배치 (최대 30마리)
                ForEach(0..<viewModel.characterCount, id: \.self) { index in
                    let character = viewModel.characters[index]

                    // offsetX를 pill 둘레를 따라 이동하는 거리로 변환
                    let moveDistance = character.offsetX / 15.0 // 15픽셀당 1칸 이동
                    let currentPosition = Double(index) + moveDistance

                    // pill 테두리를 따라 움직이는 위치 계산
                    let position = calculatePillShapePositionContinuous(
                        centerX: geometry.size.width / 2,
                        continuousIndex: currentPosition,
                        totalCount: 30 // 최대 30마리 기준으로 배치
                    )

                    Image(character.currentFrame == 0 ? "idle1" : "idle2")
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16) // 4배 크기 (4x4 → 16x16)
                        .scaleEffect(x: character.isMovingRight ? 1 : -1, y: 1)
                        .offset(y: character.bounceOffset)
                        .position(x: position.x, y: position.y)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    // 기기별 pill 크기 가져오기
    private func getPillDimensions() -> (width: CGFloat, height: CGFloat, centerY: CGFloat) {
        let deviceModel = UIDevice.current.modelName

        switch deviceModel {
        case let model where model.contains("iPhone 15"):
            // iPhone 15 Pro/Pro Max - 더 크게 조정
            return (width: 144, height: 52, centerY: 36)
        case let model where model.contains("iPhone 14"):
            return (width: 130, height: 39, centerY: 29.5)
        case let model where model.contains("iPhone 16"):
            // iPhone 16 Pro/Pro Max - 좌우 더 줄임
            return (width: 110, height: 35, centerY: 28)
        default:
            return (width: 126, height: 37, centerY: 29.5)
        }
    }

    // 다이나믹 아일랜드 pill 모양 테두리 위치 계산 (연속적인 index 지원)
    private func calculatePillShapePositionContinuous(centerX: CGFloat, continuousIndex: Double, totalCount: Int) -> CGPoint {
        // 기기별 다이나믹 아일랜드 pill 크기
        let dimensions = getPillDimensions()
        let pillWidth: CGFloat = dimensions.width
        let pillHeight: CGFloat = dimensions.height
        let radius: CGFloat = pillHeight / 2
        let straightWidth: CGFloat = pillWidth - pillHeight

        let centerY: CGFloat = dimensions.centerY
        let margin: CGFloat = 3 // 테두리 바깥 여백

        // Pill의 둘레 계산
        let perimeter = 2 * straightWidth + 2 * .pi * (radius + margin)

        // continuousIndex를 0~totalCount 범위로 정규화 (순환)
        var normalizedIndex = continuousIndex.truncatingRemainder(dividingBy: Double(totalCount))
        if normalizedIndex < 0 {
            normalizedIndex += Double(totalCount)
        }

        let distance = (perimeter / CGFloat(totalCount)) * CGFloat(normalizedIndex)

        // 위쪽 직선 시작점부터 시계방향으로 배치
        let sideAdjustment: CGFloat = 9 // 좌우 반원은 안쪽으로 9px 이동
        let topAdjustment: CGFloat = 2 // 위쪽 직선은 2px 위로 이동
        let bottomAdjustment: CGFloat = 4 // 아래쪽 직선은 4px 위로 이동

        if distance < straightWidth {
            // 위쪽 직선 (왼쪽 → 오른쪽) - 더 위로
            let x = centerX - straightWidth/2 + distance
            let y = centerY - radius - margin - topAdjustment
            return CGPoint(x: x, y: y)
        } else if distance < straightWidth + .pi * (radius + margin - sideAdjustment) {
            // 오른쪽 반원 (안쪽으로 이동)
            let arcDistance = distance - straightWidth
            let sideMargin = margin - sideAdjustment
            let angle = arcDistance / (radius + sideMargin) - .pi/2
            let x = centerX + straightWidth/2 + (radius + sideMargin) * cos(angle)
            let y = centerY + (radius + sideMargin) * sin(angle)
            return CGPoint(x: x, y: y)
        } else if distance < 2 * straightWidth + .pi * (radius + margin - sideAdjustment) {
            // 아래쪽 직선 (오른쪽 → 왼쪽) - 더 위로
            let lineDistance = distance - straightWidth - .pi * (radius + margin - sideAdjustment)
            let x = centerX + straightWidth/2 - lineDistance
            let y = centerY + radius + margin - bottomAdjustment
            return CGPoint(x: x, y: y)
        } else {
            // 왼쪽 반원 (안쪽으로 이동)
            let arcDistance = distance - 2 * straightWidth - .pi * (radius + margin - sideAdjustment)
            let sideMargin = margin - sideAdjustment
            let angle = arcDistance / (radius + sideMargin) + .pi/2
            let x = centerX - straightWidth/2 + (radius + sideMargin) * cos(angle)
            let y = centerY + (radius + sideMargin) * sin(angle)
            return CGPoint(x: x, y: y)
        }
    }

    // 다이나믹 아일랜드 위쪽 Y 위치
    private func getDynamicIslandTopY() -> CGFloat {
        let deviceModel = UIDevice.current.modelName

        // 기기별 다이나믹 아일랜드 상단 위치
        switch deviceModel {
        case let model where model.contains("iPhone 14 Pro"):
            return 37 // iPhone 14 Pro/Pro Max
        case let model where model.contains("iPhone 15 Pro"):
            return 37 // iPhone 15 Pro/Pro Max
        case let model where model.contains("iPhone 16 Pro"):
            return 37 // iPhone 16 Pro/Pro Max
        default:
            return 37 // 기본값
        }
    }

    // 다이나믹 아일랜드 아래쪽 Y 위치
    private func getDynamicIslandBottomY() -> CGFloat {
        let deviceModel = UIDevice.current.modelName

        // 기기별 다이나믹 아일랜드 아래쪽 위치
        switch deviceModel {
        case let model where model.contains("iPhone 14 Pro"):
            return 44 // iPhone 14 Pro/Pro Max
        case let model where model.contains("iPhone 15 Pro"):
            return 44 // iPhone 15 Pro/Pro Max
        case let model where model.contains("iPhone 16 Pro"):
            return 44 // iPhone 16 Pro/Pro Max
        default:
            return 44 // 기본값
        }
    }
}
import Combine

// 개별 캐릭터 상태
struct CharacterState {
    var currentFrame: Int
    var isMovingRight: Bool
    var offsetX: CGFloat
    var bounceOffset: CGFloat
    var moveSpeed: CGFloat
    var moveRange: CGFloat
}

// 다중 캐릭터 뷰모델 (각 캐릭터가 개별적으로 움직임)
class MultiCharacterViewModel: ObservableObject {
    @Published var characters: [CharacterState]
    @Published var characterCount: Int = 0 // 현재 표시되는 캐릭터 수

    private var animationTimer: Timer?
    private var growthTimer: Timer?
    private weak var mealStore: MealStore?
    private weak var settingsManager: SettingsManager?
    private var cancellables = Set<AnyCancellable>()

    init(count: Int, mealStore: MealStore, settingsManager: SettingsManager) {
        self.mealStore = mealStore
        self.settingsManager = settingsManager
        // 최대 30마리의 캐릭터 상태 미리 생성 (각각 랜덤 초기값)
        characters = (0..<30).map { _ in
            CharacterState(
                currentFrame: Int.random(in: 0...1), // 랜덤 시작 프레임
                isMovingRight: Bool.random(), // 랜덤 방향
                offsetX: CGFloat.random(in: -3...3), // 랜덤 시작 위치
                bounceOffset: 0,
                moveSpeed: CGFloat.random(in: 1.5...2.5), // 랜덤 속도
                moveRange: CGFloat.random(in: 8...12) // 랜덤 이동 범위
            )
        }

        startAnimation()
        startGrowthTimer()
        observeMealChanges()
    }

    private func observeMealChanges() {
        // MealStore의 변화 감지
        guard let mealStore = mealStore else { return }

        mealStore.objectWillChange.sink { [weak self] _ in
            guard let self = self else { return }

            // 약간의 지연 후 체크 (변경사항이 반영된 후)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.checkAndResetIfNeeded()
            }
        }
        .store(in: &cancellables)
    }

    private func checkAndResetIfNeeded() {
        guard let mealStore = mealStore,
              let settingsManager = settingsManager else { return }

        let today = Calendar.current.startOfDay(for: Date())
        let meals = mealStore.getMeals(for: today)

        let isExerciseMode = settingsManager.albumType == .exercise

        // 오늘 식사 기록이 있으면 캐릭터 리셋
        if isExerciseMode {
            // 운동 모드: 아침 식사가 있으면 리셋
            if meals[.breakfast] != nil {
                resetCharacters()
            }
        } else {
            // 식단 모드: 어떤 식사라도 있으면 리셋
            if !meals.isEmpty {
                resetCharacters()
            }
        }
    }

    private func startGrowthTimer() {
        // 20분(1200초)마다 캐릭터 1마리씩 증가 (최대 30마리)
        growthTimer = Timer.scheduledTimer(withTimeInterval: 1200, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if self.characterCount < 30 {
                    self.characterCount += 1
                    print("🐾 [캐릭터 증가] 현재 캐릭터 수: \(self.characterCount)")
                }
            }
        }

        // 테스트용: 즉시 1마리 추가 (나중에 제거 가능)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if self.characterCount < 30 {
                self.characterCount += 1
            }
        }
    }

    // 식사 기록 시 캐릭터 리셋
    func resetCharacters() {
        DispatchQueue.main.async {
            self.characterCount = 0
            print("🔄 [캐릭터 리셋] 식사 기록됨")
        }
    }

    private func startAnimation() {
        // 0.6초마다 애니메이션 업데이트
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            DispatchQueue.main.async {
                for i in 0..<self.characters.count {
                    // 프레임 전환 (idle1 <-> idle2) - 각 캐릭터 독립적
                    self.characters[i].currentFrame = (self.characters[i].currentFrame + 1) % 2

                    // 콩콩 뛰는 효과
                    self.characters[i].bounceOffset = self.characters[i].currentFrame == 0 ? 0 : -2

                    // 좌우 이동 (각 캐릭터가 다른 속도와 범위로 움직임)
                    if self.characters[i].isMovingRight {
                        self.characters[i].offsetX += self.characters[i].moveSpeed
                        if self.characters[i].offsetX >= self.characters[i].moveRange {
                            self.characters[i].isMovingRight = false
                        }
                    } else {
                        self.characters[i].offsetX -= self.characters[i].moveSpeed
                        if self.characters[i].offsetX <= -self.characters[i].moveRange {
                            self.characters[i].isMovingRight = true
                        }
                    }
                }
            }
        }
    }

    deinit {
        animationTimer?.invalidate()
        growthTimer?.invalidate()
    }
}

// 기기 모델명 확인 extension
extension UIDevice {
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }

        // 식별자를 기기명으로 매핑
        switch identifier {
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"
        case "iPhone17,1": return "iPhone 16 Pro"
        case "iPhone17,2": return "iPhone 16 Pro Max"
        default: return identifier
        }
    }
}
