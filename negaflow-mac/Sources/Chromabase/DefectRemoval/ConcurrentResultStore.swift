import Foundation

/// `DispatchQueue.concurrentPerform` worker가 index별 결과를 기록하고, 모든 worker가 끝난 뒤
/// 호출 스레드가 deterministic 순서로 snapshot을 읽는 작은 동기화 경계다.
final class ConcurrentResultStore<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [Element?]

    init(count: Int) {
        elements = [Element?](repeating: nil, count: count)
    }

    func set(_ element: Element, at index: Int) {
        lock.lock()
        elements[index] = element
        lock.unlock()
    }

    func snapshot() -> [Element?] {
        lock.lock()
        defer { lock.unlock() }
        return elements
    }
}
