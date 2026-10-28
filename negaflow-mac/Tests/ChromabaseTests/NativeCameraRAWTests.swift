import CoreImage
import CryptoKit
import Foundation
import XCTest
@testable import Chromabase

final class NativeCameraRAWTests: XCTestCase {
    private let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!

    private func pixels(_ image: CIImage, width: Int, height: Int) -> [Float] {
        var values = [Float](repeating: 0, count: width * height * 4)
        let x = (image.extent.midX - CGFloat(width) * 0.5).rounded(.down)
        let y = (image.extent.midY - CGFloat(height) * 0.5).rounded(.down)
        let bounds = CGRect(x: x, y: y, width: CGFloat(width), height: CGFloat(height))
        ChromabaseEngine.sharedLinearRenderContext.render(image, toBitmap: &values, rowBytes: width * 16,
            bounds: bounds, format: .RGBAf, colorSpace: space)
        return values
    }

    func testInversionPrecedesCrossChannelMatrixIncludingProxy() throws {
        let matrix = try XCTUnwrap(CameraToWorkingMatrix([1.5, -0.3, -0.2, -0.1, 1.3, -0.2, -0.05, -0.2, 1.25]))
        let scene = SIMD3<Double>(0.20, 0.24, 0.30)
        let base = SIMD3<Double>(0.80, 0.55, 0.35)
        let density = SIMD3(0.60 + 0.62 * log10(scene.x / 0.18),
                            0.60 + 0.62 * log10(scene.y / 0.18),
                            0.60 + 0.62 * log10(scene.z / 0.18))
        let native = SyntheticScan.makeImage(width: 128, height: 128) { _, _ in
            SIMD3(base.x * pow(10, -density.x), base.y * pow(10, -density.y), base.z * pow(10, -density.z))
        }
        let input = NativeCameraRAW.tagged(native, matrix: matrix)
        let engine = ChromabaseEngine()
        let fb = FilmBase(rgb: base, source: .manual)
        var params = DevelopParameters()
        params.autoBalance = false
        let full = pixels(engine.developScanner(image: input, base: fb, params: params), width: 1, height: 1)
        let proxy = pixels(engine.developScannerPreview(image: input, base: fb, params: params, maxDimension: 64), width: 1, height: 1)
        let reference = sceneToOriginalResponse(scene)
        let expectedRGB = SIMD3(1.5 * reference.x - 0.3 * reference.y - 0.2 * reference.z,
            -0.1 * reference.x + 1.3 * reference.y - 0.2 * reference.z,
            -0.05 * reference.x - 0.2 * reference.y + 1.25 * reference.z)
        // Independent v4 scalar response followed by M; never M on negative samples.
        for (index, expected) in [expectedRGB.x, expectedRGB.y, expectedRGB.z].enumerated() {
            XCTAssertEqual(Double(full[index]), expected, accuracy: 0.00001)
            // Core Image preview resampling uses intermediate precision; < 0.1% here.
            XCTAssertEqual(Double(proxy[index]), expected, accuracy: 0.0003)
        }
    }

    private func sceneToOriginalResponse(_ scene: SIMD3<Double>) -> SIMD3<Double> {
        let response = NegativeInversion.response(for: .colorNegative)
        func value(_ e: Double) -> Double {
            let d = (0.60 + 0.62 * log10(e / 0.18)) / response.normalRange
            return pow(10, response.yCeil - response.amplitude * exp(-pow(response.rate * d, response.shape)))
        }
        return SIMD3(value(scene.x), value(scene.y), value(scene.z))
    }

    func testInvalidCameraMatricesAreRejectedIncludingDecodedJSON() throws {
        XCTAssertNil(CameraToWorkingMatrix([Double](repeating: 0, count: 9)))
        XCTAssertNil(CameraToWorkingMatrix([1, 0, 0]))
        XCTAssertThrowsError(try JSONDecoder().decode(CameraToWorkingMatrix.self,
            from: Data("{\"values\":[0,0,0,0,0,0,0,0,0]}".utf8)))
    }

    func testExplicitNativeBasePickDoesNotRequireOrangeChannelOrdering() throws {
        let base = SIMD3<Double>(0.30, 0.43, 0.21)
        let image = SyntheticScan.makeImage(width: 128, height: 128) { _, _ in base }
        let point = CGPoint(x: 0.5, y: 0.5)
        XCTAssertNil(FilmBasePicker.sample(in: image, atUnit: point))
        let picked = try XCTUnwrap(FilmBasePicker.sample(in: image, atUnit: point, cameraNative: true))
        for c in 0..<3 { XCTAssertEqual(picked[c], base[c], accuracy: 0.0003) }
        let black = SyntheticScan.makeImage(width: 128, height: 128) { _, _ in SIMD3(0.004, 0.003, 0.002) }
        XCTAssertNil(FilmBasePicker.sample(in: black, atUnit: point, cameraNative: true))
    }

