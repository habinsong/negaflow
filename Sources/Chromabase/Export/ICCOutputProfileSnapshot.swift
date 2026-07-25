import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// 최종 출력 경계에서 사용하는 측정 printer ICC의 불변 스냅샷입니다.
/// 일반 RGB working/display profile과 구분하기 위해 ICC output-device class만 허용합니다.
public struct ICCOutputProfileSnapshot: Equatable, Sendable {
    public let profileName: String
    public let iccProfileData: Data
    public let profileSHA256: String

    public init?(
        profileName: String,
        iccProfileData: Data,
        expectedSHA256: String? = nil
    ) {
        let normalizedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sha256 = Self.sha256(iccProfileData)
        guard !normalizedName.isEmpty,
              (expectedSHA256.map(Self.normalizedSHA256) ?? sha256) == sha256,
              Self.validatedColorSpace(for: iccProfileData) != nil else {
            return nil
        }
        self.profileName = normalizedName
        self.iccProfileData = iccProfileData
        profileSHA256 = sha256
    }

    /// 출력 직전에도 bytes와 SHA를 다시 결박해 변조나 잘못 복원된 snapshot의 fallback을 막습니다.
    public func validatedColorSpace() -> CGColorSpace? {
        guard Self.sha256(iccProfileData) == profileSHA256 else { return nil }
        return Self.validatedColorSpace(for: iccProfileData)
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func embeddedProfileSHA256(at url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(
                  source,
                  0,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              ), let profile = image.colorSpace?.copyICCData() else {
            return nil
        }
        return sha256(profile as Data)
    }

    private static func validatedColorSpace(for data: Data) -> CGColorSpace? {
        guard data.count >= 128,
              Int(readUInt32(data, at: 0)) == data.count,
              signature(data, at: 12) == "prtr",
              signature(data, at: 16) == "RGB ",
              ["Lab ", "XYZ "].contains(signature(data, at: 20)),
              signature(data, at: 36) == "acsp",
              let colorSpace = CGColorSpace(iccData: data as CFData),
              colorSpace.model == .rgb,
              colorSpace.supportsOutput,
              CGColorConversionInfo(
                optionsSrc: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                dst: colorSpace,
                options: nil
              ) != nil,
              CGColorConversionInfo(
                optionsSrc: colorSpace,
                dst: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                options: nil
              ) != nil else {
            return nil
        }
        return colorSpace
    }

    private static func normalizedSHA256(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("sha256:") ? String(trimmed.dropFirst(7)) : trimmed
    }

    private static func signature(_ data: Data, at offset: Int) -> String? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        return String(data: data[offset..<(offset + 4)], encoding: .ascii)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }
}
