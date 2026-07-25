import Foundation

struct SourceEXIFMetadata: Codable, Equatable, Sendable {
    var dateTimeOriginalRaw: String?
    var offsetTimeOriginalRaw: String?
    var subsecondTimeOriginalRaw: String?
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var software: String?
    var exposureTimeSeconds: Double?
    var fNumber: Double?
    var isoSpeedRatings: [Int]
    var focalLengthMM: Double?

    /// raw 문자열이 authoritative하다. 시간대가 명시된 경우에만 계산한다.
    var capturedAt: Date? {
        SourceMetadataReader.parseEXIFDate(
            dateTimeRaw: dateTimeOriginalRaw,
            offsetRaw: offsetTimeOriginalRaw,
            subsecondRaw: subsecondTimeOriginalRaw
        )
    }

    var isEmpty: Bool {
        dateTimeOriginalRaw == nil
            && offsetTimeOriginalRaw == nil
            && subsecondTimeOriginalRaw == nil
            && cameraMake == nil
            && cameraModel == nil
            && lensModel == nil
            && software == nil
            && exposureTimeSeconds == nil
            && fNumber == nil
            && isoSpeedRatings.isEmpty
            && focalLengthMM == nil
    }
}
