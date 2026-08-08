import Foundation

enum ExportEncodingLocalizedText {
    case jpegQuality
    case tiffCompression
    case tiffBitDepth
    case pngBitDepth
    case preserveAlpha
    case none
    case lzw
    case deflate

    func resolved(language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english:
            switch self {
            case .jpegQuality: "JPEG Quality"
            case .tiffCompression: "TIFF Compression"
            case .tiffBitDepth: "TIFF Bit Depth"
            case .pngBitDepth: "PNG Bit Depth"
            case .preserveAlpha: "Preserve Alpha"
            case .none: "None"
            case .lzw: "LZW"
            case .deflate: "ZIP"
            }
        case .korean:
            switch self {
            case .jpegQuality: "JPEG 품질"
            case .tiffCompression: "TIFF 압축"
            case .tiffBitDepth: "TIFF 비트 심도"
            case .pngBitDepth: "PNG 비트 심도"
            case .preserveAlpha: "알파 보존"
            case .none: "없음"
            case .lzw: "LZW"
            case .deflate: "ZIP"
            }
        case .japanese:
            switch self {
            case .jpegQuality: "JPEG品質"
            case .tiffCompression: "TIFF圧縮"
            case .tiffBitDepth: "TIFFビット深度"
            case .pngBitDepth: "PNGビット深度"
            case .preserveAlpha: "アルファを保持"
            case .none: "なし"
            case .lzw: "LZW"
            case .deflate: "ZIP"
            }
        case .simplifiedChinese:
            switch self {
            case .jpegQuality: "JPEG质量"
            case .tiffCompression: "TIFF压缩"
            case .tiffBitDepth: "TIFF位深度"
            case .pngBitDepth: "PNG位深度"
            case .preserveAlpha: "保留Alpha"
            case .none: "无"
            case .lzw: "LZW"
            case .deflate: "ZIP"
            }
        case .french:
            switch self {
            case .jpegQuality: "Qualité JPEG"
            case .tiffCompression: "Compression TIFF"
            case .tiffBitDepth: "Profondeur TIFF"
            case .pngBitDepth: "Profondeur PNG"
            case .preserveAlpha: "Conserver l’alpha"
            case .none: "Aucune"
            case .lzw: "LZW"
            case .deflate: "ZIP"
            }
        case .german:
            switch self {
            case .jpegQuality: "JPEG-Qualität"
            case .tiffCompression: "TIFF-Komprimierung"
            case .tiffBitDepth: "TIFF-Bittiefe"
            case .pngBitDepth: "PNG-Bittiefe"
            case .preserveAlpha: "Alpha beibehalten"
            case .none: "Keine"
            case .lzw: "LZW"
            case .deflate: "ZIP"
            }
        }
    }
}
