# SekkiWidget — 위젯 타깃 설정 (Phase 2)

이 폴더의 Swift 파일은 **아직 어떤 타깃에도 속하지 않습니다**(앱 타깃 오염 방지를 위해 의도적으로 `RoutineCamera/` 밖에 둠). 아래 절차로 위젯 익스텐션 타깃을 만들고 이 파일들을 연결하면 잠금화면/홈 위젯 원탭이 완성됩니다.

## 1. 위젯 타깃 생성
Xcode에서 `File > New > Target… > Widget Extension`
- Product Name: **SekkiWidget**
- "Include Live Activity" **체크 해제**
- "Include Configuration App Intent" **체크 해제** (StaticConfiguration 사용)
- Finish → "Activate scheme?"는 Cancel(앱 스킴 유지)

Xcode가 생성한 기본 `SekkiWidget/` 그룹의 보일러플레이트 파일(SekkiWidget.swift, Bundle 등)은 **삭제**하고, 이 폴더의 파일 3개로 대체:
- `SekkiWidgetBundle.swift` (@main)
- `SekkiWidget.swift`
- `SekkiWidgetStore.swift`

> 이미 이 폴더가 타깃 폴더가 되도록 New Target 위치를 여기로 잡았다면 그대로 두면 됩니다.

## 2. App Group 연결 (필수 — 데이터 공유)
위젯 타깃 선택 → Signing & Capabilities → **+ Capability > App Groups** →
`group.com.ysoup.RoutineCamera` 체크. (앱 본체에는 이미 추가돼 있음)

App Group이 없으면 위젯이 기록 수를 읽지 못하고 "다 먹음"도 앱에 전달되지 않습니다.

## 3. 배포 타깃
위젯 타깃의 iOS Deployment Target을 앱과 동일(iOS 17+ / 프로젝트는 26)으로.
인터랙티브 위젯 버튼(`Button(intent:)`)은 iOS 17+ 필요.

## 4. 동작 방식
- 위젯이 App Group 공유 저장소에서 **오늘 기록 수**를 읽어 표시.
- **"다 먹음" 버튼**(인터랙티브) → 앱을 열지 않고 공유 대기열(`pendingAteAll`)에 적재 + 위젯 새로고침.
- 앱이 다음에 활성화되면 `MealRecordStore.drainPendingAteAll()`이 대기열을 실제 기록으로 반영.
  (이 배관은 앱 본체에 이미 구현·검증됨.)

## 5. 확인
- 홈 화면/잠금화면에 "세끼" 위젯 추가 → "다 먹음" 탭 → 숫자 증가 → 앱 열면 순간 피드에 반영.

## 참고: 코드 공유
위젯은 앱과 프로세스가 달라 `MealRecordStore`(CloudKit 등 무거운 의존성)를 직접 쓰지 않고,
`SekkiWidgetStore`가 App Group 저장소만 가볍게 읽고/쓴다. 식별자·키·대기열 포맷은
앱의 `AppGroup.swift` / `PendingAteAll` 과 동일하게 유지할 것(문자열 변경 시 양쪽 같이).
