# RoutineCamera 접근성(VoiceOver) 개선

## 진행: 코드 구조화 · 리팩터 · 테스트
- [x] 기능 목록 문서화 (FEATURES.md)
- [x] 핵심 순수 로직을 RoutineCameraCore 로컬 패키지로 추출 (MealType/MealRecord/MealStats/PendingAteAll)
- [x] 단위 테스트 23개 작성 + `swift test` 통과 (스트릭·기록일·추론·정렬·Codable 호환)
- [x] 프로젝트 경고 0건 정리
- [ ] STAGE 2: 앱이 RoutineCameraCore를 import하도록 통합 (중복 타입 제거) — Xcode에서 로컬 패키지 추가 필요(안전) 또는 pbxproj 배선(위험)
- [x] STAGE 3: ContentView.swift 3232줄 → 429줄, 7개 파일로 분리 (빌드+실행 검증)
  → STAGE 2(패키지 통합)는 선택 사항 — 앱은 자체 타입으로 정상 동작, 테스트는 swift test로 독립 보장


## 완료: 예전 기록 백필 + 업로드 판정 수정 (1.0.6, 빌드 검증 완료 ✅)
- [x] dirty 판정: 최근 3일 → 날짜별 지문 비교로 실제 변경 날짜만
- [x] 앱 시작 시 기준값 1회 생성 (업데이트 직후 대량 업로드 방지, 새 설치는 첫 기록부터 업로드)
- [x] 기록을 모두 지운 날은 서버에서도 삭제 (deleteMyMeals)
- [x] MealBackfillManager + 설정 화면: 범위 선택·예상 용량·진행률·중단/재개
- [x] 이미 올라간 날짜는 desiredKeys:[] 로 사진 없이 존재만 확인해 건너뜀
- [x] 운동 모드에서 운동 기록이 식단으로 업로드되던 경로 차단 (dietMeals 전용 접근자)
- [ ] 실기기 확인: 백필 실행 → 친구 화면에서 과거 날짜 노출되는지
- 결론: Firebase 이관 로직은 불필요 (SDK 제거됨 + Firebase 데이터는 로컬 기록의 사본)

## 완료: 친구 요청/수락 + 그룹 (1.0.6, 빌드 검증 완료 ✅)
- [x] FriendLink 레코드로 관계 전환 (각자 자기 링크만 생성, 양쪽 존재 = 친구)
- [x] 요청 보내기 / 수락 / 거절 / 요청 취소 + 맞요청 즉시 성사
- [x] 구버전 friendsJSON → FriendLink 자동 이관 (isLegacy 플래그로 상대 미업데이트 호환)
- [x] 친구 요청 푸시 구독 (otherId == 나)
- [x] 그룹: 만들기/초대코드 참여/나가기, 멤버 전원의 날짜별 피드 (GroupsView)
- [x] 그룹 식단 배치 조회 (사람×끼니 ID 100개씩, 친구 캐시 공유)
- [ ] 사용자 확인 필요: CloudKit Console에서 새 레코드 타입 인덱스 생성 + Production 배포
      (FriendLink.ownerId/otherId, RCGroup.inviteCode/ownerId, GroupMember.groupId/userId)
- [ ] 실기기 2대로 요청→수락→상호 열람, 그룹 3인 이상 피드 검증 (시뮬레이터는 iCloud 미로그인이라 미검증)

## 완료: 친구 코드 오류 진단 (1.0.6, 빌드 검증 완료 ✅)
- [x] "존재하지 않는 코드" 안내에 원인 힌트 추가 (친구 앱의 현재 코드 / TestFlight·앱스토어 설치 경로 일치)
- [x] CloudKit 조회 실패 원인별 문구 분리 (스키마 미준비·인덱스 없음·네트워크·iCloud 미로그인)
- [x] 내 코드 자가검증(FriendManager.verifyMyCodeRegistered) + 친구 화면 주황 경고 배너 + "다시 확인" 버튼
- [x] CLOUDKIT_SETUP.md 문제 해결 섹션 (Development/Production DB 분리 확인법)
- [ ] 사용자 확인 필요: CloudKit Console에서 Development/Production 각각 `RCUser code == BVUPP3` 조회 → 어느 환경에 있는지 확인, 필요 시 스키마 Production 배포

