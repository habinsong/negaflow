import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// 실제 스캔(보도블럭 하단)을 테스트베드로 한 스크래치 오검출 측정 하네스.
//
// 커밋된 정규 스위트는 합성 픽스처만 쓴다(이 파일은 SPECK_REAL_FILE 환경변수가 있을 때만 동작).
// 반복 개발 중 실제 파일로 자동 검출을 돌려, 보도블럭 영역의 스크래치 컴포넌트 수를 수치로 재고
// 알고리즘을 조정하기 위한 도구다(육안 판단 없음 — 개수 측정만).
//
// 반복 속도를 위해 긴 변 ~2200px 로 다운스케일하고 microSpeck 은 끈다(스크래치 오검출만 측정).
// 사용법:
//   SPECK_REAL_FILE="/path/OpticFilm8100_frame_3.tiff" swift test --filter DefectPaverRealMeasureTests
final class DefectPaverRealMeasureTests: XCTestCase {
    func testMeasurePaverScratchFalsePositives() throws {
        guard let path = ProcessInfo.processInfo.environment["SPECK_REAL_FILE"] else {
            throw XCTSkip("SPECK_REAL_FILE 미설정 — 실제 파일 측정 하네스 건너뜀")
        }
        let url = URL(fileURLWithPath: path)
        guard let loaded = ChromabaseEngine().loadScannerImage(url) else {
            return XCTFail("스캔 이미지 로드 실패: \(path)")
        }
        // 반복 속도용 다운스케일(스크래치 텍스처는 스케일 무관 — 방법론 검증에 충분).
        let longSide = max(loaded.extent.width, loaded.extent.height)
        let target: CGFloat = 2200
        let scale = longSide > target ? target / longSide : 1
        let image = scale < 1
            ? loaded.applyingFilter("CILanczosScaleTransform",
                                    parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0])
                .cropped(to: CGRect(x: 0, y: 0,
                                    width: (loaded.extent.width * scale).rounded(),
                                    height: (loaded.extent.height * scale).rounded()))
            : loaded
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6,
                                           detectMicroSpecks: false)
        // 앱 자동 모드 재현: 0..1 ROI 가 변환·반올림으로 extent 와 1px 어긋난 상황(constrainedRegion
        // 오판을 유발). wholeFrameAuto=false 면 부분 ROI로 오판(오검출 폭증), true 면 억제되어야 한다.
        let insetROI = image.extent.insetBy(dx: 1, dy: 1)
        func measure(_ label: String, wholeFrameAuto: Bool) {
            let clock = Date()
            let field = SoftwareDefectRemoval.detectComponents(
                in: image, roi: insetROI, parameters: params, wholeFrameAuto: wholeFrameAuto)
            let ms = Date().timeIntervalSince(clock) * 1000
            let h = field.height
            let scratch = field.components.filter { $0.kind == .scratch }
            let lower = scratch.filter { ($0.minY + $0.maxY) / 2 >= h / 2 }.count
            print("""
            PAVER-MEASURE[\(label)]  \(field.width)x\(field.height)  \(Int(ms))ms
              scratch=\(scratch.count) (upper=\(scratch.count - lower) lower=\(lower))  \
            dust=\(field.components.filter { $0.kind == .dust }.count)  total=\(field.components.count)
            """)
        }
        measure("app-bug(off)", wholeFrameAuto: false)
        measure("fixed(auto)", wholeFrameAuto: true)

        // 수정 경로(auto)의 보도블럭 스크래치가 소수여야 한다.
        let fixed = SoftwareDefectRemoval.detectComponents(
            in: image, roi: insetROI, parameters: params, wholeFrameAuto: true)
        let scratch = fixed.components.filter { $0.kind == .scratch }
        XCTAssertLessThan(scratch.count, 40, "auto 경로 스크래치 오검출 과다: \(scratch.count)")
    }
}
