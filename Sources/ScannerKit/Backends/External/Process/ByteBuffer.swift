import Foundation
import Darwin

final class ByteBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var collected = Data()
    private var _failure: String?
    private let limit: Int
    private let label: String
    private let onFailure: @Sendable (String) -> Void

    init(limit: Int, label: String, onFailure: @escaping @Sendable (String) -> Void) {
        self.limit = limit
        self.label = label
        self.onFailure = onFailure
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        guard _failure == nil else {
            lock.unlock()
            return
        }
        guard data.count <= limit - collected.count else {
            let message = "plugin \(label) 허용량 초과 (최대 \(limit) bytes)"
            _failure = message
            lock.unlock()
            onFailure(message)
            return
        }
        collected.append(data)
        lock.unlock()
    }

    var failure: String? {
        lock.lock(); defer { lock.unlock() }
        return _failure
    }

    var allData: Data {
        lock.lock(); defer { lock.unlock() }
        return collected
    }
}

/// stdout 바이트를 누적하며 개행 단위로 onLine 콜백을 호출하는 스레드 안전 버퍼.
