import Foundation

struct MetadataBounds {
    var discardedOversizedValues = false
    var discardedInvalidValues = false
    private var remainingTextBytes = SourceMetadataReader.maximumSnapshotTextBytes

    mutating func reserveTextBytes(_ byteCount: Int) -> Bool {
        guard byteCount >= 0, byteCount <= remainingTextBytes else {
            discardedOversizedValues = true
            return false
        }
        remainingTextBytes -= byteCount
        return true
    }
}
