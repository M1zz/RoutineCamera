# RoutineCamera 접근성(VoiceOver) 개선

## 완료: 접근성 코드 적용 (빌드 검증 완료 ✅)
- [x] ① 헤더 아이콘 버튼 라벨 (통계/친구/설정) - ContentView StreakHeaderView
- [x] ② 목표 진행률 값 번역 + 버튼 트레잇 - ContentView StreakHeaderView
- [x] ③ 끼니 카드 병합 + 상태 문장(거름/미래/차례/완료) - ContentView MealPhotoView
- [x] 피드백 버튼 + 친구 셀 라벨 - FriendsView FriendMealPhotoCell
- [x] DateHeaderView 앨범 전환 버튼 라벨/값/힌트
- [x] FriendsView 코드 복사/친구추가/계정설정/샘플 버튼 라벨
- [x] 내 친구 코드 문자 단위 낭독 (accessibilityValue)
- [x] 친구 목록 행 병합 + 장식 chevron 숨김
- [x] PhotoDetailView 더보기 메뉴 라벨 + 식전/식후 사진 라벨
- [x] StatisticsView 주간/월간/식사별/연속기록/업적 요소 병합·값 번역
- [x] 장식용 SF Symbol 이미지 accessibilityHidden 처리

## 완료: 추가 접근성 (빌드 검증 완료 ✅)
- [x] 색 이중 인코딩: 끼니 카드 테두리 패턴(실선=거름 / 점선=예정 / 없음=일반)
- [x] 커스텀 로터: "오늘" / "거른 날"로 바로 점프 (MealListRotors)

## 완료: 첫 실행 경험 수정 (빌드 검증 완료 ✅)
- [x] 시작일(첫 실행일/최오래 기록일) 개념 도입 - SettingsManager.appStartDate, MealRecordStore.startDate
- [x] 시작일 이전 과거 날짜는 "거른 끼니"로 판정하지 않음 (isPastDateMissed)
- [x] 누적 빨간 카운터(previousMissedCount)도 시작일 이후만 집계
- [x] "거른 날" 로터도 시작일 존중
  → 신규 사용자 첫 화면에서 빨간 12 누적 사라짐, 과거는 중립 표시

## 완료: 실패 표시 톤 재설계 + 사용성 (빌드 검증 완료 ✅)
- [x] 유예 기간(첫 3일): 미기록도 실패 강조 없이 초대(+) 톤 - isWithinGracePeriod
- [x] 누적 빨간 숫자 완전 제거 (mainSymbolView)
- [x] "진짜 연속 끊김" 지점만 옅은 빨강 강조 - isStreakBreakDay (이전 날이 완전 기록)
- [x] 그 외 미기록은 회색 점선 '부드러운 미기록' - isSoftMissed
- [x] 심볼 톤 정리: 미기록/예정=음소거 회색, 유예·일반=식사 색
- [x] 접근성 낭독 문구 새 상태 반영 (유예/끊김/미기록)
- [x] Reduce Motion 시 펄스 애니메이션 정지 - PulsingSymbolView

## 완료: "기록이 쉬운 앱" 메인 화면 개선 (빌드 + 시뮬레이터 실기동 검증 완료 ✅)
- [x] 카메라 자동 오픈(진입 강탈) 제거 → 탭하면 열리는 "기록할 시간" 배너로 교체 - RecordNowBanner, pendingMealType
- [x] autoOpenCamera 설정 재활용: "기록 시간 배너 표시" 토글로 문구 변경 (키/기본값 유지)
- [x] 커스텀 헤더 숨김 드래그 제스처 제거 (스크롤 간섭/잔버그) + 헤더 자체를 컴팩트하게 (vertical 18→8)
- [x] 과거 스크롤 시 "오늘 ↑" 플로팅 버튼 추가 (currentVisibleDate ≠ 오늘일 때만 표시)
- [x] 가로 스크롤 발견성: 4칸 이상이면 3.35칸 기준 크기로 4번째 칸 peek 노출
- [x] 빈 간식 칸을 "간식 보이기" 설정에 연동 (꺼져 있으면 과거 날짜에도 빈 간식 칸 미노출)
- [x] 과거 빈 끼니 칸에 회색 + 아이콘 (탭하면 소급 기록 가능함을 암시)
- [x] previousMissedMealsCount 배선 제거 (미사용 O(n²) 연산 삭제)
- [x] 드래그 핸들러 등 고빈도 print 제거

