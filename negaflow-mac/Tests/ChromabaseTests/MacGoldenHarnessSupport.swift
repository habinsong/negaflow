import CryptoKit
import CoreGraphics
import CoreImage
import Foundation

/// Windows 포팅본 대조용 macOS 기준값(golden) 하네스가 공유하는 최소 도구.
///
/// 일반 `swift test` 실행에서는 하네스 전체가 skip 되므로 여기의 코드도 돌지 않는다.
/// 실제 스캔 파일을 읽는 opt-in 진단 경로이며, 산출물 경로는 환경변수로만 지정한다.
enum MacGoldenHarness {
    /// 산출물 디렉터리. 지정되지 않으면 하네스가 skip 된다.
    static func outputDirectory(_ key: String = "NEGAFLOW_GOLDEN_DIR") -> URL? {
        guard let raw = ProcessInfo.processInfo.environment[key], !raw.isEmpty else { return nil }
        let url = URL(fileURLWithPath: raw, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func inputURL(_ key: String) -> URL? {
        guard let raw = ProcessInfo.processInfo.environment[key], !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: raw)
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func byteCount(of url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return values.fileSize ?? 0
    }

    /// 사람이 읽고 diff 하기 쉬운 정렬된 JSON 으로 기록한다.
    static func writeJSON(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: .atomic)
    }

    static func makeLinearImage(
        pixels: [Float],
        width: Int,
        height: Int,
        colorSpace: CGColorSpace
    ) -> CIImage {
        precondition(pixels.count == width * height * 4)
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(
            bitmapData: data,
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: colorSpace
        )
    }

    static func renderLinearRGBAf(
        _ image: CIImage,
        width: Int,
        height: Int,
        context: CIContext,
        colorSpace: CGColorSpace
    ) -> [Float] {
        var bitmap = [Float](repeating: 0, count: width * height * 4)
        bitmap.withUnsafeMutableBytes { buffer in
            context.render(
                image,
                toBitmap: buffer.baseAddress!,
                rowBytes: width * 4 * MemoryLayout<Float>.size,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBAf,
                colorSpace: colorSpace
            )
        }
        return bitmap
    }

    static func writeFloat32(_ bitmap: [Float], to url: URL) throws {
        try bitmap.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: url, options: .atomic)
    }
}
