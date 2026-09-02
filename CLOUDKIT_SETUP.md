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
| `Meal` | `meal_<userId>_<yyyy-MM-dd>_<끼니키>` (운동은 `_ex` 접미사) | `ownerId`(쿼리 대상), `dateString`, `mealType`, `memo`, `beforeImage`/`afterImage`(**CKAsset**), `timestamp` | 공유 식단 (ID로 직접 조회 — 인덱스 불필요) |
| `Feedback` | 자동 UUID | `recipientId`·`authorId`·`dateString`·`mealType`(쿼리 대상), `authorNickname`, `content`, `createdAtTS` | 피드백/콕 찌르기 |
| `FriendLink` | `link_<내ID>_<상대ID>` | `ownerId`·`otherId`(쿼리 대상), `ownerCode`, `otherCode`, `ownerNickname`, `otherNickname`, `state`, `isLegacy`, `createdAtTS` | 친구 요청/수락 (양쪽 링크가 있으면 친구) |
| `RCGroup` | `group_<uuid>` | `inviteCode`·`ownerId`(쿼리 대상), `name`, `visibility`, `createdAtTS` | 그룹 |
| `GroupMember` | `member_<그룹ID>_<내ID>` | `groupId`·`userId`(쿼리 대상), `nickname`, `joinedAtTS` | 그룹 가입 (셀프 등록) |

### 친구 관계 (요청 → 수락)

공개 DB는 생성자만 수정할 수 있어 남의 레코드에 "수락됨"을 쓸 수 없다.
그래서 **각자 자기 쪽 링크만 만들고, 양쪽 링크의 존재로 친구를 판정**한다.

- A가 요청: `link_A_B (requested)` 생성 → A 화면엔 "수락 대기 중"
- B가 수락: `link_B_A (accepted)` 생성 → 양방향 성립, 서로의 기록이 보임
- B가 거절: `link_B_A (rejected)` → A 화면엔 "거절됨", 같은 요청이 다시 뜨지 않음
- 친구 끊기: 내 링크만 삭제 (상대 링크는 상대만 지울 수 있음)
- 푸시: 받는 사람은 `otherId == 내ID` 구독으로 요청·수락 알림을 받는다
- 구버전 `friendsJSON` 친구는 첫 실행 때 `isLegacy` 링크로 자동 이관되고,
  상대가 아직 업데이트하지 않았어도 친구로 인정된다

### 그룹

- 방장이 `RCGroup`을 만들면 6자리 초대 코드가 발급된다
- 참여는 **셀프 등록** — 코드로 그룹을 찾은 뒤 자기 `GroupMember` 레코드만 만든다
- 그룹 피드는 (멤버 × 끼니) 레코드 ID를 100개씩 묶어 한 번에 조회하므로 인덱스가 필요 없다
- 방장이 나가면 그룹 레코드를 지운다. 남의 멤버 레코드는 지울 수 없어 남지만, 그룹이 없으면 각 기기에서 정리된다
- 강퇴는 지원하지 않는다 (남의 레코드를 지울 수 없음)

**공개 범위 (`RCGroup.visibility`)** — 방장만 바꿀 수 있다. 공개 DB가 생성자만 수정을 허용하므로 서버에서도 강제된다.

| 값 | 화면 | 조회 |
|---|---|---|
| `record` | 멤버 전원을 기록함/안 함으로 표시 (누가 안 했는지가 핵심이라 전원 노출) | `desiredKeys: ["mealType"]` — **사진을 내려받지 않음** |
| `full` | 지금까지처럼 사진·메모까지, 기록 있는 멤버만 | 레코드 전체 (CKAsset 포함) |

필드가 없는 예전 그룹은 `full`로 간주한다(기존 동작 유지).

> ⚠️ `visibility`는 **Production 스키마에 배포해야** 쓸 수 있다. 배포 전 앱스토어/TestFlight 빌드에서는
> `Cannot create or modify field 'visibility' in record 'RCGroup' in production schema` 오류가 난다.
> 앱은 이 경우 `visibility` 없이 그룹을 만들어 넘어가고(= `full`), 사용자가 "기록 여부만"을 골랐을 때는
> 의도보다 많이 공개하지 않도록 그룹을 만들지 않고 안내한다.
> CloudKit Console → Schema → **Deploy Schema Changes**로 Development 스키마를 Production에 반영할 것.

### 음식 / 운동 (1.0.8)

앱은 음식(`식단`)과 운동을 **완전히 별개로** 저장한다. 1.0.7까지는 음식만 친구에게 올라갔다.
1.0.8부터 운동도 올라가고, 친구 화면 상단 탭에서 갈라 본다.

구분은 **레코드 이름**이 담는다. 새 필드가 없으니 운영 스키마를 건드릴 필요가 없다.

| 앨범 | Meal 레코드 이름 | Feedback 의 `mealType` 값 |
| --- | --- | --- |
| 음식 | `meal_<uid>_<날짜>_<끼니키>` | `lunch` |
| 운동 | `meal_<uid>_<날짜>_<끼니키>_ex` | `lunch_ex` |

