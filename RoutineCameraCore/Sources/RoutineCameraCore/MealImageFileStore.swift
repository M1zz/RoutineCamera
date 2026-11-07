//
//  MealImageFileStore.swift
//  RoutineCameraCore
//
//  식사 사진 바이트를 UserDefaults 대신 파일로 한 장씩 보관한다.
//  기록 전체(사진 포함)를 한 덩어리로 UserDefaults 에 쓰면 사진이 쌓일수록 저장할 때마다
//  수백 MB 를 인코딩·기록하게 되고, 그 사이 메모리가 치솟아 앱이 종료된다.
//  기록 JSON 에는 파일 이름만 남기고 사진은 여기 둔다.
//

import Foundation

/// 기록 저장은 메인 밖의 한 줄(직렬 큐)에서 하므로, 기억해 둔 바이트(`known`)는 잠금으로 지킨다.
public final class MealImageFileStore: @unchecked Sendable {
    public enum StoreError: Error, Equatable {
        case invalidName(String)
    }

    public static let fileExtension = "jpg"

    public let directory: URL
    private let fileManager: FileManager
    /// 이 실행에서 읽거나 쓴 파일의 바이트. 기록이 들고 있는 사진과 같은 메모리를 나눠 쓰므로 메모리가 더 들지 않는다.
    /// 같은 바이트(같은 메모리)를 다시 쓰라고 하면 디스크를 열지 않고 넘어간다 —
    /// 기록 하나를 고칠 때마다 모든 사진 파일을 열어 비교하던 것을 없앤다.
    private var known: [String: Data] = [:]
    private let lock = NSLock()

    private func knownData(_ name: String) -> Data? { lock.withLock { known[name] } }
    private func remember(_ data: Data?, for name: String) { lock.withLock { known[name] = data } }

    /// 같은 내용인지 볼 때 파일 앞뒤에서 읽는 바이트 수.
    /// 사진 전체를 매번 읽지 않기 위한 절충 — 크기와 앞뒤가 같으면 같은 사진으로 본다.
    static let sampleLength = 4096

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// 끼니 칸 하나에 대응하는 파일 이름. 같은 날·같은 끼니·같은 종류(식전/식후)는 늘 같은 이름이다.
    /// - Parameters:
    ///   - day: `yyyy-MM-dd`
    ///   - slot: 끼니 식별자 (ASCII)
    ///   - kind: `before` / `after`
    public static func fileName(day: String, slot: String, kind: String) -> String {
        "\(day)_\(slot)_\(kind).\(fileExtension)"
    }

    /// 사진을 파일로 쓴다. 같은 이름에 같은 내용이 이미 있으면 다시 쓰지 않는다.
    /// - Returns: 실제로 파일을 썼으면 true
    @discardableResult
    public func write(_ data: Data, named name: String) throws -> Bool {
        let url = try fileURL(for: name)
        if let previous = knownData(name), Self.isSameBytes(previous, data) { return false }
        if hasSameContent(data, at: url) { remember(data, for: name); return false }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        // 중간에 종료돼도 반쯤 쓴 파일이 남지 않도록 원자적으로 교체
        try data.write(to: url, options: .atomic)
        remember(data, for: name)
        return true
    }

    /// 사진을 읽는다. 메모리에 통째로 올리지 않고 파일에 매핑해, 시스템이 필요할 때 내려놓을 수 있게 한다.
    public func load(named name: String) -> Data? {
        guard let url = try? fileURL(for: name),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        remember(data, for: name)
        return data
    }

    /// `keeping` 에 없는 사진 파일을 지운다 (기록에서 빠진 사진 정리). 사진 확장자가 아닌 파일은 건드리지 않는다.
    /// - Returns: 지운 파일 수
    @discardableResult
    public func removeFiles(keeping names: Set<String>) -> Int {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var removed = 0
        for name in contents where name.hasSuffix(".\(Self.fileExtension)") && !names.contains(name) {
            if (try? fileManager.removeItem(at: directory.appendingPathComponent(name))) != nil {
                removed += 1
                remember(nil, for: name)
            }
        }
        return removed
    }

    // MARK: - 내부

    private func fileURL(for name: String) throws -> URL {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
            throw StoreError.invalidName(name)
        }
        return directory.appendingPathComponent(name)
    }

    /// 같은 바이트인지 — 같은 메모리를 가리키면 읽지 않고 같다고 본다 (Data 는 복사해도 고치기 전까지 메모리를 나눠 쓴다).
    /// 작은 값은 Data 안에 바로 들어 있어 주소가 매번 다르므로 그대로 비교한다.
    static func isSameBytes(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        guard a.count > 64 else { return a == b }
        return a.withUnsafeBytes { pa in b.withUnsafeBytes { pb in pa.baseAddress == pb.baseAddress } }
    }

    private func hasSameContent(_ data: Data, at url: URL) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              size == data.count,
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        let sample = Self.sampleLength
        if data.count <= sample * 2 {
            return (try? handle.readToEnd()) == data
        }
        guard let head = try? handle.read(upToCount: sample), head == data.prefix(sample) else { return false }
        guard (try? handle.seek(toOffset: UInt64(data.count - sample))) != nil,
              let tail = try? handle.read(upToCount: sample) else { return false }
        return tail == data.suffix(sample)
    }
}