## 🚀 대전환: "얼마나 먹었나" 리디자인 (스펙: REDESIGN_SPEC.md)
격자(3끼 슬롯) → 순간 컬렉션 + 앱 안 여는 원탭 기록. 핵심 지표는 칼로리가 아닌 "양"(식전/식후 차이 + "다 먹음" 탭).
- [ ] Phase 1 (앱 본체): capturedAt/ateAll 모델 + MomentsView 피드 + 식후 알림 + AppIntent(액션버튼/단축어) + 격자는 설정 토글로 보존
- [x] Phase 2 (Widget): 완료 — SekkiWidget 타깃 생성·임베드, 홈/잠금화면 위젯 + 원탭 다먹음 (1.0.6)
- [~] Phase 2 (구버전 메모): App Group 배관 완료(entitlements+공유 suite+대기열 drain, 앱 빌드 검증). 위젯 코드는 SekkiWidget/ 에 준비됨 → 사용자가 Xcode에서 Widget Extension 타깃 생성 후 연결 필요 (SekkiWidget/README.md)
- 상세 로직·페르소나·기록 조합표는 REDESIGN_SPEC.md 참조
- [x] 챙길 식사 선택: 삼시세끼 전부 알림 → "챙기고 싶은 식사"만 알림. 첫 실행 프롬프트("어떤 식사를 챙기고 싶어요?") + 설정 섹션 (CaredMealsView, SettingsManager.caredMeals, NotificationManager 게이팅)


## 진행: 완벽주의/올오어낫씽 완화 (식단 기록 이탈 심리 대응)
리서치 근거: 추적 피로 + "나쁜 날 회피"가 식단 기록 이탈의 핵심 심리
- [x] ① 하루 완료 기준 완화: 스트릭이 "주요 3끼 전부"가 아니라 "최소 한 끼라도"면 이어짐 (Models.isDayRecorded, getCurrentStreak/getMaxStreak)
- [x] ② 회복 프레임: 통계의 "🏆 최고 연속"(경쟁·리셋) → "📸 기록한 날"(절대 안 줄어드는 누적) + 격려 한 줄 (StatisticsView.StreakAndGoalView, Models.getTotalRecordedDays)
- [x] ③ 끊김 빨강 '박제' 제거: 끊긴 날 빨간 배경/실선 테두리 → 미기록과 동일한 회색 점선, "끊겼어요" → "다음 기록부터 다시 이어져요" (ContentView backgroundColor/stateBorderOverlay/accessibilityStatus)
- [x] LeeoKit 미구현 API 구현 (블로커 해소): LeeoEngagement(참여도 추적) + .leeoSatisfactionCheck(2갈래 만족도 체크: 만족→앱스토어 리뷰 / 불만족→피드백) — LeeoKit/Sources/LeeoKit/Engagement/
- [x] 앱 전체 빌드 성공 (BUILD SUCCEEDED) + LeeoKit 패키지 단독 빌드 성공
- [x] 제안 3 시뮬레이터 시각 확인: 과거 미기록 칸 전부 빨강 없이 균일한 회색 점선
- [ ] 제안 1·2 시뮬레이터 확인 남음: 통계 화면(🔥 현재 연속 / 📸 기록한 날 + 격려 문구) — System Events 접근성 권한 게이트로 탭 자동화 불가, 수동 확인 필요


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

## 완료: "간식 보이기" 설정 강화 (빌드 검증 완료 ✅)
- [x] 꺼져 있으면 과거 날짜의 **기록된 간식도** 화면에서 숨김 (기존엔 빈 칸만 숨겨짐, 오늘 행과 동작 통일) - getSnacksToShow
- [x] 토글을 "사진 저장" 섹션 → "표시 설정" 섹션으로 이동 + 상태별 설명 문구 추가 (기록은 삭제되지 않음을 명시)
- [x] DailySectionView가 SettingsManager를 관찰하도록 해 토글 즉시 반영

## 향후(선택) 개선 아이디어
- [ ] 로터에 "안 읽은 피드백" 추가 (피드백 개수 비동기 집계 데이터 소스 필요)
- [ ] Dynamic Type: minimumScaleFactor(0.7) 대신 줄바꿈 허용 검토
- [ ] 기록 배너: 운동 모드 지원 검토 (현재 식단 모드 전용)
- [ ] pendingMealType이 시간 경과를 실시간 반영하도록 타이머/scenePhase 갱신 검토 (현재는 재렌더 시점에 갱신)
