# Firebase 설정 가이드

친구 식단 공유 기능을 위한 Firebase 설정 방법입니다.

## 1단계: Firebase 프로젝트 생성

1. https://console.firebase.google.com 접속
2. "프로젝트 추가" 클릭
3. 프로젝트 이름 입력 (예: "RoutineCamera")
4. Google 애널리틱스 설정 (선택사항)
5. 프로젝트 생성 완료

## 2단계: iOS 앱 추가

1. Firebase 콘솔에서 "iOS 앱 추가" 클릭
2. Bundle ID 입력: `com.yourname.RoutineCamera`
   - Xcode에서 확인: 프로젝트 설정 > General > Bundle Identifier
3. 앱 닉네임: "RoutineCamera" (선택사항)
4. App Store ID: 비워두기 (선택사항)
5. "앱 등록" 클릭

## 3단계: GoogleService-Info.plist 다운로드

1. `GoogleService-Info.plist` 파일 다운로드
2. Xcode에서 프로젝트 네비게이터 열기
3. `RoutineCamera` 폴더에 파일 드래그 앤 드롭
4. "Copy items if needed" 체크
5. "Add to targets: RoutineCamera" 체크

## 4단계: Firebase SDK 설치 (Swift Package Manager)

1. Xcode에서 `File` > `Add Package Dependencies...`
2. 패키지 URL 입력:
   ```
   https://github.com/firebase/firebase-ios-sdk
   ```
3. Dependency Rule: "Up to Next Major Version" 11.0.0 선택
4. "Add Package" 클릭
5. 다음 라이브러리 선택:
   - ✅ FirebaseAuth
   - ✅ FirebaseDatabase
   - ✅ FirebaseStorage
6. "Add Package" 클릭

## 5단계: Firebase Realtime Database 활성화

1. Firebase 콘솔에서 "빌드" > "Realtime Database" 선택
2. "데이터베이스 만들기" 클릭
3. 위치 선택: "asia-northeast3 (서울)" 또는 가까운 지역
4. 보안 규칙: "테스트 모드로 시작" 선택 (나중에 변경 가능)
5. "사용 설정" 클릭

## 6단계: Firebase Storage 활성화

1. Firebase 콘솔에서 "빌드" > "Storage" 선택
2. "시작하기" 클릭
3. 보안 규칙: 기본값 사용
4. 위치: Realtime Database와 동일한 지역 선택
5. "완료" 클릭

## 7단계: 보안 규칙 설정 (중요!)

### Realtime Database 규칙
Firebase 콘솔 > Realtime Database > 규칙 탭에서:

```json
{
  "rules": {
    "users": {
      "$uid": {
        ".read": true,
        ".write": "$uid === auth.uid"
      }
    },
    "userCodes": {
      ".read": true,
      ".write": false
    },
    "meals": {
      "$uid": {
        ".read": true,
        ".write": "$uid === auth.uid"
      }
    }
  }
}
```

