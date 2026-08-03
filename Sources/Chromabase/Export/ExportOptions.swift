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

public struct ExportOptions: Sendable, Codable, Equatable {
    /// 출력 색공간(임베드 프로파일).
    public var colorSpace: ExportColorSpace
    /// 출력 메타데이터 DPI. 0이면 미기록.
    public var dpi: Int
    /// 긴 변 픽셀 상한. nil이면 원본 크기. 비율은 유지한다(축소만 — 업스케일 안 함).
    public var longEdge: Int?
    public var jpegQuality: Double
    public var tiffCompression: ExportTIFFCompression
    public var tiffBitDepth: ExportBitDepth
    /// PNG는 무손실이라 품질 손잡이가 없다. 화질을 정하는 유일한 값이 비트 심도다.
    public var pngBitDepth: ExportBitDepth
    public var preserveAlpha: Bool
    public var metadataPolicy: ExportMetadataPolicy
    public var outputSharpening: Double
    public var outputSharpeningMedium: OutputSharpeningMedium

    public init(
        colorSpace: ExportColorSpace = .sRGB,
        dpi: Int = 0,
        longEdge: Int? = nil,
        jpegQuality: Double = 1.0,
        tiffCompression: ExportTIFFCompression = .none,
        tiffBitDepth: ExportBitDepth = .sixteen,
        pngBitDepth: ExportBitDepth = .sixteen,
        preserveAlpha: Bool = false,
        metadataPolicy: ExportMetadataPolicy = .minimal,
        outputSharpening: Double = 0,
        outputSharpeningMedium: OutputSharpeningMedium = .screen
    ) {
        self.colorSpace = colorSpace
        self.dpi = dpi
        self.longEdge = longEdge
        self.jpegQuality = jpegQuality
        self.tiffCompression = tiffCompression
        self.tiffBitDepth = tiffBitDepth
        self.pngBitDepth = pngBitDepth
        self.preserveAlpha = preserveAlpha
        self.metadataPolicy = metadataPolicy
        self.outputSharpening = outputSharpening
        self.outputSharpeningMedium = outputSharpeningMedium
    }

    private enum CodingKeys: String, CodingKey {
        case colorSpace, dpi, longEdge, jpegQuality, tiffCompression, tiffBitDepth
        case pngBitDepth
        case preserveAlpha, metadataPolicy, outputSharpening, outputSharpeningMedium
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        colorSpace = try container.decode(ExportColorSpace.self, forKey: .colorSpace)
        dpi = try container.decode(Int.self, forKey: .dpi)
        longEdge = try container.decodeIfPresent(Int.self, forKey: .longEdge)
        jpegQuality = try container.decodeIfPresent(Double.self, forKey: .jpegQuality) ?? 1.0
        tiffCompression = try container.decodeIfPresent(
            ExportTIFFCompression.self,
            forKey: .tiffCompression
        ) ?? .none
        tiffBitDepth = try container.decodeIfPresent(
            ExportBitDepth.self,
            forKey: .tiffBitDepth
        ) ?? .sixteen
        pngBitDepth = try container.decodeIfPresent(
            ExportBitDepth.self,
            forKey: .pngBitDepth
        ) ?? .sixteen
        preserveAlpha = try container.decodeIfPresent(Bool.self, forKey: .preserveAlpha) ?? false
        metadataPolicy = try container.decodeIfPresent(
            ExportMetadataPolicy.self,
            forKey: .metadataPolicy
        ) ?? .minimal
        outputSharpening = try container.decodeIfPresent(
            Double.self,
            forKey: .outputSharpening
        ) ?? 0
        outputSharpeningMedium = try container.decodeIfPresent(
            OutputSharpeningMedium.self,
            forKey: .outputSharpeningMedium
        ) ?? .screen
    }

    public static let standard = ExportOptions()
}

extension ExportFormat {
    /// 사용자 표기용 짧은 라벨.
    public var uiLabel: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .tiff16: return "TIFF"
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
