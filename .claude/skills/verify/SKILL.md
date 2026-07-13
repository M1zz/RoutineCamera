---
name: verify
description: RoutineCamera iOS 앱을 시뮬레이터에서 빌드·실행·조작해 변경사항을 눈으로 검증하는 레시피
---

# RoutineCamera 검증 레시피

## 빌드 & 실행 (iOS 시뮬레이터)

```bash
# 빌드 (Firebase SPM 해석 때문에 첫 빌드는 수 분 소요)
xcodebuild -project RoutineCamera.xcodeproj -scheme RoutineCamera \
  -destination 'generic/platform=iOS Simulator' build

# 부팅 + 설치 + 실행 (번들 ID: com.ysoup.RoutineCamera)
xcrun simctl boot <UDID>   # xcrun simctl list devices available 로 UDID 확인
open -a Simulator && xcrun simctl bootstatus <UDID>
APP=~/Library/Developer/Xcode/DerivedData/RoutineCamera-*/Build/Products/Debug-iphonesimulator/RoutineCamera.app
xcrun simctl install booted $APP
xcrun simctl launch booted com.ysoup.RoutineCamera
xcrun simctl io booted screenshot out.png   # 디바이스 화면만 캡처 (Space 무관, 항상 동작)
```

## 시뮬레이터 UI 조작 (cliclick)

simctl은 탭 주입을 지원하지 않음 → `cliclick`으로 macOS 좌표에 클릭.

1. **Space 주의**: 시뮬레이터가 다른 Space에 있을 수 있음. 반드시
   `osascript -e 'tell application "Simulator" to activate' && sleep 1.5 && <클릭/캡처>`
   를 **한 명령으로 묶어서** 실행 (별도 명령으로 나누면 그 사이 Space가 되돌아가 빗나감).
2. **좌표 매핑**: 창 프레임 조회 후 창 영역을 스크린샷하고, 그 캡처(2x px)에서 타깃 위치를 읽어 변환:
   ```bash
   osascript -e 'tell application "System Events" to tell process "Simulator" to get {position, size} of window 1'
   # → {wx, wy, ww, wh}
   screencapture -x -R<wx>,<wy>,<ww>,<wh> win.png   # activate와 한 명령으로!
   # 클릭 좌표 = (wx + 캡처px_x/2, wy + 캡처px_y/2)
   cliclick c:<x>,<y>
   ```
   디바이스 스크린샷(1206x2622 @3x) 좌표에서 역산하려 하지 말 것 — 창 캡처에서 직접 읽는 게 정확함.
3. **스크롤**: `cliclick dd:x,y1 dm:x,y2 ... du:x,y3` (위로 드래그 = 과거로 스크롤).

## 클릭 없이 카메라 시트 열기 (DEBUG 훅)

사용자가 맥을 쓰는 중이면 cliclick(포커스 강탈)을 피할 것. DEBUG 빌드는 환경변수로 카메라 시트를 자동 오픈할 수 있음:

```bash
SIMCTL_CHILD_OPEN_CAMERA_SHEET_FOR_TEST=1 xcrun simctl launch booted com.ysoup.RoutineCamera
```

(ContentView.onAppear의 `OPEN_CAMERA_SHEET_FOR_TEST` 훅, #if DEBUG 전용)

## 알아둘 것 (gotcha)

- 시뮬레이터엔 카메라가 없어 **셔터 버튼이 무반응** (에러 표시도 없음). 기록 검증은
  "사진 없이 기록" 토글 → 완료, 또는 사진앨범 탭(샘플 사진 존재) 경로를 쓸 것.
- 식사 기록/배너는 NotificationManager의 아침/점심/저녁 시간 설정에 의존 —
  현재 시각에 따라 보이는 상태가 달라짐.
- 빌드 성공 직후 SourceKit이 "Cannot find X in scope" 진단을 뿜을 수 있음 — 인덱서 노이즈이므로 무시.
- 데이터 초기화: 설정 시트의 DEBUG 섹션에 "모든 데이터 삭제" / "샘플 데이터 생성" 있음.