### Storage 규칙
Firebase 콘솔 > Storage > Rules 탭에서:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /meals/{userId}/{allPaths=**} {
      allow read: if true;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

## 8단계: 앱에서 Firebase 초기화 확인

앱을 실행하고 Xcode 콘솔에서 다음 메시지 확인:
```
✅ Firebase 초기화 완료
✅ 사용자 코드 생성: ABC123
```

## 완료!

이제 친구 식단 공유 기능을 사용할 수 있습니다.

## 비용 안내

**무료 티어 (Spark Plan):**
- Realtime Database: 1GB 저장용량, 10GB/월 다운로드
- Storage: 5GB 저장용량, 1GB/일 다운로드
- 인증: 무제한

일반적인 사용에는 무료 티어로 충분합니다.

## 문제 해결

### GoogleService-Info.plist 파일이 없어요
- Firebase 콘솔 > 프로젝트 설정 > 일반 > 내 앱 > iOS 앱에서 다시 다운로드

### Firebase SDK 설치 오류
- Xcode 재시작
- `File` > `Packages` > `Reset Package Caches`

### 데이터베이스 연결 오류
- Firebase 콘솔에서 Realtime Database가 활성화되어 있는지 확인
- 보안 규칙이 올바른지 확인

## 피드백 푸시 알림 설정 (FCM)

친구가 피드백/콕 찌르기를 남기면 푸시가 오도록 하는 설정입니다.
클라이언트 코드(FCM 토큰 등록)와 Cloud Function(`functions/index.js`)은 구현되어 있고,
아래 콘솔 작업 2가지만 하면 동작합니다.

> **현재 비활성화 상태**: 콘솔 작업 전이므로 코드에서 꺼 두었습니다. 활성화하려면
> 1. 아래 1·2번 콘솔 작업 완료
> 2. `RoutineCameraApp.swift`의 `AppDelegate.feedbackPushEnabled`를 `true`로 변경
> 3. `RoutineCamera.entitlements`에 `aps-environment`(development) 키 다시 추가

### 1. APNs 인증 키 등록 (필수)

1. [Apple Developer](https://developer.apple.com) > Certificates, Identifiers & Profiles > Keys
2. "+" 로 새 키 생성, **Apple Push Notifications service (APNs)** 체크 → `.p8` 파일 다운로드 (Key ID 메모)
3. Firebase Console > 프로젝트 설정 > 클라우드 메시징 > Apple 앱 구성
4. "APNs 인증 키 업로드" 에 `.p8` 파일 + Key ID + Team ID 입력
5. Xcode > 타겟 > Signing & Capabilities 에 **Push Notifications** capability가 추가되어 있는지 확인
   (entitlements에 `aps-environment`는 이미 추가됨)

### 2. Cloud Function 배포 (필수)

Cloud Functions는 **Blaze 요금제**가 필요합니다 (호출량이 적으면 사실상 무료).

```bash
npm install -g firebase-tools   # 없다면
firebase login
cd <프로젝트 루트>
firebase init functions          # 기존 functions/ 유지 선택
cd functions && npm install
firebase deploy --only functions
```

배포되는 함수: `sendFeedbackPush` — `feedbacks/{userId}/...`에 새 피드백이 생기면
그 사용자의 `users/{userId}/fcmToken`으로 푸시를 보냅니다.

주의: Realtime Database 인스턴스가 us-central1이 아니면 `functions/index.js`의
`onValueCreated` 옵션에 `instance`를 지정해야 합니다.

### 20명 이벤트 전 점검 목록

- [ ] APNs 키 업로드 + 함수 배포 완료
- [ ] 참가자 전원 Apple 로그인 + "내 식단 공유 가능" 켜기 (기본 on)
- [ ] 친구 코드 목록 공유 → 친구 추가 화면에 전체 붙여넣기 (일괄 추가 지원)
- [ ] 보안 규칙 확인: `feedbacks/`, `meals/`, `users/`가 인증 사용자만 읽기/쓰기 가능한지
- [ ] 사진 업로드는 자동 축소됨(긴 변 1024px) — 무료 플랜 전송량으로 충분

## 피드백 푸시 — CloudKit 핑 채널 (현재 사용 중인 방식)

FCM 대신 CloudKit 공개 DB 구독으로 피드백 푸시를 배달합니다.
**서버, APNs 키 업로드, Blaze 요금제가 모두 필요 없습니다** (Apple이 배달).

동작 구조:
1. A가 피드백/콕 작성 → Firebase 저장 + CloudKit에 `FeedbackPing` 레코드 생성
   (받는사람 ID, 보낸사람 닉네임, 끼니 이름만 — 피드백 내용은 넣지 않음)
2. B는 로그인 시 자기 ID 조건의 CKQuerySubscription을 자동 등록
3. 레코드 생성 → Apple이 B에게 푸시 발송
4. 보낸 사람은 로컬 장부 기반으로 7일 지난 자기 핑을 자동 삭제

필요한 준비 (Xcode에서 확인):
- [ ] Signing & Capabilities에 **iCloud (CloudKit)** — 컨테이너 `iCloud.com.ysoup.RoutineCamera` 체크
- [ ] Signing & Capabilities에 **Push Notifications**
- [ ] 자동 서명이 프로필을 재생성하도록 실기기에서 한 번 빌드
- 참가자 기기에 iCloud 로그인 필요 (일반적으로 충족)

TestFlight/App Store 배포 시 주의:
- 개발 빌드는 CloudKit **Development** 환경을 쓰고 스키마(FeedbackPing 타입)가 첫 저장 때 자동 생성됩니다.
- 배포 빌드는 **Production** 환경을 쓰므로, 이벤트 전에
  [CloudKit Console](https://icloud.developer.apple.com) → 해당 컨테이너 → **Deploy Schema Changes to Production** 을 한 번 실행해야 합니다.
