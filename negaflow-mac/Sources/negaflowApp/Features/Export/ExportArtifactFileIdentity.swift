import Darwin
import Foundation

struct ExportArtifactFileIdentity: Codable, Equatable, Sendable {
    let deviceID: UInt64
    let inode: UInt64
    let birthTimeSeconds: Int64
    let birthTimeNanoseconds: Int64

    var isValid: Bool {
        inode > 0
            && birthTimeSeconds >= 0
            && (0..<1_000_000_000).contains(birthTimeNanoseconds)
    }
}

struct ExportSourceFileIdentity: Equatable, Sendable {
    let deviceID: UInt64
    let inode: UInt64
    let byteCount: Int64
    let birthTimeSeconds: Int64
    let birthTimeNanoseconds: Int64
    let modificationTimeSeconds: Int64
    let modificationTimeNanoseconds: Int64
    let changeTimeSeconds: Int64
    let changeTimeNanoseconds: Int64
}

enum ExportArtifactFileIdentityInspector {
    static func regularFile(at url: URL) -> ExportArtifactFileIdentity? {
        guard let status = status(at: url),
              (status.st_mode & S_IFMT) == S_IFREG else { return nil }
        return ExportArtifactFileIdentity(
            deviceID: UInt64(bitPattern: Int64(status.st_dev)),
            inode: UInt64(status.st_ino),
            birthTimeSeconds: Int64(status.st_birthtimespec.tv_sec),
            birthTimeNanoseconds: Int64(status.st_birthtimespec.tv_nsec)
        )
    }

    static func entryExists(at url: URL) -> Bool {
        status(at: url) != nil
    }

    static func sourceFile(at url: URL) -> ExportSourceFileIdentity? {
        guard let status = status(at: url.resolvingSymlinksInPath()),
              (status.st_mode & S_IFMT) == S_IFREG else { return nil }
        return ExportSourceFileIdentity(
            deviceID: UInt64(bitPattern: Int64(status.st_dev)),
            inode: UInt64(status.st_ino),
            byteCount: Int64(status.st_size),
            birthTimeSeconds: Int64(status.st_birthtimespec.tv_sec),
            birthTimeNanoseconds: Int64(status.st_birthtimespec.tv_nsec),
            modificationTimeSeconds: Int64(status.st_mtimespec.tv_sec),
            modificationTimeNanoseconds: Int64(status.st_mtimespec.tv_nsec),
            changeTimeSeconds: Int64(status.st_ctimespec.tv_sec),
            changeTimeNanoseconds: Int64(status.st_ctimespec.tv_nsec)
        )
    }

    private static func status(at url: URL) -> stat? {
        var value = stat()
        let result: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return Darwin.lstat(path, &value)
        }
        return result == 0 ? value : nil
    }

}

enum ExportArtifactFileOperations {
    static func moveExclusively(from source: URL, to destination: URL) throws {
        let result: Int32 = source.withUnsafeFileSystemRepresentation { sourcePath in
            guard let sourcePath else { return -1 }
            return destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let destinationPath else { return -1 }
                return Darwin.renamex_np(sourcePath, destinationPath, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    static func unlinkFile(at url: URL) throws {
        let result: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return Darwin.unlink(path)
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
