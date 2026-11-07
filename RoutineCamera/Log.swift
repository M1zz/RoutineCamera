//
//  Log.swift
//  RoutineCamera
//
//  앱 기록(로그)은 print 대신 여기 있는 Logger 로 남긴다.
//  print 는 배포 빌드에서도 문자열을 만들고 아무 데도 남지 않았다.
//  Logger 는 콘솔 앱에서 분류별로 걸러 볼 수 있고, 닉네임·코드 같은 값은 배포 빌드 기록에서 가려진다.
//  어느 스레드에서든 쓸 수 있다.
//

import os

nonisolated enum Log {
    private static let subsystem = "com.ysoup.RoutineCamera"

    /// 기록 저장 · 불러오기 · 사진 파일
    static let store = Logger(subsystem: subsystem, category: "store")
    /// 친구 공유용 CloudKit 공개 DB 업로드
    static let share = Logger(subsystem: subsystem, category: "share")
    /// 친구 · 그룹 · 피드백
    static let friends = Logger(subsystem: subsystem, category: "friends")
    /// 내 iCloud 백업 동기화
    static let sync = Logger(subsystem: subsystem, category: "sync")
    /// 카메라 · 사진 앨범 저장
    static let camera = Logger(subsystem: subsystem, category: "camera")
    /// 알림 · 푸시
    static let notification = Logger(subsystem: subsystem, category: "notification")
    /// 사진 분석
    static let analysis = Logger(subsystem: subsystem, category: "analysis")
    /// 그 밖의 앱 동작 (위젯, 위치, 설정)
    static let app = Logger(subsystem: subsystem, category: "app")
}
