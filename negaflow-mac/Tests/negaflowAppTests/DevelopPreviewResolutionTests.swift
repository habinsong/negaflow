import XCTest
@testable import negaflowApp

/// 인터랙티브 프리뷰 해상도 적응 + 캔버스 레이아웃 종횡비 안정화 검증.
/// 목표: 슬라이더 편집 중 프리뷰가 화면 표시 픽셀보다 작게 렌더되어 "해상도가 내려가며
/// 떨리는" 현상이 생기지 않아야 한다(업스케일 금지 + 서브픽셀 레이아웃 이동 금지).
final class DevelopPreviewResolutionTests: XCTestCase {
    // MARK: 적응형 인터랙티브 프록시 치수

    func testUnknownDisplayTargetFallsBackToDefault() {
        XCTAssertEqual(
            DevelopFrameRenderer.interactiveProxyDimension(displayTargetPixels: 0),
            DevelopFrameRenderer.interactiveMaxDimension
        )
        XCTAssertEqual(
            DevelopFrameRenderer.interactiveProxyDimension(displayTargetPixels: -100),
            DevelopFrameRenderer.interactiveMaxDimension
        )
    }

    func testProxyDimensionNeverBelowDisplayTarget() {
        // 어떤 표시 크기에서도 프록시 ≥ 표시 픽셀(상한 이내) — 업스케일 블러가 없어야 한다.
        for target in stride(from: 200.0, through: 3600.0, by: 37.0) {
            let dim = DevelopFrameRenderer.interactiveProxyDimension(displayTargetPixels: target)
            XCTAssertGreaterThanOrEqual(dim, CGFloat(target), "target \(target)px 보다 작게 렌더하면 업스케일 블러 발생")
        }
    }

    func testProxyDimensionQuantizedToStep() {
        let step = DevelopFrameRenderer.interactiveDimensionStep
        // 2700px 필요(예: 1350pt 캔버스 × 2x Retina) → 2816(= 11×256)으로 올림.
        XCTAssertEqual(DevelopFrameRenderer.interactiveProxyDimension(displayTargetPixels: 2700), 2816)
        // 스텝 경계값은 그대로.
        XCTAssertEqual(DevelopFrameRenderer.interactiveProxyDimension(displayTargetPixels: 2816), 2816)
        // 양자화는 항상 스텝 배수(캐시 재사용 안정성).
        for target in stride(from: 1100.0, through: 3400.0, by: 111.0) {
            let dim = DevelopFrameRenderer.interactiveProxyDimension(displayTargetPixels: target)
            XCTAssertEqual(dim.truncatingRemainder(dividingBy: step), 0)
        }
    }

    func testProxyDimensionClampedToBounds() {
        // 작은 창은 하한(불필요하게 작은 렌더 방지 + 소형 창 속도 이득).
        XCTAssertEqual(
            DevelopFrameRenderer.interactiveProxyDimension(displayTargetPixels: 300),
            DevelopFrameRenderer.interactiveMinDimension
        )
        // 5K급 대형 표시는 정착 패스와 동일한 상한 — 두 패스 치수가 같아져 스왑이 무변화.
        XCTAssertEqual(
            DevelopFrameRenderer.interactiveProxyDimension(displayTargetPixels: 5200),
            DevelopFrameRenderer.fullMaxDimension
        )
        XCTAssertEqual(
            DevelopFrameRenderer.interactiveProxyDimension(displayTargetPixels: 3599),
            DevelopFrameRenderer.fullMaxDimension
        )
    }

    // MARK: 레이아웃 종횡비 안정화

