import Foundation
import CoreImage
import CoreGraphics
import ImageIO

// MARK: - ExportEngine (plan §9.6, §8.3)
//
// JPEG 95% 기본 / 16bit TIFF 옵션 / Raw 보관. (plan §4.2)
// 출력은 sRGB로 변환 (plan §8.3 MVP).
// EXIF(scanner/dpi/film/software) 자동 주입.
public enum ExportEngine {
    public static func write(_ image: CIImage, to url: URL, format: ExportFormat,
                             using context: CIContext, metadata: ExportMeta? = nil) throws {
        switch format {
        case .jpeg:
            try writeJPEG(image, to: url, using: context, quality: 0.95, metadata: metadata)
        case .png:
            try writePNG(image, to: url, using: context, metadata: metadata)
        case .tiff16:
            try writeTIFF(image, to: url, using: context, bitsPerComponent: 16, metadata: metadata)
        case .rawScanTIFF:
            try writeTIFF(image, to: url, using: context, bitsPerComponent: 16, metadata: metadata)
        }
    }

    static func writeJPEG(_ image: CIImage, to url: URL, using context: CIContext,
                          quality: CGFloat, metadata: ExportMeta? = nil) throws {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        var props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
        ]
        props.merge(metadataProperties(metadata)) { _, new in new }
        let cg = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: cs)
        guard let cg else { throw ChromabaseError.writeFailed("createCGImage nil: \(url.path)") }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
        else { throw ChromabaseError.writeFailed("CGImageDestinationCreateWithURL nil: \(url.path)") }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ChromabaseError.writeFailed("CGImageDestinationFinalize failed: \(url.path)")
        }
    }

    static func writePNG(_ image: CIImage, to url: URL, using context: CIContext,
                         metadata: ExportMeta? = nil) throws {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cg = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: cs)
        else { throw ChromabaseError.writeFailed("createCGImage nil: \(url.path)") }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { throw ChromabaseError.writeFailed("CGImageDestinationCreateWithURL nil: \(url.path)") }
        CGImageDestinationAddImage(dest, cg, metadataProperties(metadata) as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ChromabaseError.writeFailed("CGImageDestinationFinalize failed: \(url.path)")
        }
    }

    static func writeTIFF(_ image: CIImage, to url: URL, using context: CIContext,
                          bitsPerComponent: Int, metadata: ExportMeta? = nil) throws {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil)
        else { throw ChromabaseError.writeFailed(url.path) }
        let format: CIFormat = bitsPerComponent == 16 ? .RGBA16 : .RGBA8
        let cg = context.createCGImage(image, from: image.extent, format: format, colorSpace: cs)
        guard let cg else { throw ChromabaseError.writeFailed(url.path) }
        let props = metadataProperties(metadata) as CFDictionary
        CGImageDestinationAddImage(dest, cg, props)
        guard CGImageDestinationFinalize(dest) else {
            throw ChromabaseError.writeFailed(url.path)
        }
    }

    /// ExportMeta → CGImageDestination props(EXIF + TIFF dictionary).
    /// transform이 픽셀에 구워졌으므로 orientation=1.
    static func metadataProperties(_ meta: ExportMeta?) -> [CFString: Any] {
        guard let meta = meta else { return [:] }
        var exif: [String: Any] = [:]
        var tiff: [String: Any] = [:]
        if let make = meta.scannerModel {
            // Make = 제조사, Model = 모델명. scannerModel 이 "Plustek OpticFilm 8200i" 면
            // 첫 토큰을 Make, 나머지를 Model 로 분리.
            let parts = make.split(separator: " ", maxSplits: 1).map(String.init)
            exif["Make"] = parts.first
            tiff["Make"] = parts.first
            exif["Model"] = parts.count > 1 ? parts[1] : make
            tiff["Model"] = parts.count > 1 ? parts[1] : make
        }
        if let dpi = meta.resolutionDPI, dpi > 0 {
            exif["XResolution"] = dpi as NSNumber
            exif["YResolution"] = dpi as NSNumber
            exif["ResolutionUnit"] = 2   // inches
            tiff["XResolution"] = dpi as NSNumber
            tiff["YResolution"] = dpi as NSNumber
            tiff["ResolutionUnit"] = 2
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy:MM:dd HH:mm:ss"
        exif["DateTimeOriginal"] = df.string(from: Date())
        exif["DateTimeDigitized"] = df.string(from: Date())
        if let software = meta.software { exif["Software"] = software; tiff["Software"] = software }
        if let film = meta.filmType { exif["UserComment"] = "FilmType: \(film)" }
        exif["Orientation"] = 1   // transform 구움
        var props: [CFString: Any] = [:]
        props[kCGImagePropertyExifDictionary] = exif
        props[kCGImagePropertyTIFFDictionary] = tiff
        props[kCGImagePropertyOrientation] = 1
        return props
    }
}

/// 출력 파일에 들어갈 EXIF/TIFF 메타데이터.
public struct ExportMeta: Sendable {
    public var scannerModel: String?
    public var resolutionDPI: Int?
    public var filmType: String?
    public var software: String?
    public init(scannerModel: String? = nil, resolutionDPI: Int? = nil,
                filmType: String? = nil, software: String? = nil) {
        self.scannerModel = scannerModel
        self.resolutionDPI = resolutionDPI
        self.filmType = filmType
        self.software = software
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
        public init(x: Double, y: Double, w: Double, h: Double) {
            self.x = x; self.y = y; self.w = w; self.h = h
        }
    }
    public struct BaseSample: Codable, Sendable {
        public var r: Double; public var g: Double; public var b: Double
        public var source: String
        public init(_ fb: FilmBase) { r = fb.rgb.x; g = fb.rgb.y; b = fb.rgb.z; source = fb.source.rawValue }
    }
    public struct ExportRecord: Codable, Sendable {
        public var path: String; public var format: String; public var at: Date
        public init(path: String, format: String, at: Date) {
            self.path = path; self.format = format; self.at = at
        }
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
