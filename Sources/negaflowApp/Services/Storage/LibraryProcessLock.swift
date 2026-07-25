import Darwin
import Foundation

@_silgen_name("flock")
private func systemFlock(_ fileDescriptor: Int32, _ operation: Int32) -> Int32

enum LibraryProcessLockError: Error, Equatable {
    case alreadyLocked
    case unavailable(Int32)
}

/// catalog별 단일 작성자 advisory lock. lock 파일 자체는 남아 있어도 소유권은 열린 file
/// descriptor와 연결되므로 정상 종료·충돌 종료 모두 커널이 잠금을 해제한다.
final class LibraryProcessLock: @unchecked Sendable {
    let lockURL: URL
    private let fileDescriptor: Int32

    private init(lockURL: URL, fileDescriptor: Int32) {
        self.lockURL = lockURL
        self.fileDescriptor = fileDescriptor
    }

    static func acquire(
        for catalogURL: URL,
        fileManager: FileManager = .default
    ) throws -> LibraryProcessLock {
        let lockURL = catalogURL.appendingPathExtension("lock")
        let parentURL = lockURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: parentURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw LibraryProcessLockError.unavailable(errno)
        }

        let descriptor = lockURL.path.withCString { path in
            Darwin.open(
                path,
                O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw LibraryProcessLockError.unavailable(errno)
        }
        guard systemFlock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let lockError = errno
            Darwin.close(descriptor)
            if lockError == EWOULDBLOCK || lockError == EAGAIN {
                throw LibraryProcessLockError.alreadyLocked
            }
            throw LibraryProcessLockError.unavailable(lockError)
        }
        return LibraryProcessLock(lockURL: lockURL, fileDescriptor: descriptor)
    }

    deinit {
        _ = systemFlock(fileDescriptor, LOCK_UN)
        Darwin.close(fileDescriptor)
    }
}
