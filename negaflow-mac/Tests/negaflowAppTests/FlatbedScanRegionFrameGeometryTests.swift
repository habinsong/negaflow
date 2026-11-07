import Chromabase
import CoreGraphics
import XCTest
@testable import negaflowApp

/// 각도가 들어간 프리뷰에서 프레임을 화면·base 사이로 오가도 크기가 변하지 않아야 한다.
/// 예전에는 경계 상자를 오가서 프레임을 누를 때마다 커졌다(QA: Epson V750, 중형 필름).
final class FlatbedScanRegionFrameGeometryTests: XCTestCase {
    private let baseSize = CGSize(width: 2400, height: 3600)
    private let imageFrame = CGRect(x: 40, y: 30, width: 520, height: 780)

    func testDisplayRectSurvivesRepeatedRoundTripsOnAStraightenedPreview() {
        let transforms = [
            ImageTransform(straightenAngle: 2.5),
            ImageTransform(flipHorizontal: true, straightenAngle: -3.7),
            ImageTransform(rotation: .deg90, straightenAngle: 1.2),
            ImageTransform(rotation: .deg270, flipVertical: true, straightenAngle: 4.4),
        ]
        for transform in transforms {
            let frame = displayedFrame(for: transform)
            let drawn = FlatbedRegionScreenShape(
                center: CGPoint(x: frame.midX - 30, y: frame.midY + 20),
                size: CGSize(width: 160, height: 110),
                angle: 0
            )
            let angle = FlatbedScanRegionFrameGeometry.regionAngle(matching: transform)
            var rect = FlatbedScanRegionFrameGeometry.unitRect(
                for: drawn, transform: transform, baseSize: baseSize, imageFrame: frame
            )
            for _ in 0..<25 {
                let shown = FlatbedScanRegionFrameGeometry.screenShape(
                    unitRect: rect,
                    straightenAngle: angle,
                    transform: transform,
                    baseSize: baseSize,
                    imageFrame: frame
                )
                XCTAssertEqual(shown.size.width, drawn.size.width, accuracy: 1e-6, "\(transform)")
                XCTAssertEqual(shown.size.height, drawn.size.height, accuracy: 1e-6, "\(transform)")
                XCTAssertEqual(shown.center.x, drawn.center.x, accuracy: 1e-6, "\(transform)")
                XCTAssertEqual(shown.center.y, drawn.center.y, accuracy: 1e-6, "\(transform)")
                XCTAssertEqual(Double(shown.angle), 0, accuracy: 1e-9, "\(transform)")
                rect = FlatbedScanRegionFrameGeometry.unitRect(
                    for: shown, transform: transform, baseSize: baseSize, imageFrame: frame
                )
            }
        }
    }

    /// 검출이 잰 기울기를 가진 프레임은 펴지 않은 프리뷰에서 그만큼 기운 사각형으로 보이고,
    /// 화면에서 옮겨도 각도와 크기가 그대로다.
    func testDetectedTiltIsDrawnAsATiltedFrameAndMovesWithoutGrowing() {
        let transform = ImageTransform.identity
        let frame = imageFrame
        let rect = CGRect(x: 0.2, y: 0.25, width: 0.3, height: 0.18)
        let shape = FlatbedScanRegionFrameGeometry.screenShape(
            unitRect: rect,
            straightenAngle: 3,
            transform: transform,
            baseSize: baseSize,
            imageFrame: frame
        )
        XCTAssertEqual(Double(shape.angle) * 180 / .pi, -3, accuracy: 1e-9)

        var moved = shape
        moved.center.x += 12
        moved.center.y -= 7
        let movedRect = FlatbedScanRegionFrameGeometry.unitRect(
            for: moved, transform: transform, baseSize: baseSize, imageFrame: frame
        )
        XCTAssertEqual(movedRect.width, rect.width, accuracy: 1e-9)
        XCTAssertEqual(movedRect.height, rect.height, accuracy: 1e-9)
        XCTAssertEqual(movedRect.minX - rect.minX, 12 / frame.width, accuracy: 1e-9)
        XCTAssertEqual(movedRect.minY - rect.minY, -7 / frame.height, accuracy: 1e-9)
    }

    func testFrameLocalRectInvertsBackToTheSameBounds() {
        let rect = CGRect(x: 0.31, y: 0.12, width: 0.22, height: 0.4)
        for angle in [-6.0, -0.4, 0, 2.2, 9.5] {
            let local = FlatbedScanRegionFrameGeometry.frameLocalRect(
                unitRect: rect, straightenAngle: angle, localAngle: angle, baseSize: baseSize
            )
            let back = FlatbedScanRegionFrameGeometry.unitRect(
                fromFrameLocal: local, localAngle: angle, baseSize: baseSize
            )
            XCTAssertEqual(back.minX, rect.minX, accuracy: 1e-9)
            XCTAssertEqual(back.minY, rect.minY, accuracy: 1e-9)
            XCTAssertEqual(back.width, rect.width, accuracy: 1e-9)
            XCTAssertEqual(back.height, rect.height, accuracy: 1e-9)
        }
    }

    /// 화면에 그려지는 사진의 비율은 변형 뒤 크기를 따른다(캔버스와 같은 맞춤).
    private func displayedFrame(for transform: ImageTransform) -> CGRect {
        var width = Double(baseSize.width), height = Double(baseSize.height)
        if transform.rotation == .deg90 || transform.rotation == .deg270 { swap(&width, &height) }
        let theta = transform.straightenAngle * .pi / 180
        let c = abs(cos(theta)), s = abs(sin(theta))
        let inscribedHeight = min(width * height / (width * c + height * s),
                                  height * height / (width * s + height * c))
        let inscribedWidth = width / height * inscribedHeight
        let scale = min(Double(imageFrame.width) / inscribedWidth,
                        Double(imageFrame.height) / inscribedHeight)
        return CGRect(
            x: imageFrame.minX,
            y: imageFrame.minY,
            width: inscribedWidth * scale,
            height: inscribedHeight * scale
        )
    }
}
