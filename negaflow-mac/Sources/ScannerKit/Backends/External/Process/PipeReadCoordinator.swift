import Foundation
import Darwin

/// 현재 pipe 버퍼에 이미 도착한 바이트만 읽는다. 후손 프로세스가 write FD를 상속해도
/// EOF를 기다리지 않으며, consumer가 제한 초과를 보고하면 즉시 중단한다.
func drainAvailableData(
    from handle: FileHandle,
    consumer: (Data) -> Bool
) {
    let descriptor = handle.fileDescriptor
    let flags = fcntl(descriptor, F_GETFL)
    guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { return }
    defer { _ = fcntl(descriptor, F_SETFL, flags) }

    var bytes = [UInt8](repeating: 0, count: 64 * 1_024)
    while true {
        let count = bytes.withUnsafeMutableBytes { buffer in
            Darwin.read(descriptor, buffer.baseAddress, buffer.count)
        }
        if count > 0 {
            guard consumer(Data(bytes: bytes, count: count)) else { return }
        } else if count == 0 {
            return
        } else if errno == EINTR {
            continue
        } else {
            return
        }
    }
}

final class PipeReadCoordinator: @unchecked Sendable {
    private let condition = NSCondition()
    private var stopping = false
    private var activeReaders = 0

    func beginRead() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard !stopping else { return false }
        activeReaders += 1
        return true
    }

    func endRead() {
        condition.lock()
        activeReaders -= 1
        if activeReaders == 0 { condition.broadcast() }
        condition.unlock()
    }

    func stopAndWait() {
        condition.lock()
        stopping = true
        while activeReaders > 0 { condition.wait() }
        condition.unlock()
    }
}
