import Foundation
import CoreGraphics

// MARK: - ExportOptions
//
// 내보내기 출력 제어: 색공간 / DPI / 크기(긴 변 리사이즈). format은 ExportFormat이 담당한다.
// 기존 호출부 호환을 위해 `.standard`(sRGB · DPI 미지정 · 원본 크기) 기본값을 둔다.

public enum ExportColorSpace: String, Sendable, CaseIterable, Codable {
    case sRGB
    case displayP3
    case adobeRGB

    public var uiLabel: String {
        switch self {
        case .sRGB: return "sRGB"
        case .displayP3: return "Display P3"
        case .adobeRGB: return "Adobe RGB"
        }
    }

    public var cgColorSpace: CGColorSpace {
        switch self {
        case .sRGB:
            return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        case .displayP3:
            return CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        case .adobeRGB:
            return CGColorSpace(name: CGColorSpace.adobeRGB1998) ?? CGColorSpaceCreateDeviceRGB()
        }
    }
}

public struct ExportOptions: Sendable {
    /// 출력 색공간(임베드 프로파일).
    public var colorSpace: ExportColorSpace
    /// 출력 메타데이터 DPI. 0이면 미기록.
    public var dpi: Int
    /// 긴 변 픽셀 상한. nil이면 원본 크기. 비율은 유지한다(축소만 — 업스케일 안 함).
    public var longEdge: Int?

    public init(colorSpace: ExportColorSpace = .sRGB, dpi: Int = 0, longEdge: Int? = nil) {
        self.colorSpace = colorSpace
        self.dpi = dpi
        self.longEdge = longEdge
    }

    public static let standard = ExportOptions()
}

extension ExportFormat {
    /// 사용자 표기용 짧은 라벨.
    public var uiLabel: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .tiff16: return "TIFF 16-bit"
        case .rawScanTIFF: return "Raw TIFF"
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .tiff16, .rawScanTIFF: return "tif"
        }
    }
}