## 완료: 메인 화면 미니멀 디자인 전환 (빌드 + 시뮬레이터 라이트/다크 확인 ✅)
※ 직전의 그라디언트/파스텔 "비주얼 리프레시"를 사용자 요청("가장 심플하고 깔끔하게")으로 걷어내고 미니멀로 재설계
- [x] 상단 두 헤더(아이콘 줄 + 날짜 줄)를 HomeHeaderView 한 줄로 통합: 날짜·오늘뱃지(탭=오늘로 이동)·모드전환·통계/친구/설정
- [x] 날짜에서 연도 제거 ("M월 d일 (E)"), 스트릭 칩 삭제, 그림자 → 헤어라인 Divider
- [x] 목표 진행률: 라벨/축하문구 삭제 → 얇은 바(6pt) + "n/N일" 한 줄 (달성 시 초록, 접근성 값은 유지)
- [x] 모드 전환 버튼: 주황/파랑 채움 → 조용한 systemGray6 캡슐
- [x] 배너: 그라디언트·아이콘 원·서브카피·그림자 제거 → 플랫 파랑 단일 줄
- [x] 끼니 카드: 파스텔 틴트·심볼 원형 백드롭 제거 → 중립 gray6 복원, 라운딩 12
- [x] 오늘 행: 그라디언트 테두리·글로우 제거 → 얇은 파랑 테두리(1.5pt) + 아주 옅은 배경
- [x] 플로팅 "오늘" 버튼·미리보기 "사용하기" 버튼: 플랫 파랑
- [x] 액센트는 시스템 블루 하나로 통일, 끼니 심볼 색만 유지 (LinearGradient 전부 제거)

## 완료: 카메라 뷰 레이아웃 정리 (빌드 + 시뮬레이터 확인 ✅)
- [x] 중복 취소 버튼 제거 (헤더에만 유지, 셔터 옆 취소 삭제)
- [x] 셔터 버튼: 좌우 더미 프레임 트릭 제거 → 진짜 중앙 정렬 + 표준 iOS 스타일(흰 링+원), 하단 고정 50pt 대신 Spacer 균형 배치
- [x] 헤더: 투명 취소 버튼 트릭 제거 → ZStack으로 식전/식후 픽커 정중앙 고정, 높이 52pt 통일
- [x] 정사각 촬영 프레임에 라운딩 18 + 은은한 흰 테두리 (촬영 영역 경계 표시)
- [x] 미리보기(PreviewView): 버튼 라운딩·그라디언트 정리, 이미지 라운딩 18
- [x] 날짜/시간 오버레이는 사진 워터마크(addDateTimeToImage)와 비율이 연동되므로 위치·크기 유지
- [x] DEBUG 검증 훅: SIMCTL_CHILD_OPEN_CAMERA_SHEET_FOR_TEST=1 로 카메라 시트 자동 오픈

