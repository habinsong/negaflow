import Foundation

enum LibraryBackupSizeEstimator {
    static let safetyMargin: Int64 = 10 * 1_024 * 1_024

    static func requiredBytes(catalogData: Data, defectData: [Data]) -> Int64 {
        let payload = Int64(catalogData.count + defectData.reduce(0) { $0 + $1.count })
        return payload + safetyMargin
    }
}
