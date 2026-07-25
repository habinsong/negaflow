import Foundation
import Darwin

final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var collected = Data()
    private var _failure: String?
    private let limit: Int
    private let label: String
    private let onLine: (@Sendable (String) -> String?)?
    private let onFailure: @Sendable (String) -> Void

    init(
        limit: Int,
        label: String,
        onLine: (@Sendable (String) -> String?)?,
        onFailure: @escaping @Sendable (String) -> Void
    ) {
        self.limit = limit
        self.label = label
        self.onLine = onLine
        self.onFailure = onFailure
    }

    func append(_ data: Data) {
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
        guard onLine != nil else { lock.unlock(); return }
        pending.append(data)
        var lines: [Data] = []
        while let nl = pending.firstIndex(of: 0x0A) {
            let lineData = pending.subdata(in: pending.startIndex..<nl)
            pending.removeSubrange(pending.startIndex...nl)
            lines.append(lineData)
        }
        lock.unlock()
        for line in lines {
            guard process(line: line) else { break }
        }
    }

    func flush() {
        lock.lock()
        let leftover = pending
        pending.removeAll()
        lock.unlock()
        if onLine != nil, !leftover.isEmpty { _ = process(line: leftover) }
    }

    private func process(line: Data) -> Bool {
        guard let string = String(data: line, encoding: .utf8) else {
            recordFailure("plugin stdout NDJSON 줄이 유효한 UTF-8이 아님")
            return false
        }
        if let message = onLine?(string) {
            recordFailure(message)
            return false
        }
        return true
    }

    private func recordFailure(_ message: String) {
        lock.lock()
        let isFirst = _failure == nil
        if isFirst { _failure = message }
        lock.unlock()
        if isFirst { onFailure(message) }
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
