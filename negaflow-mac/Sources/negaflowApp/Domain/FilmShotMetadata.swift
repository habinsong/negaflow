import Foundation
import ImageIO
import Chromabase

// MARK: - FilmShotMetadata (촬영 기록)
//
// 필름 카메라는 EXIF를 남기지 않는다. 스캔 파일에 적히는 카메라·렌즈·노출은 스캐너나 복사 촬영
// 장비의 것이지 그 사진을 찍은 카메라의 것이 아니다. 사용자가 적어 둔 촬영 기록을 내보낼 때
// 결과 파일의 EXIF/TIFF에 기록해, 다른 앱이 그대로 읽을 수 있게 한다.
//
// 기록은 카탈로그의 앱 메타데이터 오버레이 안에만 산다. 원본 파일은 절대 수정하지 않는다.
struct FilmShotMetadata: Codable, Equatable, Sendable {
    /// 노출 시간 상한(초). 이보다 긴 값은 오타로 보고 버린다.
    static let maximumExposureTimeSeconds = 3_600.0

    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var filmStock: String?
    var isoSpeed: Int?
    var exposureTimeSeconds: Double?
    var fNumber: Double?
    var focalLengthMM: Double?

    init(
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil,
        filmStock: String? = nil,
        isoSpeed: Int? = nil,
        exposureTimeSeconds: Double? = nil,
        fNumber: Double? = nil,
        focalLengthMM: Double? = nil
    ) {
        self.cameraMake = AppMetadataOverlay.normalizedText(cameraMake)
        self.cameraModel = AppMetadataOverlay.normalizedText(cameraModel)
        self.lensModel = AppMetadataOverlay.normalizedText(lensModel)
        self.filmStock = AppMetadataOverlay.normalizedText(filmStock)
        self.isoSpeed = isoSpeed.flatMap { $0 > 0 ? $0 : nil }
        self.exposureTimeSeconds = Self.normalizedExposureTime(exposureTimeSeconds)
        self.fNumber = Self.normalizedPositive(fNumber)
        self.focalLengthMM = Self.normalizedPositive(focalLengthMM)
    }

    var isEmpty: Bool {
        cameraMake == nil && cameraModel == nil && lensModel == nil && filmStock == nil
            && isoSpeed == nil && exposureTimeSeconds == nil && fNumber == nil
            && focalLengthMM == nil
    }

    var isValid: Bool {
        [cameraMake, cameraModel, lensModel, filmStock].allSatisfy {
            $0.map { !$0.isEmpty && $0.utf8.count <= AppMetadataOverlay.maximumTextBytes } ?? true
        }
            && isoSpeed.map { $0 > 0 } ?? true
            && exposureTimeSeconds == Self.normalizedExposureTime(exposureTimeSeconds)
            && fNumber == Self.normalizedPositive(fNumber)
            && focalLengthMM == Self.normalizedPositive(focalLengthMM)
    }

    /// 촬영 기록을 내보내기 메타데이터에 얹는다. 필름 스톡은 표준 EXIF 태그가 없어
    /// 엔진의 UserComment 경로(`ExportMeta.filmStock`)로 따로 간다.
    func applying(to metadata: ExportSourceMetadata) -> ExportSourceMetadata {
        var result = metadata
        if let cameraMake {
            result.tiff[kCGImagePropertyTIFFMake as String] = .string(cameraMake)
        }
        if let cameraModel {
            result.tiff[kCGImagePropertyTIFFModel as String] = .string(cameraModel)
        }
        if let lensModel {
            result.exif[kCGImagePropertyExifLensModel as String] = .string(lensModel)
        }
        if let isoSpeed {
            result.exif[kCGImagePropertyExifISOSpeedRatings as String] = .integers([isoSpeed])
        }
        if let exposureTimeSeconds {
            result.exif[kCGImagePropertyExifExposureTime as String] = .number(exposureTimeSeconds)
        }
        if let fNumber {
            result.exif[kCGImagePropertyExifFNumber as String] = .number(fNumber)
        }
        if let focalLengthMM {
            result.exif[kCGImagePropertyExifFocalLength as String] = .number(focalLengthMM)
        }
        return result
    }

    private static func normalizedExposureTime(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0, value <= maximumExposureTimeSeconds else {
            return nil
        }
        return value
    }

    private static func normalizedPositive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}

// MARK: - 셔터 속도 텍스트

extension FilmShotMetadata {
    /// 초 단위를 뜻하는 꼬리표. 사진가는 s, ", 초를 섞어 쓴다.
    private static let secondsSuffixes: Set<Character> = ["s", "\u{22}", "\u{CD08}"]

    /// "1/125", "1/125s", "2", "2s" 를 초로 읽는다. 읽을 수 없으면 nil.
    static func exposureTime(fromText text: String) -> Double? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while let last = value.last, secondsSuffixes.contains(last) {
            value.removeLast()
        }
        value = value.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        if let separator = value.firstIndex(of: "/") {
            guard let numerator = Double(value[value.startIndex..<separator]),
                  let denominator = Double(value[value.index(after: separator)...]),
                  denominator > 0 else { return nil }
            return normalizedExposureTime(numerator / denominator)
        }
        return normalizedExposureTime(Double(value))
    }

    /// 1초 미만은 사진가가 읽는 방식(1/125)으로, 그 이상은 초로 보여준다.
    static func exposureTimeText(_ seconds: Double) -> String {
        guard seconds > 0 else { return String() }
        if seconds < 1 {
            return "1/\(Int((1 / seconds).rounded()))"
        }
        return seconds == seconds.rounded()
            ? "\(Int(seconds))"
            : String(format: "%.1f", seconds)
    }
}