    func testPublicRAWUsesNativeRGBAndIgnoresAsShotWhiteBalance() throws {
        guard NativeCameraRAW.isAvailable else {
            throw XCTSkip("Build scripts/build-libraw.sh and set NEGAFLOW_LIBRAW_LIBRARY to run actual RAW checks")
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "CameraNativeRaw", withExtension: "dng"))
        let original = try Data(contentsOf: url)
        XCTAssertEqual(SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined(),
            "1d77dcc6cdb839b10c1948f0b4471984ab48cf15e973fb77520584cee72b603e")
        let native = try XCTUnwrap(ImageLoader.loadImportedDecoded(url, rawRendering: .cameraNativeNegative))
        XCTAssertEqual(native.provenance.decoder, .libRaw)
        XCTAssertNotNil(native.provenance.cameraToWorking)
        XCTAssertTrue(native.image.extent.width > 1000)
        // This fixture is little-endian TIFF/DNG with AsShotNeutral (50728) in IFD0.
        var altered = original
        func uint16(_ offset: Int) -> Int { Int(altered[offset]) | Int(altered[offset + 1]) << 8 }
        func uint32(_ offset: Int) -> Int { uint16(offset) | uint16(offset + 2) << 16 }
        func write32(_ value: UInt32, at offset: Int) {
            for byte in 0..<4 { altered[offset + byte] = UInt8(truncatingIfNeeded: value >> (byte * 8)) }
        }
        XCTAssertEqual(Array(altered.prefix(2)), [0x49, 0x49])
        let ifd = uint32(4)
        var changed = false
        for index in 0..<uint16(ifd) {
            let entry = ifd + 2 + index * 12
            if uint16(entry) == 50728 {
                XCTAssertEqual(uint16(entry + 2), 5)
                XCTAssertEqual(uint32(entry + 4), 3)
                let offset = uint32(entry + 8)
                for channel in 0..<3 {
                    write32(UInt32(channel + 1), at: offset + channel * 8)
                    write32(4, at: offset + channel * 8 + 4)
                }
                changed = true
            }
        }
        XCTAssertTrue(changed)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("native-raw-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("wb-changed.dng")
        try altered.write(to: copy)
        let decoded = try XCTUnwrap(ImageLoader.loadImportedDecoded(copy, rawRendering: .cameraNativeNegative))
        XCTAssertEqual(native.provenance.cameraToWorking, decoded.provenance.cameraToWorking,
            "촬영 WB 메타데이터가 음화의 후단 색행렬을 바꾸면 안 됩니다")
        let a = pixels(native.image, width: 64, height: 64)
        let b = pixels(decoded.image, width: 64, height: 64)
        XCTAssertEqual(a, b, "촬영 WB 메타데이터가 음화 투과율을 바꾸면 안 됩니다")
        let output = folder.appendingPathComponent("developed.png")
        try ChromabaseEngine().developFile(input: url, output: output, format: .png,
            base: FilmBase(rgb: SIMD3(0.8, 0.55, 0.35), source: .manual), params: .init())
        let published = try XCTUnwrap(ImageLoader.loadImportedDecoded(output))
        XCTAssertEqual(published.image.extent.size, native.image.extent.size)
        let outputPixels = pixels(published.image, width: 32, height: 32)
        XCTAssertTrue(outputPixels.allSatisfy(\.isFinite))
        XCTAssertTrue(outputPixels.enumerated().contains { $0.offset % 4 != 3 && $0.element > 0.01 })
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    /// 프리뷰 크기 요청은 원본 크기 RGBA16 을 만들지 않고 목표 크기로 줄인 화상을 돌려준다.
    /// 크기가 다른 두 번째 요청은 캐시한 정착 크기 마스터에서 파생되며 행렬 태그를 유지한다.
    func testPreviewDecodeReturnsTargetSizeAndKeepsMatrixAcrossSizes() throws {
        guard NativeCameraRAW.isAvailable else {
            throw XCTSkip("Build scripts/build-libraw.sh and set NEGAFLOW_LIBRAW_LIBRARY to run actual RAW checks")
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "CameraNativeRaw", withExtension: "dng"))
        let full = try XCTUnwrap(NativeCameraRAW.decode(url, scaleFactor: nil))
        let width = full.image.extent.width, height = full.image.extent.height
        let fullMatrix = try XCTUnwrap(full.provenance.cameraToWorking)

        for scale in [CGFloat(0.5), 0.25, 0.1] {
            let preview = try XCTUnwrap(NativeCameraRAW.decode(url, scaleFactor: scale))
            let expected = NativeCameraRAW.reducedSize(width: Int(width), height: Int(height), scale: scale)
            XCTAssertEqual(Int(preview.image.extent.width), expected.width, "scale \(scale)")
            XCTAssertEqual(Int(preview.image.extent.height), expected.height, "scale \(scale)")
            XCTAssertEqual(preview.provenance.rawScaleFactor, Double(scale))
            XCTAssertEqual(preview.provenance.cameraToWorking, fullMatrix)
            XCTAssertEqual(NativeCameraRAW.matrix(in: preview.image), fullMatrix)
        }

        // 축소 결과의 평균 밝기는 원본 평균과 같아야 한다(면적 평균).
        let fullMean = meanChannels(full.image, size: 16)
        let previewMean = meanChannels(try XCTUnwrap(NativeCameraRAW.decode(url, scaleFactor: 0.25)).image, size: 16)
        for c in 0..<3 { XCTAssertEqual(previewMean[c], fullMean[c], accuracy: max(0.002, fullMean[c] * 0.03)) }
    }

    func testPreviewMasterLongSideMatchesSettledProxyLimit() {
        XCTAssertEqual(NativeCameraRAW.previewMasterLongSide, 3600)
    }

    private func meanChannels(_ image: CIImage, size: Int) -> [Float] {
        let averaged = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
        var value = [Float](repeating: 0, count: 4)
        ChromabaseEngine.sharedLinearRenderContext.render(averaged, toBitmap: &value, rowBytes: 16,
            bounds: CGRect(x: averaged.extent.minX, y: averaged.extent.minY, width: 1, height: 1),
            format: .RGBAf, colorSpace: space)
        return Array(value.prefix(3))
    }
}
