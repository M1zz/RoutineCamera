# SekkiWidget — 홈/잠금화면 위젯

`SekkiWidget/` 는 **위젯 익스텐션 타깃(SekkiWidget)** 으로 프로젝트에 연결되어 있다.
앱 타깃(RoutineCamera)이 빌드될 때 함께 빌드되고 `RoutineCamera.app/PlugIns/SekkiWidget.appex` 로 임베드된다.

## 구성

| 파일 | 역할 |
|---|---|
| `SekkiWidgetBundle.swift` | `@main` 위젯 번들 |
| `SekkiWidget.swift` | 타임라인 프로바이더 + 패밀리별 뷰 |
| `SekkiWidgetStore.swift` | App Group 공유 저장소 읽기/쓰기 + `LogAteAllWidgetIntent` |
| `Info.plist` | `NSExtension` = `com.apple.widgetkit-extension` (나머지 키는 빌드 설정에서 생성) |
| `SekkiWidget.entitlements` | App Group `group.com.ysoup.RoutineCamera` |

지원 패밀리: `systemSmall`(홈), `accessoryRectangular` / `accessoryCircular` / `accessoryInline`(잠금화면).

## 동작

1. 앱이 기록을 저장할 때마다 `MealRecordStore.publishWidgetSnapshot()` 이 App Group에
   경량 스냅샷(`widgetSnapshot`)을 쓰고 `WidgetCenter.reloadAllTimelines()` 를 호출한다.
   - 스냅샷: 오늘 기록 수, 오늘 "먹는 중"인 끼니와 그 시각, 마지막 기록 시각, "기록 필요" 수
   - 위젯은 사진이 담긴 기록 전체를 디코딩하지 않는다(메모리 절약)
2. 위젯은 스냅샷 + 아직 반영 안 된 대기열(`pendingAteAll`)을 합쳐 표시한다.
   - 오늘 식전만 찍힌 끼니가 있으면 "○○ 먹는 중"
   - 없으면 "오늘 N개"
3. **"다 먹음" 버튼**(인터랙티브, iOS 17+): 앱을 열지 않고 대기열에 적재 + 위젯 새로고침.
   - "먹는 중"인 끼니가 있으면 **그 기록을 마감**하도록 해당 끼니·날짜로 적재
   - 없으면 현재 시각으로 추론한 끼니에 사진 없이 다먹음 기록
4. 앱이 다음에 활성화되면 `MealRecordStore.drainPendingAteAll()` 이 대기열을 실제 기록으로 반영한다.

## 코드 공유 규칙

위젯은 앱과 프로세스가 달라 `MealRecordStore`(CloudKit 등 무거운 의존성)를 직접 쓰지 않는다.
- **판단 로직**은 `RoutineCameraCore`(로컬 패키지)의 `WidgetStateResolver` 에 있고 위젯 타깃이 링크한다.
  표시 상태 계산과 "다 먹음이 어느 기록에 붙는지"는 `WidgetSharedStateTests` 로 테스트된다.
- **저장소 입출력**만 `SekkiWidgetStore` 가 담당한다.

앱 타깃은 아직 Core를 링크하지 않으므로 `AppGroup.swift` 에 같은 필드의 `WidgetSnapshot` 을 따로 둔다.
**한쪽 필드 이름만 바꾸면 위젯이 조용히 빈 상태가 된다** — 아래를 함께 유지할 것:

- `group.com.ysoup.RoutineCamera` (App Group)
- `DietMealRecords`, `pendingAteAll`, `widgetSnapshot` (키)
- 앱 `WidgetSnapshot` ↔ Core `WidgetSnapshot` (필드 동일 / 계약 테스트: `testSnapshot_decodesAppSideJSON`)
- 앱 `PendingAteAll` ↔ Core `PendingAteAll` (필드 동일)

## 확인 방법

- 시뮬레이터/실기기에서 앱 실행 → 기록 하나 남김 → 홈 화면 위젯 추가("세끼") → 숫자 확인
- 식전 사진만 남긴 뒤 위젯이 "○○ 먹는 중"으로 바뀌는지 확인
- 위젯의 "다 먹음" 탭 → 앱을 열면 해당 끼니가 마감(다 먹음)돼 있는지 확인
- 잠금화면: 잠금화면 편집 → 위젯 추가 → "세끼"

> 실기기 배포 시 App Group `group.com.ysoup.RoutineCamera` 가 위젯 번들 ID
> (`com.ysoup.RoutineCamera.SekkiWidget`)의 프로비저닝 프로파일에도 포함돼야 한다.
> 자동 서명이면 Xcode가 처리한다.
