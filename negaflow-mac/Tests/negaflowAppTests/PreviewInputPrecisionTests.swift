import Chromabase
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import negaflowApp

/// 프리뷰 입력을 프레임에 굳혀 두는 경로가 원본 정밀도를 깎지 않는지 지킨다.
///
/// 굳히는 조건을 넓히면서(작은 원본도 굳긴다) 16bit 원본이 8bit 로 내려앉을 여지가 생겼다.
/// ICC 태그가 붙은 16bit 스캔(VueScan/SilverFast 출력)이 정확히 그 경우다.
@MainActor
final class PreviewInputPrecisionTests: XCTestCase {

    func testTaggedSixteenBitSourceKeepsPrecisionThroughPreviewCache() throws {
        let url = try Self.writeGradientTIFF(
            width: 1_200, height: 800,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        model.activeWorkspaceModule = .develop
        model.canvasDisplayTargetPixels = 1_024
        let frame = ScanFrame(
            scanIndex: 1, rawScanURL: url, filmType: .colorNegative, sourceKind: .importedFile
        )
        model.frames = [frame]

        let baseKey = FilmBaseCacheKey(
            filmType: frame.filmType,
            mode: frame.params.baseEstimationMode,
            manualBaseRGB: frame.params.manualBaseRGB,
            filmStockDminID: frame.params.filmStockDminID,
            lightSourceProfileID: frame.params.lightSourceProfileID
        )
        let snapshot = model.makeSnapshot(
            for: frame, baseKey: baseKey,
            needsRawPreview: false, needsNeutralPreview: false, needsDebugPreviews: false,
            needsThumbnail: false, proxyMaxDimension: 1_024
        )
        let result = try DevelopFrameRenderer.render(snapshot)
        let cached = try XCTUnwrap(
            result.previewRaw,
            "작은 원본도 굳혀 둬야 슬라이더마다 원본을 다시 디코딩하지 않는다"
        )
        XCTAssertGreaterThanOrEqual(
            cached.image.bitsPerComponent, 16,
            "굳혀 둔 프리뷰 입력이 8bit 로 내려앉으면 16bit 원본의 계조가 그 자리에서 사라진다"
        )
    }

    /// 무프로필 16bit(스캐너 raw)는 linear 로 해석되며 정밀도가 유지된다 — 기존 계약.
    func testUntaggedSixteenBitScannerSourceKeepsPrecision() throws {
        let url = try Self.writeGradientTIFF(
            width: 1_200, height: 800,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let frame = ScanFrame(
            scanIndex: 1, rawScanURL: url, filmType: .colorNegative, sourceKind: .scannerTIFF
        )
        model.frames = [frame]
        let baseKey = FilmBaseCacheKey(
            filmType: frame.filmType,
            mode: frame.params.baseEstimationMode,
            manualBaseRGB: frame.params.manualBaseRGB,
            filmStockDminID: frame.params.filmStockDminID,
            lightSourceProfileID: frame.params.lightSourceProfileID
        )
        let snapshot = model.makeSnapshot(
            for: frame, baseKey: baseKey,
            needsRawPreview: false, needsNeutralPreview: false, needsDebugPreviews: false,
            needsThumbnail: false, proxyMaxDimension: 1_024
        )
        let result = try DevelopFrameRenderer.render(snapshot)
        let cached = try XCTUnwrap(result.previewRaw)
        XCTAssertGreaterThanOrEqual(cached.image.bitsPerComponent, 16)
    }

    /// sRGB 로 굳히는 8bit 원본(포지티브)은 굳혀 둘 때도 8bit 다 — 부풀려 봐야 메모리만 두 배로 먹는다.
    func testEightBitSourceKeptInSRGBIsNotInflated() throws {
        let cached = try Self.cachedPreview(filmType: .colorPositive)
        XCTAssertEqual(cached.image.bitsPerComponent, 8)
        XCTAssertFalse(cached.usesLinearSRGB)
    }

    /// 네거티브는 반전이 linear 도메인에서 돈다. 8bit JPEG 이라도 linear 로 굳힐 때 8bit 면
    /// 암부 계조가 뭉개져 반전 결과가 계단으로 깨진다 — 16bit 로 굳혀야 한다.
    func testEightBitNegativeSourceIsStoredLinearAtSixteenBits() throws {
        let cached = try Self.cachedPreview(filmType: .colorNegative)
        XCTAssertTrue(cached.usesLinearSRGB)
        XCTAssertGreaterThanOrEqual(cached.image.bitsPerComponent, 16)
    }

    /// 네거티브 카메라 RAW 프리뷰 마스터 크기는 정착 프리뷰 상한과 같아야 정착 요청이 캐시를 쓴다.
    func testNativeRAWPreviewMasterMatchesSettledProxyLimit() {
        XCTAssertEqual(NativeCameraRAW.previewMasterLongSide, DevelopFrameRenderer.fullMaxDimension)
    }

    func testPreviewRawFormatTable() {
        XCTAssertEqual(DevelopFrameRenderer.previewRawFormat(sourceBitsPerComponent: 8, usesLinearSRGB: false), .RGBA8)
        XCTAssertEqual(DevelopFrameRenderer.previewRawFormat(sourceBitsPerComponent: 8, usesLinearSRGB: true), .RGBA16)
        XCTAssertEqual(DevelopFrameRenderer.previewRawFormat(sourceBitsPerComponent: 16, usesLinearSRGB: false), .RGBA16)
        XCTAssertEqual(DevelopFrameRenderer.previewRawFormat(sourceBitsPerComponent: 16, usesLinearSRGB: true), .RGBA16)
    }

    func testLinearMaterializationDoesNotInspectTheOriginalForItsDepth() throws {
        let image = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 24))
        for linear in [true, false] {
            var sourceReads = 0
            func inspectDepth() -> Int { sourceReads += 1; return 16 }
            let proxy = try XCTUnwrap(DevelopFrameRenderer.materializedPreviewRaw(image,
                usesLinearSRGB: linear, sourceBitsPerComponent: inspectDepth(),
                context: DevelopFrameRenderer.linearRawProxyContext))
            XCTAssertEqual(sourceReads, linear ? 0 : 1)
            XCTAssertEqual(proxy.image.bitsPerComponent, 16)
        }
    }

