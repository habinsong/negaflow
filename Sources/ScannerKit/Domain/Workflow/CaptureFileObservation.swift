import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

// MARK: - Capture fixity

/// 캡처 완료 시점의 파일시스템 개체를 재시작 뒤에도 동일하게 식별하기 위한 안정된 관찰값.
/// URL만 저장하지 않고 device/inode/size/mtime/ctime을 함께 고정한다.
public struct CaptureFileObservation: Codable, Sendable, Equatable, Hashable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let originalURL: URL
    public let device: UInt64
    public let inode: UInt64
    public let byteCount: UInt64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let changedSeconds: Int64
    public let changedNanoseconds: Int64

    public init(
        originalURL: URL,
        device: UInt64,
        inode: UInt64,
        byteCount: UInt64,
        modifiedSeconds: Int64,
        modifiedNanoseconds: Int64,
        changedSeconds: Int64,
        changedNanoseconds: Int64
    ) throws {
        self.schemaVersion = Self.currentSchemaVersion
        self.originalURL = originalURL
        self.device = device
        self.inode = inode
        self.byteCount = byteCount
        self.modifiedSeconds = modifiedSeconds
        self.modifiedNanoseconds = modifiedNanoseconds
        self.changedSeconds = changedSeconds
        self.changedNanoseconds = changedNanoseconds
        try validate()
    }

    /// symlink를 따라가지 않는 읽기 전용 descriptor와 path lstat을 함께 확인한다.
    public static func capture(for url: URL) throws -> CaptureFileObservation {
        let descriptor = try openCaptureFileDescriptor(for: url)
        defer { Darwin.close(descriptor) }

        let before = try captureStat(for: descriptor)
        guard before.isRegularFile, before.size > 0 else {
            throw ScanWorkflowValidationError.invalidValue(
                "캡처 원본은 비어 있지 않은 symlink가 아닌 regular file이어야 합니다"
            )
        }
        let pathStat = try captureStat(forPath: url)
        let after = try captureStat(for: descriptor)
        guard before == after,
              after == pathStat,
              pathStat.isRegularFile else {
            throw ScanWorkflowValidationError.invariantViolation(
                "캡처 파일 관찰 중 원본 파일 또는 경로가 변경되었습니다"
            )
        }
        return try after.observation(for: url)
    }

    /// 현재 경로가 캡처 완료 시점과 같은 파일시스템 개체/세대인지 확인한다.
    public func verifyCurrentFile() throws {
        let current = try Self.capture(for: originalURL)
        guard current == self else {
            throw ScanWorkflowValidationError.invariantViolation(
                "캡처 완료 뒤 원본 파일 또는 경로가 변경되었습니다"
            )
        }
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ScanWorkflowValidationError.invariantViolation(
                "지원하지 않는 CaptureFileObservation schemaVersion: \(schemaVersion)"
            )
        }
        guard originalURL.isFileURL else {
            throw ScanWorkflowValidationError.invalidValue(
                "captureObservation.originalURL은 file URL이어야 합니다"
            )
        }
        guard byteCount > 0 else {
            throw ScanWorkflowValidationError.invalidValue(
                "captureObservation.byteCount는 1 이상이어야 합니다"
            )
        }
        guard (0..<1_000_000_000).contains(modifiedNanoseconds),
              (0..<1_000_000_000).contains(changedNanoseconds) else {
            throw ScanWorkflowValidationError.invalidValue(
                "captureObservation 나노초 값이 유효하지 않습니다"
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case originalURL
        case device
        case inode
        case byteCount
        case modifiedSeconds
        case modifiedNanoseconds
        case changedSeconds
        case changedNanoseconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try requireSupportedSchema(
            schemaVersion,
            current: Self.currentSchemaVersion,
            record: "CaptureFileObservation",
            key: .schemaVersion,
            container: container
        )
        self.schemaVersion = schemaVersion
        self.originalURL = try container.decode(URL.self, forKey: .originalURL)
        self.device = try container.decode(UInt64.self, forKey: .device)
        self.inode = try container.decode(UInt64.self, forKey: .inode)
        self.byteCount = try container.decode(UInt64.self, forKey: .byteCount)
        self.modifiedSeconds = try container.decode(Int64.self, forKey: .modifiedSeconds)
        self.modifiedNanoseconds = try container.decode(Int64.self, forKey: .modifiedNanoseconds)
        self.changedSeconds = try container.decode(Int64.self, forKey: .changedSeconds)
        self.changedNanoseconds = try container.decode(Int64.self, forKey: .changedNanoseconds)
        try decodeValidated(self, decoder: decoder)
    }
}

struct CaptureStatSnapshot: Equatable {
    let device: UInt64
    let inode: UInt64
    let mode: mode_t
    let size: UInt64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    init(_ value: stat) throws {
        guard value.st_size >= 0 else {
            throw ScanWorkflowValidationError.invalidValue("캡처 원본 파일 크기가 유효하지 않습니다")
        }
        device = UInt64(truncatingIfNeeded: value.st_dev)
        inode = UInt64(truncatingIfNeeded: value.st_ino)
        mode = value.st_mode
        size = UInt64(value.st_size)
        modifiedSeconds = Int64(value.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(value.st_mtimespec.tv_nsec)
        changedSeconds = Int64(value.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(value.st_ctimespec.tv_nsec)
    }

    var isRegularFile: Bool { (mode & S_IFMT) == S_IFREG }

    func observation(for url: URL) throws -> CaptureFileObservation {
        try CaptureFileObservation(
            originalURL: url,
            device: device,
            inode: inode,
            byteCount: size,
            modifiedSeconds: modifiedSeconds,
            modifiedNanoseconds: modifiedNanoseconds,
            changedSeconds: changedSeconds,
            changedNanoseconds: changedNanoseconds
        )
    }
}

func openCaptureFileDescriptor(for url: URL) throws -> Int32 {
    guard url.isFileURL else {
        throw ScanWorkflowValidationError.invalidValue("캡처 원본은 file URL이어야 합니다")
    }
    let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
        guard let path else { return -1 }
        return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else {
        throw ScanWorkflowValidationError.invalidValue(
            "캡처 원본을 symlink 없이 읽기 전용으로 열 수 없습니다"
        )
    }
    return descriptor
}

func captureStat(for descriptor: Int32) throws -> CaptureStatSnapshot {
    var value = stat()
    guard Darwin.fstat(descriptor, &value) == 0 else {
        throw ScanWorkflowValidationError.invalidValue("캡처 원본 파일 정보를 읽을 수 없습니다")
    }
    return try CaptureStatSnapshot(value)
}

func captureStat(forPath url: URL) throws -> CaptureStatSnapshot {
    var value = stat()
    let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
        guard let path else { return -1 }
        return Darwin.lstat(path, &value)
    }
    guard result == 0 else {
        throw ScanWorkflowValidationError.invariantViolation(
            "캡처 원본 경로가 사라졌습니다"
        )
    }
    return try CaptureStatSnapshot(value)
}

/// 캡처 당시 파일 위치와 PREMIS식 fixity를 보존한다.
