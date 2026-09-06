import CryptoKit
import Foundation

/// 큰 마스크는 디스크 저장·읽기 경계에서만 해시합니다. 슬라이더 경로에는 추가하지 않습니다.
enum DefectSidecarPayloadDigest {
    static func sha256(_ items: [DefectEditItemRecord]) -> String {
        var hash = SHA256()
        func append(_ payload: DefectCompressedData?) {
            var count = UInt64(payload?.data.count ?? 0).bigEndian
            withUnsafeBytes(of: &count) { hash.update(data: Data($0)) }
            hash.update(data: Data([payload == nil ? 0 : (payload!.zlib ? 2 : 1)]))
            if let payload { hash.update(data: payload.data) }
        }
        for item in items {
            hash.update(data: Data(item.id.uuidString.utf8))
            append(item.regionMask)
            for cluster in item.clusters ?? [] {
                append(cluster.mask)
                append(cluster.attenuation)
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