음식에 접미사가 없는 것은 **1.0.7까지 쌓인 레코드가 그 이름이기 때문**이다.
그대로 둬야 아직 업데이트하지 않은 친구의 앱에서도 계속 보인다.
반대로 운동 레코드는 구버전 앱이 이름을 만들지 않으므로 아예 조회되지 않는다 — 깨지지 않고 안 보일 뿐이다.

- 레코드는 쿼리가 아니라 **이름으로 직접** 가져오므로 (`records(for:)`) 새 인덱스도 필요 없다
- `Feedback` 은 `mealType` 으로 쿼리하는데, 이 필드는 이미 있으므로 값만 바뀐다.
  덕분에 같은 날 같은 끼니라도 음식 응원과 운동 응원이 섞이지 않는다
- 그룹의 "오늘 기록함" 판정은 **두 앨범을 합쳐** 센다. 운동만 하는 멤버가 미기록으로 보이면 안 된다
- 그룹 사진 피드는 한 끼니 자리에 하나만 담을 수 있어 음식을 우선하고, 없으면 운동으로 채운다

> ⚠️ 운동 **이력**은 자동으로 올라가지 않는다. 변경 감지 기준값을 1.0.8 첫 실행에 지금 상태로 잡기 때문이다
> (안 그러면 전체 이력이 한꺼번에 업로드된다). 설정의 "예전 기록 공유"도 아직 음식만 올린다.

### 이모지 반응 (1.0.8)

반응은 **별도 레코드 타입도, 새 필드도 아니다.** `Feedback.content` 에 이모지만 담아 저장한다.

- 운영 스키마를 건드리지 않아도 되고,
- 아직 업데이트하지 않은 친구의 앱에서는 `🎉` 가 짧은 메시지로 읽혀 깨지지 않는다.

"이 글이 반응인가 글인가"를 가르는 규칙은 `RoutineCameraCore.FeedbackContent` 에 있다
(이모지 클러스터로만 이뤄져 있고 3개 이하). 테스트는 `FeedbackContentTests`.
같은 이모지를 다시 누르면 내 레코드를 지워 취소한다 — 공개 DB는 만든 사람만 지울 수 있으므로
남의 반응에는 쓸 수 없다.

### 피드백 푸시

받는 사람이 로그인 시 `recipientId == 내 ID` 조건의 `CKQuerySubscription`을 자동 등록합니다.
친구가 `Feedback` 레코드를 저장하면 Apple이 곧바로 푸시를 배달합니다.
(예전 FCM·FeedbackPing 핑 채널은 모두 제거됨 — Feedback 레코드 하나로 저장+푸시 통합)

> ⚠️ **1.0.7까지 푸시가 오지 않던 원인**
> 등록 실패를 성공으로 삼켰다. `.serverRejectedRequest` 를 무조건 "이미 있음"으로 보고
> UserDefaults 에 도장을 찍었는데, 운영 스키마에 `Feedback.recipientId` 쿼리 인덱스가 없을 때도
> 같은 코드가 날아온다. 한 번 도장이 찍히면 다시는 재시도하지 않아 푸시가 영원히 오지 않았다.
>
> 1.0.8부터는 **서버에 구독이 실제로 있는지 확인한 뒤에만** 도장을 찍고, 아니면 다음 실행에 다시 시도한다.
> 도장 키도 `feedbackSubscriptionUserId.v2` 로 올려 기존 기기가 한 번씩 재등록하게 했다.
> 상태는 설정 → 알림 → "친구 응원 알림" 에서 확인하고 "다시 등록"할 수 있다.
>
> 여기가 계속 "꺼짐"이면 `Feedback.recipientId` 의 Queryable 인덱스가 Production 에 있는지 확인할 것.

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

쿼리에 쓰이는 필드의 **Queryable 인덱스**가 Production에 포함되어 있는지 확인하세요:
`RCUser.code`, `Meal.ownerId`, `Feedback.recipientId`/`authorId`/`dateString`/`mealType`,
`FriendLink.ownerId`/`otherId`, `RCGroup.inviteCode`/`ownerId`, `GroupMember.groupId`/`userId`

## Production 스키마가 비어 있을 때 (배포할 변경사항이 없다고 나오는 경우)

`Cannot create new type Feedback in production schema` / `Cannot create or modify field 'visibility' ...`
= **운영 스키마에 그 타입·필드가 없다**는 뜻이다.

"Deploy Schema Changes"에 아무것도 안 뜨면, Development 스키마에도 없는 것이다
(Development에서 **한 번이라도 저장이 일어나야** 자동 생성되기 때문).
해결은 둘 중 하나:

1. **디버그 빌드로 한 번 써 본다** — Xcode 실행(= Development) → 피드백 남기기·그룹 만들기 →
   Development 스키마에 자동 생성 → 콘솔에서 Deploy Schema Changes
2. **콘솔에서 직접 만든다** — 환경을 **Development**로 바꾼 뒤 Record Type 추가 (Production은 읽기 전용)

