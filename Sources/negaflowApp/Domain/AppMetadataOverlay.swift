import CryptoKit
import Foundation
import ImageIO
import Chromabase

struct AppMetadataOverlay: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let maximumTextBytes = 4_096
    static let maximumKeywords = 128

    var version = currentVersion
    var title: String?
    var caption: String?
    var keywords: [String]
    var copyright: String?
    var sourceMetadataSHA256: String?
    var revision: UInt64
    var updatedAt: Date

    init(
        title: String? = nil,
        caption: String? = nil,
        keywords: [String] = [],
        copyright: String? = nil,
        sourceMetadataSHA256: String?,
        revision: UInt64,
        updatedAt: Date = Date()
    ) {
        self.title = Self.normalizedText(title)
        self.caption = Self.normalizedText(caption)
        self.keywords = Self.normalizedKeywords(keywords)
        self.copyright = Self.normalizedText(copyright)
        self.sourceMetadataSHA256 = sourceMetadataSHA256
        self.revision = revision
        self.updatedAt = updatedAt
    }

    var isEmpty: Bool {
        title == nil && caption == nil && keywords.isEmpty && copyright == nil
    }

    var isValid: Bool {
        version == Self.currentVersion
            && revision > 0
            && updatedAt.timeIntervalSinceReferenceDate.isFinite
            && [title, caption, copyright].allSatisfy {
                $0.map { !$0.isEmpty && $0.utf8.count <= Self.maximumTextBytes } ?? true
            }
            && keywords == Self.normalizedKeywords(keywords)
            && Self.validSHA256(sourceMetadataSHA256)
    }

    func conflicts(with snapshot: SourceMetadataSnapshot?) -> Bool {
        sourceMetadataSHA256 != snapshot?.appMetadataIdentitySHA256()
    }

    func applying(to source: ExportSourceMetadata?) -> ExportSourceMetadata {
        var result = source ?? ExportSourceMetadata()
        if let title {
            result.iptc[kCGImagePropertyIPTCObjectName as String] = .string(title)
        }
        if let caption {
            result.iptc[kCGImagePropertyIPTCCaptionAbstract as String] = .string(caption)
        }
        if !keywords.isEmpty {
            result.iptc[kCGImagePropertyIPTCKeywords as String] = .strings(keywords)
        }
        if let copyright {
            result.iptc[kCGImagePropertyIPTCCopyrightNotice as String] = .string(copyright)
            result.tiff[kCGImagePropertyTIFFCopyright as String] = .string(copyright)
        }
        return result
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        while value.utf8.count > maximumTextBytes { value.removeLast() }
        return value
    }

    private static func normalizedKeywords(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.prefix(maximumKeywords).compactMap { raw in
            guard let value = normalizedText(raw) else { return nil }
            let key = value.folding(options: [.caseInsensitive], locale: .current)
            return seen.insert(key).inserted ? value : nil
        }
    }

    private static func validSHA256(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

extension SourceMetadataSnapshot {
    func appMetadataIdentitySHA256() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
