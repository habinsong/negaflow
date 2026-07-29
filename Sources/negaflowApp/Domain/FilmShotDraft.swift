import Foundation

// MARK: - FilmShotDraft (촬영 기록 입력 문자열)
//
// 사람이 적는 표기("1/125", "f/2.8", "50mm")와 저장 값(초, 실수) 사이의 변환을 한 곳에 둔다.
// 프레임 편집과 롤 기록 편집이 같은 규칙을 쓰도록 두 화면이 이 타입을 공유한다.
struct FilmShotDraft: Equatable {
    var cameraMake = ""
    var cameraModel = ""
    var lensModel = ""
    var filmStock = ""
    var isoSpeed = ""
    var shutterSpeed = ""
    var aperture = ""
    var focalLength = ""

    init() {}

    init(_ shot: FilmShotMetadata?) {
        cameraMake = shot?.cameraMake ?? ""
        cameraModel = shot?.cameraModel ?? ""
        lensModel = shot?.lensModel ?? ""
        filmStock = shot?.filmStock ?? ""
        isoSpeed = shot?.isoSpeed.map(String.init) ?? ""
        shutterSpeed = shot?.exposureTimeSeconds.map(FilmShotMetadata.exposureTimeText) ?? ""
        aperture = shot?.fNumber.map { Self.decimalText($0) } ?? ""
        focalLength = shot?.focalLengthMM.map { Self.decimalText($0) } ?? ""
    }

    /// 읽을 수 없는 숫자는 조용히 버린다 — 적히지 않은 것과 같게 취급한다.
    var values: FilmShotMetadata {
        FilmShotMetadata(
            cameraMake: cameraMake,
            cameraModel: cameraModel,
            lensModel: lensModel,
            filmStock: filmStock,
            isoSpeed: Int(isoSpeed.trimmingCharacters(in: .whitespaces)),
            exposureTimeSeconds: FilmShotMetadata.exposureTime(fromText: shutterSpeed),
            fNumber: Self.decimalValue(aperture, droppingPrefix: "f/"),
            focalLengthMM: Self.decimalValue(focalLength, droppingSuffix: "mm")
        )
    }

    static func decimalText(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    static func decimalValue(
        _ text: String,
        droppingPrefix prefix: String = "",
        droppingSuffix suffix: String = ""
    ) -> Double? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !prefix.isEmpty, value.hasPrefix(prefix) { value.removeFirst(prefix.count) }
        if !suffix.isEmpty, value.hasSuffix(suffix) { value.removeLast(suffix.count) }
        return Double(value.trimmingCharacters(in: .whitespaces))
    }
}