    func testRoundingLevelAspectDifferenceIsIgnored() {
        // 3600×2400(정착) vs 1600×1067(인터랙티브 프록시 반올림) — 같은 컷의 두 프록시.
        // 이 차이가 레이아웃을 갱신하면 스왑 때마다 fitted frame이 서브픽셀 이동한다(떨림).
        XCTAssertFalse(ScanFrame.aspectDiffers(
            CGSize(width: 3600, height: 2400),
            from: CGSize(width: 1600, height: 1067)
        ))
        // 동일 종횡비 스케일 차이도 무시.
        XCTAssertFalse(ScanFrame.aspectDiffers(
            CGSize(width: 3600, height: 2400),
            from: CGSize(width: 1800, height: 1200)
        ))
    }

    func testRealGeometryChangeIsDetected() {
        // 크롭 3:2 → 1:1, 회전 90° 등 실제 기하 변화는 반드시 감지.
        XCTAssertTrue(ScanFrame.aspectDiffers(
            CGSize(width: 3600, height: 2400),
            from: CGSize(width: 2400, height: 2400)
        ))
        XCTAssertTrue(ScanFrame.aspectDiffers(
            CGSize(width: 3600, height: 2400),
            from: CGSize(width: 2400, height: 3600)
        ))
        // 기준이 없으면 항상 채택.
        XCTAssertTrue(ScanFrame.aspectDiffers(nil, from: CGSize(width: 100, height: 100)))
    }

    @MainActor
    func testInteractiveResultDoesNotDisturbSettledLayoutSize() {
        let frame = Self.makeFrame()
        // 정착(권위) 크기 기록.
        frame.noteDevelopedDisplaySize(CGSize(width: 3600, height: 2400), authoritative: true)
        // 인터랙티브 프록시(반올림 종횡비)는 레이아웃 크기를 건드리지 않는다.
        frame.noteDevelopedDisplaySize(CGSize(width: 1600, height: 1067), authoritative: false)
        XCTAssertEqual(frame.displayPixelSize, CGSize(width: 3600, height: 2400))
        // 실제 기하 변화(회전)는 인터랙티브 결과라도 채택한다.
        frame.noteDevelopedDisplaySize(CGSize(width: 1067, height: 1600), authoritative: false)
        XCTAssertEqual(frame.displayPixelSize, CGSize(width: 1067, height: 1600))
        // 권위 경로는 항상 갱신.
        frame.noteDevelopedDisplaySize(CGSize(width: 2400, height: 3600), authoritative: true)
        XCTAssertEqual(frame.displayPixelSize, CGSize(width: 2400, height: 3600))
    }

    @MainActor
    func testFirstResultAdoptedWhenNoSizeRecorded() {
        let frame = Self.makeFrame()
        XCTAssertNil(frame.displayPixelSize)
        frame.noteDevelopedDisplaySize(CGSize(width: 1600, height: 1067), authoritative: false)
        XCTAssertEqual(frame.displayPixelSize, CGSize(width: 1600, height: 1067))
    }

    @MainActor
    func testInvalidSizeIgnored() {
        let frame = Self.makeFrame()
        frame.noteDevelopedDisplaySize(CGSize(width: 3600, height: 2400), authoritative: true)
        frame.noteDevelopedDisplaySize(.zero, authoritative: true)
        XCTAssertEqual(frame.displayPixelSize, CGSize(width: 3600, height: 2400))
    }

    // MARK: 인터랙티브 raw 프록시 캐시(치수 태깅)

    @MainActor
    func testClearPreviewRawCachesResetsDimension() {
        let frame = Self.makeFrame()
        frame.cachedInteractivePreviewRawDimension = 2816
        frame.cachedInteractivePreviewRawRevision = 3
        frame.clearPreviewRawCaches()
        XCTAssertEqual(frame.cachedInteractivePreviewRawDimension, 0)
        XCTAssertEqual(frame.cachedInteractivePreviewRawRevision, -1)
        XCTAssertNil(frame.cachedInteractivePreviewRaw)
        XCTAssertNil(frame.cachedSettledPreviewRaw)
    }

    @MainActor
    private static func makeFrame() -> ScanFrame {
        ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-preview-resolution-test-\(UUID().uuidString).tiff"),
            filmType: .colorNegative
        )
    }
}
