import Foundation

public enum ExportTIFFCompression: String, Codable, CaseIterable, Sendable {
    case none
    case lzw
    case deflate

    var imageIOValue: Int {
        switch self {
        case .none: 1
        case .lzw: 5
        case .deflate: 8
        }
    }
}

public enum ExportTIFFBitDepth: Int, Codable, CaseIterable, Sendable {
    case eight = 8
    case sixteen = 16
}

public enum ExportOptionsError: Error, LocalizedError, Equatable {
    case invalidDPI
    case invalidLongEdge
    case invalidJPEGQuality
    case invalidOutputSharpening
    case unsupportedAlpha(ExportFormat)
    case unsupportedRawTIFFOptions

    public var errorDescription: String? {
        switch self {
        case .invalidDPI: "Export DPI must be zero or positive."
        case .invalidLongEdge: "Export long edge must be positive."
        case .invalidJPEGQuality: "JPEG quality must be between 0 and 1."
        case .invalidOutputSharpening: "Output sharpening must be between 0 and 1."
        case .unsupportedAlpha(let format): "Alpha is not supported for \(format.rawValue)."
        case .unsupportedRawTIFFOptions: "Raw TIFF requires 16-bit uncompressed opaque output."
        }
    }
}

public extension ExportOptions {
    func validate(for format: ExportFormat) throws {
        guard dpi >= 0 else { throw ExportOptionsError.invalidDPI }
        guard longEdge.map({ $0 > 0 }) ?? true else {
            throw ExportOptionsError.invalidLongEdge
        }
        guard jpegQuality.isFinite, (0...1).contains(jpegQuality) else {
            throw ExportOptionsError.invalidJPEGQuality
        }
        guard outputSharpening.isFinite, (0...1).contains(outputSharpening) else {
            throw ExportOptionsError.invalidOutputSharpening
        }
        if format == .jpeg, preserveAlpha {
            throw ExportOptionsError.unsupportedAlpha(format)
        }
        if format == .rawScanTIFF,
           (tiffBitDepth != .sixteen || tiffCompression != .none || preserveAlpha
               || outputSharpening > 0 || longEdge != nil) {
            throw ExportOptionsError.unsupportedRawTIFFOptions
        }
    }
}
