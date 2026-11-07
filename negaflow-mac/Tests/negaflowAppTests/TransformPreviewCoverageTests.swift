import Chromabase
import CoreGraphics
import CoreImage
import XCTest
@testable import negaflowApp

/// 1.2.6 회귀: 소프트 프루프와 색역 경고를 켠 채 변환(원근)을 걸면 투명해야 할 색역 오버레이가
/// 흰 판이 되어 사진 전체를 덮었다. 변환 단계가 빈 곳을 흰색으로 구웠기 때문이다.
final class TransformPreviewCoverageTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    func testOverlaysStayTransparentAndThePhotoKeepsItsUncoveredAreaOutOfAnalysis() throws {
        var transform = ImageTransform(cropRect: SIMD4(0.2, 0, 0.6, 1), straightenAngle: -0.2)
        transform.perspective = PerspectiveCorrection(mode: .off, vertical: 22)
        let profile = try XCTUnwrap(CGColorSpace(name: CGColorSpace.genericRGBLinear)?.copyICCData() as Data?)
        let result = try DevelopFrameRenderer.render(makeSnapshot(
            input: try makeInput(),
            transform: transform,
            softProof: SoftProofSettings(isEnabled: true, colorSpace: .sRGB, iccProfileData: profile)
        ))

        let developed = rgba(result.developed)
        let width = result.developed.width, height = result.developed.height
        // 수직 보정은 위를 넓히고 아래 모서리를 비운다. 화면용 결과는 빈 곳이 투명이다.
        let bottomLeft = ((height - 1) * width) * 4
        let center = ((height / 2) * width + width / 2) * 4
        XCTAssertEqual(developed[bottomLeft + 3], 0, "화면용 사진의 빈 곳은 투명이어야 캔버스의 흰 바탕과 분석이 맞습니다")
        XCTAssertEqual(developed[center + 3], 255)

        for (name, overlay) in [("색역", result.destinationGamutOverlay), ("클리핑", result.clippingOverlay)] {
            let image = try XCTUnwrap(overlay, "\(name) 오버레이가 없습니다")
            let pixels = rgba(image)
            let opaque = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] == 255 }.count
            XCTAssertLessThan(Double(opaque), Double(pixels.count / 4) * 0.5,
                              "\(name) 오버레이가 사진을 덮는 불투명 판이 됐습니다")
            XCTAssertEqual(pixels[bottomLeft + 3], 0, "\(name) 오버레이가 빈 곳을 경고합니다")
        }

        // 필름스트립 썸네일은 바탕 없이 보이므로 빈 곳을 흰색으로 굽는다.
        let thumbnail = try XCTUnwrap(result.thumbnail)
        let thumbnailPixels = rgba(thumbnail)
        let corner = ((thumbnail.height - 1) * thumbnail.width) * 4
        XCTAssertEqual(Array(thumbnailPixels[corner..<corner + 4]), [255, 255, 255, 255])
    }

    private func makeSnapshot(
        input: CGImage,
        transform: ImageTransform,
        softProof: SoftProofSettings
    ) -> DevelopFrameSnapshot {
        var params = DevelopParameters()
        params.filmType = .colorPositive
        return DevelopFrameSnapshot(
            rawScanURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("negaflow-transform-coverage-\(UUID().uuidString).tiff"),
            preloadedRaw: input,
            cleanedRawURL: nil,
            filmType: .colorPositive,
            params: params,
            preset: nil,
            imageTransform: transform,
            cachedBase: nil,
            baseKey: FilmBaseCacheKey(
                filmType: .colorPositive,
                mode: params.baseEstimationMode,
                manualBaseRGB: nil,
                filmStockDminID: nil
            ),
            needsRawPreview: false,
            needsNeutralPreview: false,
            needsDebugPreviews: false,
            softProof: softProof,
            destinationGamutWarningEnabled: true,
            clippingOverlayEnabled: true,
            proxyMaxDimension: 240,
            needsThumbnail: true
        )
    }

    /// 가운데는 중간 회색, 오른쪽 위 작은 사각형만 하이라이트가 잘리도록 밝다.
    private func makeInput() throws -> CGImage {
        let size = CGRect(x: 0, y: 0, width: 240, height: 160)
        let gray = try XCTUnwrap(CIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1, colorSpace: linear))
        let hot = try XCTUnwrap(CIColor(red: 4, green: 4, blue: 4, alpha: 1, colorSpace: linear))
        let image = CIImage(color: hot).cropped(to: CGRect(x: 150, y: 100, width: 20, height: 20))
            .composited(over: CIImage(color: gray).cropped(to: size))
        let context = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        return try XCTUnwrap(context.createCGImage(image, from: size, format: .RGBAh, colorSpace: linear))
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }
}
