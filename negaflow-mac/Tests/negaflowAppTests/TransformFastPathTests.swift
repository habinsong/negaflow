import XCTest
import CoreGraphics
import CoreImage
import Chromabase
@testable import negaflowApp

/// Angle(수평 보정) 슬라이더 라이브 반응 검증 — 틱마다 태스크를 쌓지 않고 코얼레싱 루프가
/// 최신 각도만 렌더하며, 정착 후에는 풀해상도 결과가 남아야 한다.
@MainActor
final class TransformFastPathTests: XCTestCase {
    func testRapidStraightenDragCoalescesAndSettlesAtFullResolution() async throws {
        let model = AppModel()
        let frame = Self.makeFrame()
        // 변형-전 발색 base(풀해상도 프록시에 해당) — 2000px 는 인터랙티브 폴백(1600px)보다 커서
        // 인터랙티브/정착 결과를 크기로 구분할 수 있다.
        frame.cachedDevelopedBase = try XCTUnwrap(Self.makeCGImage(width: 2000, height: 1400))
        model.frames = [frame]

        // 드래그 시뮬레이션: 빠르게 연속 호출(코얼레싱 루프는 하나만 떠야 한다).
        for step in 1...30 {
            model.setStraighten(frame, angle: Double(step) * 0.1)
        }
        XCTAssertEqual(frame.imageTransform.straightenAngle, 3.0, accuracy: 1e-9)
        XCTAssertNotNil(frame.transformTask, "코얼레싱 루프가 떠 있어야 한다")

        // 정착까지 대기(인터랙티브 → settle 윈도 → 풀해상도).
        try await waitUntil("transform task 종료", timeout: 8) { frame.transformTask == nil }

        let developed = try XCTUnwrap(frame.developedImage)
        // straighten 은 회전 후 같은 종횡비 최대 내접 사각형으로 크롭한다 — 3° 기준 기대 크기.
        let theta = 3.0 * Double.pi / 180
        let w = 2000.0, h = 1400.0
        let c = abs(cos(theta)), s = abs(sin(theta))
        let hp = min(w * h / (w * c + h * s), h * h / (w * s + h * c))
        let wp = (w / h) * hp
        // 정착 결과는 풀해상도(내접 크롭 ≈ 1902×1331) — 인터랙티브(≤1600)가 아니어야 한다.
        XCTAssertEqual(Double(developed.size.width), wp, accuracy: 3)
        XCTAssertEqual(Double(developed.size.height), hp, accuracy: 3)
        XCTAssertGreaterThan(developed.size.width, 1600)
        // 레이아웃 기준 크기는 정착 결과로 권위 갱신된다.
        let displaySize = try XCTUnwrap(frame.displayPixelSize)
        XCTAssertEqual(displaySize.width, developed.size.width, accuracy: 0.5)
        XCTAssertEqual(displaySize.height, developed.size.height, accuracy: 0.5)
    }

    func testStraightenPreservesAspectSoLayoutStaysStable() async throws {
        // Angle 조절 중 종횡비가 유지되어야 캔버스 fitted frame 이 흔들리지 않는다
        // (applyStraighten 은 입력과 같은 종횡비의 내접 사각형으로 크롭).
        let model = AppModel()
        let frame = Self.makeFrame()
        frame.cachedDevelopedBase = try XCTUnwrap(Self.makeCGImage(width: 1800, height: 1200))
        model.frames = [frame]

        model.setStraighten(frame, angle: 5)
        try await waitUntil("transform task 종료", timeout: 8) { frame.transformTask == nil }

        let developed = try XCTUnwrap(frame.developedImage)
        let aspect = developed.size.width / developed.size.height
        XCTAssertEqual(aspect, 1800.0 / 1200.0, accuracy: 0.01)
    }

    func testRotate90SettlesWithSwappedFullResolutionDimensions() async throws {
        let model = AppModel()
        let frame = Self.makeFrame()
        frame.cachedDevelopedBase = try XCTUnwrap(Self.makeCGImage(width: 2000, height: 1400))
        model.frames = [frame]

        model.rotate(frame, clockwise: true)
        try await waitUntil("transform task 종료", timeout: 8) { frame.transformTask == nil }

        let developed = try XCTUnwrap(frame.developedImage)
        XCTAssertEqual(developed.size.width, 1400, accuracy: 1)
        XCTAssertEqual(developed.size.height, 2000, accuracy: 1)
    }