## 완료: 20명 식단 피드백 이벤트 대비 (빌드 ✅, Firebase 연동 흐름은 실기기 검증 필요)
- [x] 업로드 이미지 자동 축소: 긴 변 1024px·JPEG 0.6 (FriendManager.resizeForUpload) — 전송량 10~20배 절감, 무료 플랜 운영 가능
- [x] 콕 찌르기 + 빈 끼니 댓글: 친구의 빈 끼니 칸 탭 → 콕 찌르기(프리셋 피드백)/댓글(QuickFeedbackView 재사용)
- [x] 수신 배지 확장: 내 빈 끼니 칸에도 안 읽은 피드백 배지 표시, 탭하면 열람 시트(읽음 처리 + "지금 기록하기")
- [x] 친구 코드 일괄 추가: 쉼표/공백/줄바꿈 구분 여러 코드 붙여넣기 → 순차 추가 + 실패 요약
- [x] FCM 피드백 푸시 구현 후 **비활성화** (콘솔 작업 불가로): AppDelegate.feedbackPushEnabled = false, entitlements aps-environment 제거 (없으면 실기기 서명 실패 위험). 활성화 절차는 FIREBASE_SETUP.md 참고
- [x] CloudKit 핑 채널 구현 (FCM 대체): FeedbackPingManager — 피드백 작성 시 FeedbackPing 레코드(닉네임+끼니만, 내용 없음) → CKQuerySubscription 푸시, 보낸 핑 7일 후 자동 정리(로컬 장부 기반, 공개 DB는 생성자만 삭제 가능)
- [ ] Xcode Signing & Capabilities 확인 (사용자): iCloud(CloudKit) 컨테이너 iCloud.com.ysoup.RoutineCamera 체크 + Push Notifications capability
- [ ] TestFlight로 이벤트 시: CloudKit Console에서 스키마 Production 배포 (FIREBASE_SETUP.md 참고)
- [ ] 실기기 2대로 콕 → 푸시 수신 검증
- [ ] 실기기 2대(계정 2개)로 콕 찌르기 → 푸시 수신 → 배지 → 기록 루프 검증

## 완료: Firebase 전면 제거 → CloudKit 대체 (v1.0.4, 빌드 검증 완료 ✅)
※ 이전 데이터(친구 관계·공유 식단·피드백)는 이관하지 않음 (사용자 확인)
- [x] 앱 버전 1.0.4 (커밋·푸시 완료)
- [x] FriendManager 전면 재작성: Firebase RTDB/Auth → CloudKit 공개 DB
  - 신원: iCloud 계정(userRecordID) — Apple 로그인 화면·nonce 코드 삭제
  - RCUser 레코드(user_<id>): 친구 코드·닉네임·친구 목록(JSON)
  - Meal 레코드(meal_<id>_<날짜>_<끼니키>): 사진 base64 → **CKAsset**, ID 직접 조회(인덱스 불필요)
  - Feedback 레코드 하나로 저장+푸시 통합 (FeedbackPing 핑 채널 삭제), 읽음 상태는 로컬 저장
  - 회원 탈퇴 = 내가 만든 레코드(RCUser/Meal/Feedback) 전체 삭제 후 새 코드로 재시작
- [x] AppDelegate: FirebaseApp/App Check/FCM 제거, 원격 알림 등록만 유지
- [x] FriendsView: Apple 로그인 화면 → iCloud 안내 화면(ICloudRequiredView), 로그아웃 UI 제거
- [x] SettingsManager: shareMealsToFirebase → shareMealsToCloud (UserDefaults 키는 유지)
- [x] 프로젝트에서 firebase-ios-sdk 패키지(24개 제품) 제거, GoogleService-Info.plist·functions/·FIREBASE_SETUP.md 삭제
- [x] entitlements에서 applesignin·appattest 제거 (iCloud/CloudKit·aps-environment 유지)
- [x] CLOUDKIT_SETUP.md 작성 (스키마·Production 배포 절차·이벤트 점검 목록)
- [ ] 실기기에서 CloudKit 흐름 검증 (코드 생성 → 친구 추가 → 식단 업로드 → 피드백 푸시)
- [ ] TestFlight 배포 전 CloudKit Console에서 스키마 Production 배포 + Queryable 인덱스 확인

## 향후(선택) 개선 아이디어
- [ ] 로터에 "안 읽은 피드백" 추가 (피드백 개수 비동기 집계 데이터 소스 필요)
- [ ] Dynamic Type: minimumScaleFactor(0.7) 대신 줄바꿈 허용 검토
- [ ] 기록 배너: 운동 모드 지원 검토 (현재 식단 모드 전용)
- [ ] pendingMealType이 시간 경과를 실시간 반영하도록 타이머/scenePhase 갱신 검토 (현재는 재렌더 시점에 갱신)
