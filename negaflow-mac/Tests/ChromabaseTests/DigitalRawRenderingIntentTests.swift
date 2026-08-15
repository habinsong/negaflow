import CoreImage
import Foundation
import XCTest
@testable import Chromabase

/// RAW 디코드 의도(scene-linear ↔ camera-rendered) 회귀 가드.
///
/// 실제 RAW 파일 없이도 성립하는 계약만 검사한다 — 실측 대조는
/// `DigitalRawRenderingDiagnosticsTests`(opt-in)가 맡는다.
final class DigitalRawRenderingIntentTests: XCTestCase {

    func testSceneLinearKeepsToneCurveOffAndCameraRenderedUsesDecoderDefault() {
        XCTAssertEqual(ImageLoader.RAWRendering.sceneLinear.boostAmount, 0)
        // CIRAWFilter 의 손대지 않은 기본값이 1.0 이다(실측). 카메라 렌더링은 그 기본을 쓴다.
        XCTAssertEqual(ImageLoader.RAWRendering.cameraRendered.boostAmount, 1)
    }

    /// 필름 경로는 절대 톤 커브를 받으면 안 된다 — 반전이 linear 투과율을 전제한다.
    func testFilmProcessesStaySceneLinear() {
        for isDigitalSource in [nil, false] as [Bool?] {
            XCTAssertEqual(
                ImageLoader.RAWRendering.forDigitalSource(isDigitalSource),
                .sceneLinear,
                "필름/미지정 소스는 linear 를 유지해야 한다"
            )
        }
    }

    func testDigitalProcessesUseCameraRendering() {
        XCTAssertEqual(ImageLoader.RAWRendering.forDigitalSource(true), .cameraRendered)
    }

    /// 기본값이 바뀌면 필름 스캔 raw DNG 가 조용히 망가진다.
    func testLoaderDefaultsPreserveFilmBehaviour() {
        XCTAssertEqual(ImageLoader.defaultRAWBoostAmount, 0)
    }

    /// 모든 RAW 확장자가 같은 디코드 경로로 들어가야 포맷별 편차가 생기지 않는다.
    func testEveryRawExtensionRoutesToTheRawDecoder() {
        for ext in ImageLoader.rawExtensions {
            let url = URL(fileURLWithPath: "/tmp/negaflow-route-check.\(ext)")
            XCTAssertEqual(ImageLoader.kind(of: url), .rawDng, "\(ext) 가 RAW 경로로 가지 않는다")
        }
    }
}