`Feedback` 타입을 손으로 만들 때의 필드:

| 필드 | 타입 | 인덱스 |
|---|---|---|
| `recipientId` | String | **Queryable** (푸시 구독도 이 필드를 쓴다) |
| `authorId` | String | **Queryable** |
| `dateString` | String | **Queryable** |
| `mealType` | String | **Queryable** |
| `authorNickname` | String | — |
| `content` | String | — |
| `createdAtTS` | Double | — |

`RCGroup`에는 `visibility` (String, 인덱스 불필요) 하나만 추가하면 된다.

## 20명 이벤트 전 점검 목록

- [ ] 스키마 Production 배포 완료
- [ ] 참가자 전원 iCloud 로그인 + "내 식단 공유 가능" 켜기 (기본 on)
- [ ] 친구 코드 목록 공유 → 친구 추가 화면에 전체 붙여넣기 (일괄 추가 지원)
- [ ] 실기기 2대(iCloud 계정 2개)로 콕 찌르기 → 푸시 수신 → 배지 → 기록 루프 검증
- 사진 업로드는 자동 축소됨(긴 변 1024px, JPEG 0.6) + CKAsset이라 무료 할당량으로 충분

## 로컬 캐시 (친구·그룹 식단)

`FriendMealCache` — Application Support의 영구 캐시. 목표는 **같은 사진을 CloudKit에 두 번 요청하지 않는 것**.

- 위치: `Application Support/FriendMealsCache` (시스템이 임의로 비우는 Caches가 아님, iCloud 백업 제외).
  예전 Caches 위치의 캐시는 첫 실행 때 그대로 옮겨온다
- 만료: **지난 날짜는 만료 없음**(기록이 바뀌지 않으므로). 오늘 15분 / 최근 3일 6시간
- **기록이 없는 날도 "없음"으로 캐시**한다 — 안 그러면 빈 날을 지나칠 때마다 다시 물어본다
- 메모리 캐시는 200개 + 총 80MB(사진 바이트 기준)로 제한
- 디스크는 300MB 상한. 넘으면 오래 받은 (친구, 날짜) 단위로 JSON+사진을 통째로 지운다
- 조회는 (사람 × 끼니) 또는 (날짜 × 끼니) 레코드 ID를 100개씩 묶어 한 번에 — 하루씩 왕복하지 않는다
- 지난 날짜가 만료되지 않으므로, 친구가 예전 기록을 고친 경우를 위해 친구 타임라인에 **당겨서 새로고침**(해당 구간 캐시 무효화 후 재조회)을 둔다

## 업로드 대상 판정과 예전 기록 백필

`MealRecordStore.markDirtyDatesFromRecords()`는 **날짜별 지문**(끼니·메모·사진 바이트 수·다먹음·촬영시각)을
직전 값과 비교해 **실제로 바뀐 날짜만** 업로드 대상으로 표시한다.
기록이 모두 지워진 날은 `FriendManager.deleteMyMeals(date:)`로 서버에서도 삭제한다.

업데이트 직후 이력 전체가 한꺼번에 올라가는 것을 막기 위해, 앱 시작 시 한 번 현재 상태를 기준값으로 잡는다
(`dietFingerprintBaseline_v1`). 새로 설치한 기기는 기록이 없는 상태가 기준이므로 첫 기록부터 정상 업로드된다.

그래서 **예전 기록은 자동으로 올라가지 않는다.** 폰에만 있는 지난 기록은
설정 → 계정·공유 → **예전 기록 공유**(`MealBackfillManager`)에서 사용자가 직접 올린다.

- 공개 DB에 이력 전체를 올리는 일이므로 자동 실행하지 않는다
- 이미 올라간 날짜는 `records(for:desiredKeys: [])`로 **사진을 받지 않고 존재만 확인**해 건너뛴다
- 완료한 날짜를 저장해 중단 후 이어서 진행할 수 있다
- 1.0.4의 Firebase → CloudKit 전환 때 이전 데이터를 이관하지 않았으므로, 그 시절 기록도 이 백필로 올라간다
  (원본은 항상 기기 로컬이었고 Firebase는 공유용 사본이었다 — 별도의 Firebase 이관 로직은 필요 없다)

→ 친구 화면에서 오래된 날짜가 비어 보이는 것은 대개 조회 범위 문제가 아니라 **그 기록이 서버에 없기 때문**이다.
(친구 타임라인은 최대 365일까지 거슬러 조회하고, 그리드 모드는 최근 30일 고정이다.)

## ⚠️ 수락·그룹은 UX 장치이지 보안이 아님

공개 DB에는 **읽기 제한이 없습니다.** 친구 수락과 그룹 가입은 "앱 화면에 무엇을 보여줄지"를 정할 뿐,
상대 userId를 아는 사람이 레코드를 직접 읽는 것까지 막지는 못합니다.
진짜 권한 통제가 필요하면 비공개 DB + CKShare로 옮겨야 합니다 (초대가 iCloud 링크 기반이 되고 6자리 코드 방식은 폐기).

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
