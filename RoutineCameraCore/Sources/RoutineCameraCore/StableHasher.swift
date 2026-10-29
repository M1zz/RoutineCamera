//
//  StableHasher.swift
//  RoutineCameraCore
//
//  실행이 바뀌어도 같은 값을 내는 해시 (64비트 FNV-1a).
//  Swift 의 Hasher 는 프로세스마다 무작위 시드를 써서, 저장해 둔 값과 다음 실행의 값이 절대 같지 않다.
//  날짜별 기록 지문(무엇이 바뀌었는지)을 UserDefaults 에 남겨 비교하는 곳에는 이것을 쓴다.
//

import Foundation

public struct StableHasher: Sendable {
    private var state: UInt64 = 0xcbf2_9ce4_8422_2325

    public init() {}

    public mutating func combine(_ value: String) {
        for byte in value.utf8 { mix(byte) }
        mix(0xff) // 구분자 — ("ab","c") 와 ("a","bc") 가 같아지지 않도록
    }

    public mutating func combine(_ value: Int) {
        withUnsafeBytes(of: Int64(value).littleEndian) { for byte in $0 { mix(byte) } }
    }

    public mutating func combine(_ value: Bool) {
        mix(value ? 1 : 0)
    }

    public mutating func combine(_ value: Double) {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { for byte in $0 { mix(byte) } }
    }

    public func finalize() -> Int {
        Int(truncatingIfNeeded: state)
    }

    private mutating func mix(_ byte: UInt8) {
        state ^= UInt64(byte)
        state = state &* 0x0000_0100_0000_01b3
    }
}
