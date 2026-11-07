//
//  DayKey.swift
//  RoutineCameraCore
//
//  하루를 가리키는 저장용 열쇠 "yyyy-MM-dd". iCloud 레코드 이름 · 사진 파일 이름 · 친구 기록 · 업로드 대기열이
//  모두 이 한 형식을 쓴다. 사용자의 달력 · 언어와 상관없이 늘 그레고리력 숫자다.
//  (예전에는 곳마다 DateFormatter 를 따로 만들었고, 한 곳은 사용자 달력으로 읽어
//   태국 불기 달력을 쓰는 사람의 업로드 날짜가 500여 년 어긋났다)
//

import Foundation

public enum DayKey {
    // DateFormatter 는 iOS 7 부터 여러 스레드에서 같이 써도 안전하다
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// 그 시각이 속한 날 (기기 시간대 기준)
    public static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    /// 그날 0시. 형식이 맞지 않으면 nil
    public static func date(from key: String) -> Date? {
        formatter.date(from: key)
    }
}
