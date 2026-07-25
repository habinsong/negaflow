import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

public struct CaptureFileIdentity: Codable, Sendable, Equatable {
    public let originalURL: URL
    public let byteCount: UInt64
    public let sha256: String

    public init(originalURL: URL, byteCount: UInt64, sha256: String) throws {
        self.originalURL = originalURL
        self.byteCount = byteCount
        self.sha256 = sha256
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case originalURL
        case byteCount
        case sha256
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        originalURL = try container.decode(URL.self, forKey: .originalURL)
        byteCount = try container.decode(UInt64.self, forKey: .byteCount)
        sha256 = try container.decode(String.self, forKey: .sha256)
        try decodeValidated(self, decoder: decoder)
    }

    /// 파일 전체를 메모리에 올리지 않고 SHA-256과 실제 읽은 바이트 수를 계산한다.
    /// 파일은 읽기 전용으로 열며 원본 바이트나 메타데이터를 변경하지 않는다.
    public static func build(for url: URL, chunkSize: Int = 1_048_576) throws -> CaptureFileIdentity {
        let observation = try CaptureFileObservation.capture(for: url)
        return try build(
            for: url,
            expectedObservation: observation,
            chunkSize: chunkSize,
            didReadChunk: nil
        )
    }

    /// 동일 크기 덮어쓰기/경로 교체를 결정적으로 검증하기 위한 내부 seam.
    /// 프로덕션 호출은 observer를 전달하지 않는다.
    static func build(
        for url: URL,
        chunkSize: Int,
        didReadChunk: ((UInt64) throws -> Void)?
    ) throws -> CaptureFileIdentity {
        let observation = try CaptureFileObservation.capture(for: url)
        return try build(
            for: url,
            expectedObservation: observation,
            chunkSize: chunkSize,
            didReadChunk: didReadChunk
        )
    }

    static func build(
        for url: URL,
        expectedObservation: CaptureFileObservation,
        chunkSize: Int,
        didReadChunk: ((UInt64) throws -> Void)? = nil
    ) throws -> CaptureFileIdentity {
        guard chunkSize > 0 else {
            throw ScanWorkflowValidationError.invalidValue("chunkSize는 1 이상이어야 합니다")
        }
        try expectedObservation.validate()
        guard expectedObservation.originalURL.standardizedFileURL == url.standardizedFileURL else {
            throw ScanWorkflowValidationError.invariantViolation(
                "fixity 대상 경로가 캡처 완료 관찰 경로와 다릅니다"
            )
        }
        try expectedObservation.verifyCurrentFile()

        let descriptor = try openCaptureFileDescriptor(for: url)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        let before = try captureStat(for: descriptor)
        guard before.isRegularFile,
              try before.observation(for: url) == expectedObservation else {
            throw ScanWorkflowValidationError.invariantViolation(
                "fixity 계산을 시작하기 전에 캡처 원본 파일이 변경되었습니다"
            )
        }
        var hasher = SHA256()
        var streamedByteCount: UInt64 = 0

        while let data = try handle.read(upToCount: chunkSize), !data.isEmpty {
            hasher.update(data: data)
            let (nextCount, overflow) = streamedByteCount.addingReportingOverflow(UInt64(data.count))
            guard !overflow else {
                throw ScanWorkflowValidationError.invalidValue("캡처 원본 크기가 UInt64 범위를 초과합니다")
            }
            streamedByteCount = nextCount
            try didReadChunk?(streamedByteCount)
        }

        let after = try captureStat(for: descriptor)
        let pathAfter = try captureStat(forPath: url)
        guard before == after,
              after == pathAfter,
              try after.observation(for: url) == expectedObservation,
              streamedByteCount == after.size else {
            throw ScanWorkflowValidationError.invariantViolation(
                "fixity 계산 중 캡처 원본 파일이 변경되었습니다"
            )
        }
        try expectedObservation.verifyCurrentFile()

        return try CaptureFileIdentity(
            originalURL: url,
            byteCount: streamedByteCount,
            sha256: hexString(hasher.finalize())
        )
    }

    public func validate() throws {
        guard originalURL.isFileURL else {
            throw ScanWorkflowValidationError.invalidValue("captureFile.originalURL은 file URL이어야 합니다")
        }
        guard byteCount > 0 else {
            throw ScanWorkflowValidationError.invalidValue("captureFile.byteCount는 1 이상이어야 합니다")
        }
        guard sha256.count == 64,
              sha256.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...102).contains(byte)
              }) else {
            throw ScanWorkflowValidationError.invalidValue(
                "captureFile.sha256은 소문자 64자리 SHA-256이어야 합니다"
            )
        }
    }

    private static func hexString<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        let digits = Array("0123456789abcdef".utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(64)
        for byte in digest {
            bytes.append(digits[Int(byte >> 4)])
            bytes.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// ScanResult의 캡처 결과 메타데이터를 영속 가능한 값으로 고정한다.
