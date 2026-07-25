import Foundation

/// 원본 파일에서 가져온 불변 메타데이터 스냅샷이다. 앱의 별점/플래그/현상 recipe와 분리해
/// 원본이 오프라인이어도 검색·정렬·출처 확인에 사용할 수 있게 한다.
struct SourceMetadataSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int = currentVersion
    var fileTypeIdentifier: String?
    var fileSizeBytes: Int64?
    var imageIndex: Int = 0
    var imageCount: Int?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var dpiWidth: Double?
    var dpiHeight: Double?
    var resolutionDPI: Int?
    /// 색상 sample 하나당 bit 수다. 전체 pixel bit 수가 아니다.
    var bitsPerColorSample: Int?
    /// ImageIO/EXIF orientation 원시값(1...8). 픽셀에 적용된 앱 transform과는 별개다.
    var orientation: Int?
    var colorModel: String?
    var colorProfileName: String?
    var namedColorSpace: String?
    var exif: SourceEXIFMetadata?
    var iptc: SourceIPTCMetadata?
    /// ImageIO가 EXIF/IPTC를 XMP schema로 정규화해 노출할 수 있으므로 실제 XMP packet
    /// 존재 증거로 해석하지 않는다.
    var imageMetadataXMPView: SourceXMPMetadata?
    /// ImageIO가 직렬화한 정규화 metadata view 바이트의 SHA-256이다.
    var imageMetadataXMPViewSHA256: String?
    var sidecarXMP: SourceXMPMetadata?
    /// 외부 XMP 파일 원문 바이트의 SHA-256이다. 외부 변경 감지의 기준값으로 사용한다.
    var sidecarXMPFileSHA256: String?
    var sidecarXMPState: SourceXMPReadState = .notFound
    /// 위치 좌표 자체는 카탈로그에 복제하지 않고 존재 여부만 보존한다.
    var containsStandardGPSMetadata: Bool = false
    /// 비정상적으로 큰 입력값을 카탈로그에 넣지 않고 제외했음을 명시한다.
    var discardedOversizedValues: Bool = false
    /// 타입·범위를 위반한 외부 값을 제외했음을 명시한다.
    var discardedInvalidValues: Bool = false
}
