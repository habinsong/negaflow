import Foundation
import Chromabase

// FilmType은 Chromabase가 소유한다 (현상 도메인 타입). ScannerKit은 재노출만 한다.

// MARK: - Enums (plan §7.4, §5)

/// 어떤 백엔드가 장치를 제어하는지. 사용자에게는 절대 노출되지 않는 내부 값.
public enum BackendType: String, Codable, Sendable {
    case imageCaptureCore   // Apple ImageCaptureCore (plan §6.2)
    case sane               // 기존 scannerID 호환용. 새 하드웨어 경로는 plugin을 쓴다.
    case plugin             // 외부 프로세스 스캐너 플러그인(설치형, negaflow와 독립)
    case mock               // 개발/데모용 가상 스캐너
}

public enum ConnectionType: String, Codable, Sendable {
    case usb
    case network
    case internalBus
}

/// Verified / Compatible Target / Experimental (plan §5.1)
public enum VerifiedStatus: String, Codable, Sendable {
    case verified           // 직접 테스트됨 (8200i)
    case compatibleTarget   // 호환 목표지만 미검증 (8100, 8300i)
    case experimental       // 일부 기능만 가능할 수 있음 (구형 OpticFilm)
}

public enum ColorMode: String, Codable, Sendable, CaseIterable {
    case color
    case gray
    case lineart
    case infrared
}

public enum BitDepth: Int, Codable, Sendable, CaseIterable {
    case eight = 8
    case sixteen = 16
}

/// 해상도(dpi). 0은 프리뷰(저해상도 overview)를 의미. (plan §7.4 resolution)
public struct Resolution: Codable, Sendable, Equatable, Comparable, Hashable {
    public let dpi: Int
    public init(_ dpi: Int) { self.dpi = dpi }
    public static let preview = Resolution(0)
    public static func < (lhs: Resolution, rhs: Resolution) -> Bool { lhs.dpi < rhs.dpi }

    /// 사용자에게 보여주는 문자열. preview는 "Preview".
    public var displayName: String { dpi == 0 ? "Preview" : "\(dpi)" }
}

public extension Resolution {
    static let r900  = Resolution(900)
    static let r1800 = Resolution(1800)
    static let r3600 = Resolution(3600)
    static let r7200 = Resolution(7200)
}

// MARK: - Scan area (plan §7.3 maxScanArea / minScanArea, §7.4 scanArea)

public struct ScanArea: Codable, Sendable, Equatable {
    /// 35mm 필름 한 프레임(단위: mm). 기본값은 풀 프레임 36×24.
    public var widthMM: Double
    public var heightMM: Double
    public init(widthMM: Double = 36.0, heightMM: Double = 24.0) {
        self.widthMM = widthMM; self.heightMM = heightMM
    }
    public static let fullFrame35mm = ScanArea()
}

public enum ScanAreaUnit: String, Codable, Sendable {
    case millimeter
    case inch
    case pixel
}