    /// 어두운 8bit 경사를 linear 로 굳혀도 sRGB 코드 단계가 살아남는다.
    func testDarkEightBitRampKeepsItsLevelsWhenStoredLinear() throws {
        let width = 256
        var pixels = [UInt8](repeating: 255, count: width * 4 * 4)
        for y in 0..<4 {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let code = UInt8(min(x, 50))
                pixels[i] = code; pixels[i + 1] = code; pixels[i + 2] = code
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let source = try XCTUnwrap(CGImage(
            width: width, height: 4, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let stored = try XCTUnwrap(DevelopFrameRenderer.materializedPreviewRaw(
            CIImage(cgImage: source), usesLinearSRGB: true, sourceBitsPerComponent: 8,
            context: DevelopFrameRenderer.linearRawProxyContext
        ))
        // 저장한 linear 값을 다시 sRGB 코드로 읽어 서로 다른 단계가 몇 개 남는지 센다.
        let back = CIImage(cgImage: stored.image, options: [.colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!])
        var out = [UInt8](repeating: 0, count: width * 4)
        DevelopFrameRenderer.srgbRawProxyContext.render(
            back, toBitmap: &out, rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: 1),
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        let levels = Set((0...50).map { out[$0 * 4 + 1] })
        XCTAssertGreaterThanOrEqual(levels.count, 49, "sRGB 코드 0~50 이 \(levels.count)단계로 뭉개졌다")
    }

    private static func cachedPreview(filmType: FilmType) throws -> DevelopFramePreviewRaw {
        let url = try writeEightBitJPEG(width: 1_200, height: 800)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let frame = ScanFrame(
            scanIndex: 1, rawScanURL: url, filmType: filmType, sourceKind: .importedFile
        )
        model.frames = [frame]
        let baseKey = FilmBaseCacheKey(
            filmType: frame.filmType,
            mode: frame.params.baseEstimationMode,
            manualBaseRGB: frame.params.manualBaseRGB,
            filmStockDminID: frame.params.filmStockDminID,
            lightSourceProfileID: frame.params.lightSourceProfileID
        )
        let snapshot = model.makeSnapshot(
            for: frame, baseKey: baseKey,
            needsRawPreview: false, needsNeutralPreview: false, needsDebugPreviews: false,
            needsThumbnail: false, proxyMaxDimension: 1_024
        )
        let result = try DevelopFrameRenderer.render(snapshot)
        return try XCTUnwrap(result.previewRaw)
    }

    private static func writeEightBitJPEG(width: Int, height: Int) throws -> URL {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let t = Double(x) / Double(width - 1)
                let i = (y * width + x) * 4
                pixels[i] = UInt8(min(255, (0.30 + 0.5 * t) * 255))
                pixels[i + 1] = UInt8(min(255, (0.24 + 0.4 * t) * 255))
                pixels[i + 2] = UInt8(min(255, (0.18 + 0.3 * t) * 255))
            }
        }
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        guard let cg = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else { throw CocoaError(.fileWriteUnknown) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-precision-\(UUID().uuidString).jpg")
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    /// 매끈한 저대비 그라디언트 — 8bit 로 내려앉으면 계단이 생긴다(실사진 미사용).
    private static func writeGradientTIFF(
        width: Int, height: Int, colorSpace: CGColorSpace
    ) throws -> URL {
        var pixels = [UInt16](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                // 0.40~0.42 사이만 쓰는 아주 얕은 경사: 8bit 로는 5단계도 안 나온다.
                let t = Double(x) / Double(width - 1)
                let v = 0.40 + 0.02 * t
                let i = (y * width + x) * 4
                pixels[i] = UInt16(v * 65_535)
                pixels[i + 1] = UInt16(v * 0.78 * 65_535)
                pixels[i + 2] = UInt16(v * 0.58 * 65_535)
                pixels[i + 3] = UInt16.max
            }
        }
        let data = Data(bytes: pixels, count: pixels.count * MemoryLayout<UInt16>.size)
        let provider = CGDataProvider(data: data as CFData)!
        guard let cg = CGImage(
            width: width, height: height,
            bitsPerComponent: 16, bitsPerPixel: 64,
            bytesPerRow: width * 4 * MemoryLayout<UInt16>.size,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else { throw CocoaError(.fileWriteUnknown) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-precision-\(UUID().uuidString).tiff")
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.tiff.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }
}
