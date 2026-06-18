import Foundation
import CoreImage
import CoreGraphics
import ImageIO

// MARK: - ExportEngine (plan §9.6, §8.3)
//
// JPEG 95% 기본 / 16bit TIFF 옵션 / Raw 보관. (plan §4.2)
// 출력은 sRGB로 변환 (plan §8.3 MVP).
public enum ExportEngine {
    public static func write(_ image: CIImage, to url: URL, format: ExportFormat,
                             using context: CIContext) throws {
        switch format {
        case .jpeg:
            try writeJPEG(image, to: url, using: context, quality: 0.95)
        case .tiff16:
            try writeTIFF(image, to: url, using: context, bitsPerComponent: 16)
        case .rawScanTIFF:
            try writeTIFF(image, to: url, using: context, bitsPerComponent: 16)
        }
    }

    static func writeJPEG(_ image: CIImage, to url: URL, using context: CIContext,
                          quality: CGFloat) throws {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
        ]
        let cg = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: cs)
        guard let cg else { throw ChromabaseError.writeFailed("createCGImage nil: \(url.path)") }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
        else { throw ChromabaseError.writeFailed("CGImageDestinationCreateWithURL nil: \(url.path)") }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ChromabaseError.writeFailed("CGImageDestinationFinalize failed: \(url.path)")
        }
    }

    static func writeTIFF(_ image: CIImage, to url: URL, using context: CIContext,
                          bitsPerComponent: Int) throws {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil)
        else { throw ChromabaseError.writeFailed(url.path) }
        // 16bit 출력을 위해 CIContext를 통해 비트깊이를 지정한 CGImage를 만든다.
        let format: CIFormat = bitsPerComponent == 16 ? .RGBAh : .RGBA8
        let cg = context.createCGImage(image, from: image.extent, format: format, colorSpace: cs)
        guard let cg else { throw ChromabaseError.writeFailed(url.path) }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ChromabaseError.writeFailed(url.path)
        }
    }
}

// MARK: - Sidecar (non-destructive editing, plan §8.11)
//
// 각 프레임마다 sidecar JSON을 저장한다. 스캔 원본은 보존된다.
public struct Sidecar: Codable, Sendable {
    public var appVersion: String
    public var engineVersion: String
    public var scannerModel: String?
    public var backendUsed: String?
    public var scanResolution: Int?
    public var bitDepth: Int?
    public var filmType: String
    public var crop: CropRect?
    public var baseSample: BaseSample?
    public var presetName: String?
    public var parameters: DevelopParameters
    public var exportHistory: [ExportRecord]

    public struct CropRect: Codable, Sendable {
        public var x: Double; public var y: Double; public var w: Double; public var h: Double
    }
    public struct BaseSample: Codable, Sendable {
        public var r: Double; public var g: Double; public var b: Double
        public var source: String
        public init(_ fb: FilmBase) { r = fb.rgb.x; g = fb.rgb.y; b = fb.rgb.z; source = fb.source.rawValue }
    }
    public struct ExportRecord: Codable, Sendable {
        public var path: String; public var format: String; public var at: Date
    }

    public init(filmType: FilmType, parameters: DevelopParameters) {
        self.appVersion = "0.1.0"
        self.engineVersion = "chromabase-0.1"
        self.filmType = filmType.rawValue
        self.parameters = parameters
        self.exportHistory = []
    }

    public func write(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(self).write(to: url)
    }
}