    func testTransformFastPathPreservesSyntheticPrinterICCProfileSHA256() async throws {
        let profile = try ICCOutputProfileTestFixture.snapshot()
        let colorSpace = try XCTUnwrap(profile.validatedColorSpace())
        let model = AppModel()
        let frame = Self.makeFrame()
        frame.cachedDevelopedBase = try XCTUnwrap(
            Self.makeCGImage(width: 64, height: 48, colorSpace: colorSpace)
        )
        model.frames = [frame]

        model.rotate(frame, clockwise: true)
        try await waitUntil("transform task 종료", timeout: 8) { frame.transformTask == nil }

        let developed = try XCTUnwrap(frame.developedImage)
        let transformed = try XCTUnwrap(
            developed.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        let embeddedProfile = try XCTUnwrap(transformed.colorSpace?.copyICCData() as Data?)
        XCTAssertEqual(
            ICCOutputProfileSnapshot.sha256(embeddedProfile),
            ICCOutputProfileTestFixture.expectedSHA256
        )
    }

    func testHorizontalFlipFlipsCurrentCropInsteadOfSelectingOppositeSourceArea() async throws {
        let model = AppModel()
        let source = try XCTUnwrap(Self.makePatternCGImage(width: 8, height: 6))
        let frame = Self.makeFrame()
        let crop = SIMD4<Double>(0.125, 1.0 / 6.0, 0.5, 0.5)
        frame.imageTransform = ImageTransform(cropRect: crop)
        frame.cachedDevelopedBase = source
        model.frames = [frame]

        let cropped = ImageTransformStage.apply(
            to: CIImage(cgImage: source),
            transform: ImageTransform(cropRect: crop)
        )
        let expected = ImageTransformStage.apply(
            to: cropped,
            transform: ImageTransform(flipHorizontal: true)
        )

        model.flipHorizontally(frame)
        try await waitUntil("transform task 종료", timeout: 8) { frame.transformTask == nil }

        let actual = ImageTransformStage.apply(
            to: CIImage(cgImage: source),
            transform: frame.imageTransform
        )
        XCTAssertEqual(actual.extent, expected.extent)
        XCTAssertEqual(Self.rgbaBytes(actual), Self.rgbaBytes(expected))
    }

    func testVerticalFlipFlipsCurrentCropInsteadOfSelectingOppositeSourceArea() async throws {
        let model = AppModel()
        let source = try XCTUnwrap(Self.makePatternCGImage(width: 8, height: 6))
        let frame = Self.makeFrame()
        let crop = SIMD4<Double>(0.125, 1.0 / 6.0, 0.5, 0.5)
        frame.imageTransform = ImageTransform(cropRect: crop)
        frame.cachedDevelopedBase = source
        model.frames = [frame]

        let cropped = ImageTransformStage.apply(
            to: CIImage(cgImage: source),
            transform: ImageTransform(cropRect: crop)
        )
        let expected = ImageTransformStage.apply(
            to: cropped,
            transform: ImageTransform(flipVertical: true)
        )

        model.flipVertically(frame)
        try await waitUntil("transform task 종료", timeout: 8) { frame.transformTask == nil }

        let actual = ImageTransformStage.apply(
            to: CIImage(cgImage: source),
            transform: frame.imageTransform
        )
        XCTAssertEqual(actual.extent, expected.extent)
        XCTAssertEqual(Self.rgbaBytes(actual), Self.rgbaBytes(expected))
    }

    func testClockwiseRotationRotatesCurrentCropInsteadOfSelectingPreviousScreenArea() async throws {
        try await assertRotationPreservesCurrentCrop(clockwise: true)
    }

    func testCounterClockwiseRotationRotatesCurrentCropInsteadOfSelectingPreviousScreenArea() async throws {
        try await assertRotationPreservesCurrentCrop(clockwise: false)
    }

    // MARK: helpers

    private static func makeCGImage(
        width: Int,
        height: Int,
        colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    ) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(CGColor(red: 0.5, green: 0.4, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    private static func makePatternCGImage(width: Int, height: Int) -> CGImage? {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                bytes[offset] = UInt8(20 + x * 20)
                bytes[offset + 1] = UInt8(30 + y * 30)
                bytes[offset + 2] = UInt8(10 + x * 7 + y * 5)
            }
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private func assertRotationPreservesCurrentCrop(
        clockwise: Bool,
        line: UInt = #line
    ) async throws {
        let model = AppModel()
        let source = try XCTUnwrap(Self.makePatternCGImage(width: 8, height: 6))
        let frame = Self.makeFrame()
        let crop = SIMD4<Double>(0.125, 1.0 / 6.0, 0.5, 0.5)
        frame.imageTransform = ImageTransform(cropRect: crop, cropAspect: 4.0 / 3.0)
        frame.cachedDevelopedBase = source
        model.frames = [frame]

        let cropped = ImageTransformStage.apply(
            to: CIImage(cgImage: source),
            transform: ImageTransform(cropRect: crop)
        )
        let expected = ImageTransformStage.apply(
            to: cropped,
            transform: ImageTransform(rotation: clockwise ? .deg90 : .deg270)
        )

        model.rotate(frame, clockwise: clockwise)
        try await waitUntil("transform task 종료", timeout: 8) { frame.transformTask == nil }

        let actual = ImageTransformStage.apply(
            to: CIImage(cgImage: source),
            transform: frame.imageTransform
        )
        let cropAspect = try XCTUnwrap(frame.imageTransform.cropAspect)
        XCTAssertEqual(cropAspect, 3.0 / 4.0, accuracy: 1e-12, line: line)
        XCTAssertEqual(actual.extent, expected.extent, line: line)
        XCTAssertEqual(
            Self.rgbaBytes(actual),
            Self.rgbaBytes(expected),
            clockwise ? "시계 방향 회전이 현재 크롭을 유지해야 한다" : "반시계 방향 회전이 현재 크롭을 유지해야 한다",
            line: line
        )
    }

    // MARK: 회전 뒤 뒤집기는 화면에 보이는 축을 따른다

    /// 변형 순서가 flip → rotate 라서, 소스 축으로 토글하면 90/270 에서 좌우 뒤집기가 상하로 나온다.
    /// 사용자가 누르는 축은 화면 축이므로 회전 상태와 무관하게 보이는 대로 뒤집혀야 한다.
    private func assertFlipFollowsScreen(rotation: ImageRotation,
                                         horizontal: Bool,
                                         line: UInt = #line) async throws {
        let model = AppModel()
        let source = try XCTUnwrap(Self.makePatternCGImage(width: 8, height: 6))
        let frame = Self.makeFrame()
        frame.imageTransform = ImageTransform(rotation: rotation)
        frame.cachedDevelopedBase = source
        model.frames = [frame]

        // 기대 = "지금 화면에 보이는 그림"을 그 축으로 뒤집은 결과.
        let onScreen = ImageTransformStage.apply(
            to: CIImage(cgImage: source),
            transform: ImageTransform(rotation: rotation)
        )
        let expected = ImageTransformStage.apply(
            to: onScreen,
            transform: horizontal
                ? ImageTransform(flipHorizontal: true)
                : ImageTransform(flipVertical: true)
        )

        if horizontal { model.flipHorizontally(frame) } else { model.flipVertically(frame) }
        try await waitUntil("transform task 종료", timeout: 8) { frame.transformTask == nil }

        let actual = ImageTransformStage.apply(
            to: CIImage(cgImage: source),
            transform: frame.imageTransform
        )
        XCTAssertEqual(actual.extent, expected.extent, line: line)
        XCTAssertEqual(Self.rgbaBytes(actual), Self.rgbaBytes(expected),
                       "\(rotation) 회전에서 \(horizontal ? "좌우" : "상하") 뒤집기가 화면 기준이어야 한다",
                       line: line)
    }

    func testHorizontalFlipFollowsScreenAfterQuarterTurns() async throws {
        for rotation in [ImageRotation.deg0, .deg90, .deg180, .deg270] {
            try await assertFlipFollowsScreen(rotation: rotation, horizontal: true)
        }
    }

    func testVerticalFlipFollowsScreenAfterQuarterTurns() async throws {
        for rotation in [ImageRotation.deg0, .deg90, .deg180, .deg270] {
            try await assertFlipFollowsScreen(rotation: rotation, horizontal: false)
        }
    }

    private static func rgbaBytes(_ image: CIImage) -> [UInt8] {
        let extent = image.extent.integral
        var bytes = [UInt8](repeating: 0, count: Int(extent.width * extent.height) * 4)
        CIContext(options: [.useSoftwareRenderer: true]).render(
            image,
            toBitmap: &bytes,
            rowBytes: Int(extent.width) * 4,
            bounds: extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        return bytes
    }

    private static func makeFrame() -> ScanFrame {
        ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-transform-fastpath-test-\(UUID().uuidString).tiff"),
            filmType: .colorNegative
        )
    }
}
