import CryptoKit
import Foundation

extension RenderManifest {
    public static func sourceIdentity(
        for url: URL,
        chunkSize: Int = 1_048_576
    ) throws -> SourceIdentity {
        guard chunkSize > 0 else { throw RenderManifestValidationError.invalidChunkSize }
        let source = url.resolvingSymlinksInPath()
        let before = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }

        var hasher = SHA256()
        var byteCount: Int64 = 0
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            guard chunk.count <= Int64.max - byteCount else {
                throw CocoaError(.fileReadTooLarge)
            }
            byteCount += Int64(chunk.count)
            hasher.update(data: chunk)
        }
        let after = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard before.fileSize == after.fileSize,
              before.contentModificationDate == after.contentModificationDate,
              byteCount == Int64(after.fileSize ?? -1) else {
            throw RenderManifestValidationError.sourceChangedDuringHash
        }
        return SourceIdentity(byteCount: byteCount, sha256: hex(hasher.finalize()))
    }

    public static func developRecipeSHA256(for parameters: DevelopParameters) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return hex(SHA256.hash(data: try encoder.encode(parameters)))
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
