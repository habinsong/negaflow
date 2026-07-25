import CoreGraphics
import Foundation

/// 서로 겹치지 않는 brush group의 병렬 결과를 index 순서로 모으는 동기화 경계다.
final class DefectPatchResultStore: @unchecked Sendable {
    typealias Result = (rect: CGRect, image: CGImage)

    private let lock = NSLock()
    private var results: [Result?]

    init(count: Int) {
        results = [Result?](repeating: nil, count: count)
    }

    func set(_ result: Result, at index: Int) {
        lock.lock()
        results[index] = result
        lock.unlock()
    }

    func snapshot() -> [Result?] {
        lock.lock()
        defer { lock.unlock() }
        return results
    }
}
