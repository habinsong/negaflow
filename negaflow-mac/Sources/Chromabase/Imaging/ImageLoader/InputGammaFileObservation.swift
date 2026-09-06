import Foundation
import Darwin

/// URL의 resource-value 캐시를 거치지 않고 파일 교체와 제자리 수정을 구분합니다.
struct InputGammaFileObservation: Hashable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int

    static func read(_ url: URL) throws -> Self {
        guard url.isFileURL else { throw InputGammaDecodeError.unsupportedSource }
        var info = stat()
        let status = url.withUnsafeFileSystemRepresentation { path in
            path.map { fstatat(AT_FDCWD, $0, &info, 0) } ?? -1
        }
        guard status == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw InputGammaDecodeError.decodeFailed
        }
        return Self(device: info.st_dev, inode: info.st_ino, size: info.st_size,
            modifiedSeconds: info.st_mtimespec.tv_sec, modifiedNanoseconds: info.st_mtimespec.tv_nsec,
            changedSeconds: info.st_ctimespec.tv_sec, changedNanoseconds: info.st_ctimespec.tv_nsec)
    }
}
