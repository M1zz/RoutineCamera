# CloudKit 설정 가이드

친구 식단 공유·피드백 기능은 전부 CloudKit 공개 DB로 동작합니다.
**서버, Firebase, APNs 키 업로드, 유료 요금제가 전혀 필요 없습니다** (Apple이 저장·푸시를 모두 처리).

## 동작 구조

- 신원: 기기의 iCloud 계정 (`CKContainer.userRecordID`) — 별도 로그인 화면 없음
- 컨테이너: `iCloud.com.ysoup.RoutineCamera`
- 공개 DB 권한 모델: 누구나 읽기, **생성자만** 수정/삭제

### 레코드 타입

| 타입 | recordName | 필드 | 용도 |
|---|---|---|---|
| `RCUser` | `user_<userId>` | `code`(친구 코드, 쿼리 대상), `nickname`, `friendsJSON` | 프로필 + 친구 목록 |
| `Meal` | `meal_<userId>_<yyyy-MM-dd>_<끼니키>` | `ownerId`(쿼리 대상), `dateString`, `mealType`, `memo`, `beforeImage`/`afterImage`(**CKAsset**), `timestamp` | 공유 식단 (ID로 직접 조회 — 인덱스 불필요) |
| `Feedback` | 자동 UUID | `recipientId`·`authorId`·`dateString`·`mealType`(쿼리 대상), `authorNickname`, `content`, `createdAtTS` | 피드백/콕 찌르기 |

### 피드백 푸시

받는 사람이 로그인 시 `recipientId == 내 ID` 조건의 `CKQuerySubscription`을 자동 등록합니다.
친구가 `Feedback` 레코드를 저장하면 Apple이 곧바로 푸시를 배달합니다.
(예전 FCM·FeedbackPing 핑 채널은 모두 제거됨 — Feedback 레코드 하나로 저장+푸시 통합)

### 읽음 상태

공개 DB 레코드는 생성자만 수정할 수 있으므로, "읽음" 표시는 수신 기기에 로컬(UserDefaults)로 저장합니다.

## 필요한 준비 (Xcode)

- [x] Signing & Capabilities → **iCloud (CloudKit)**, 컨테이너 `iCloud.com.ysoup.RoutineCamera` 체크
- [x] Signing & Capabilities → **Push Notifications** (entitlements에 `aps-environment` 있음)
- 참가자 기기에 iCloud 로그인 필요 (일반적으로 충족)

## TestFlight / App Store 배포 시 (중요!)

개발 빌드는 CloudKit **Development** 환경을 쓰며 스키마(레코드 타입·인덱스)가 첫 저장 때 자동 생성됩니다.
배포 빌드는 **Production** 환경을 쓰므로, 배포 전에 반드시:

1. 개발 빌드로 각 기능을 한 번씩 사용 (코드 생성, 친구 추가, 식단 업로드, 피드백 작성) → 스키마 자동 생성
2. [CloudKit Console](https://icloud.developer.apple.com) → `iCloud.com.ysoup.RoutineCamera` → **Deploy Schema Changes to Production** 실행

쿼리에 쓰이는 필드(`RCUser.code`, `Meal.ownerId`, `Feedback.recipientId`/`authorId`/`dateString`/`mealType`)의
**Queryable 인덱스**가 Production에 포함되어 있는지 확인하세요.

## 20명 이벤트 전 점검 목록

- [ ] 스키마 Production 배포 완료
- [ ] 참가자 전원 iCloud 로그인 + "내 식단 공유 가능" 켜기 (기본 on)
- [ ] 친구 코드 목록 공유 → 친구 추가 화면에 전체 붙여넣기 (일괄 추가 지원)
- [ ] 실기기 2대(iCloud 계정 2개)로 콕 찌르기 → 푸시 수신 → 배지 → 기록 루프 검증
- 사진 업로드는 자동 축소됨(긴 변 1024px, JPEG 0.6) + CKAsset이라 무료 할당량으로 충분

## 문제 해결: 친구 추가 시 "존재하지 않는 코드입니다"

이 메시지는 **쿼리는 성공했는데 결과가 0건**일 때만 나옵니다(스키마·인덱스·네트워크 오류는 별도 문구로 안내됨).
즉 조회한 환경의 공개 DB에 해당 코드의 `RCUser` 레코드가 없다는 뜻입니다. 확인 순서:

1. **배포 환경 불일치** — Xcode로 직접 설치한 빌드는 Development DB, TestFlight/App Store 빌드는 Production DB를 씁니다.
   두 DB는 완전히 별개라 한쪽에서 만든 코드는 다른 쪽에서 절대 조회되지 않습니다. 두 기기의 설치 경로를 맞추세요.
2. **코드가 최신인지** — 회원 탈퇴·다른 iCloud 계정 로그인 시 코드가 **새로 발급**됩니다. 예전에 공유한 코드는 무효입니다.
3. **레코드 자체가 없음** — 앱은 친구 화면 진입 시 자기 코드로 조회해보고, 검색되지 않으면 코드 아래에 주황색 경고를 띄웁니다
   (`FriendManager.verifyMyCodeRegistered`). 이 경고가 보이면 그 기기의 코드는 아직 남에게 검색되지 않는 상태입니다.
4. **인덱싱 지연** — 방금 생성된 레코드는 몇 초 뒤에야 쿼리에 잡힙니다. 자가검증은 3초 간격으로 3회 시도한 뒤에만 경고합니다.

CloudKit Console → Records에서 **Development / Production 각각** `RCUser`를 `code == <코드>` 로 조회해보면 어느 환경에 있는지 바로 확인됩니다.

## 비용 안내

CloudKit 공개 DB는 앱의 무료 할당량이 활성 사용자 수에 비례해 자동으로 늘어납니다.
이 규모(수십 명)에서는 사실상 무료입니다.
