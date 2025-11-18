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
