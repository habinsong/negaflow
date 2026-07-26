import XCTest
@testable import Chromabase

// 코어(strong) 밀도 하한 검증 — 합성 후보 맵 전용.
//
// 실제 버그(2026-07-26): 흑백 네거티브를 가이드로 드래그하면 "유제 손상 1건"이 뜨는데 실제로는
// ROI 상당 부분이 검출돼 제거 시 뭉개졌다. 가이드는 먼지 면적 상한을 물리 크기의 49배까지 열기
// 때문에(5000px 스캔에서 238×238px), weak 연결로 이어 붙은 그레인 카펫이 그 상한 아래로 들어와
// 통과했다 — "면적 게이트가 카펫을 막는다"는 전제가 확장된 상한에서 무너져 있었다.
//
// 판별 축은 코어 밀도다: 실제 이물은 strong 이 몸통을 채우고, 카펫은 드문드문하다. 면적 상한을
// 크게 열어 둔 채(=가이드 조건) 검증한다.
final class RegionDefectGrainCarpetTests: XCTestCase {
    private let width = 300
    private let height = 300
    /// 가이드 경로처럼 넉넉히 열어 둔 면적 상한.
    private let generousMaxDustArea = 60_000

    private func emptyMap() -> [Bool] { [Bool](repeating: false, count: width * height) }

    private func build(dust: [Bool], strong: [Bool]) -> DefectLabelField {
        DefectComponentMask.buildLabeled(
            width: width, height: height,
            dust: dust, scratch: emptyMap(),
            scratchStrong: emptyMap(), dustStrong: strong,
            maxDustArea: generousMaxDustArea,
            minScratchLength: 6,
            dustMaxAspect: 8
        )
    }

    private var largestComponent: (DefectLabelField) -> Int {
        { $0.components.map(\.pixelCount).max() ?? 0 }
    }

    // MARK: 카펫 — 넓게 이어졌지만 코어가 드문드문

    func testSparselyCoredCarpetIsRejected() {
        var dust = emptyMap()
        var strong = emptyMap()
        // 120x120 영역을 촘촘히 채워 하나의 큰 컴포넌트로 잇는다(면적 상한 아래).
        for y in 60..<180 {
            for x in 60..<180 {
                dust[y * width + x] = true
                // 코어는 12x12 격자마다 하나 — 약 0.7%.
                if x % 12 == 0, y % 12 == 0 { strong[y * width + x] = true }
            }
        }

        let field = build(dust: dust, strong: strong)
        XCTAssertTrue(field.isEmpty,
                      "코어가 드문드문한 카펫은 면적 상한을 통과하더라도 기각되어야 한다 "
                      + "(최대 \(largestComponent(field))px)")
    }

    // MARK: 실제 이물 — 코어가 몸통을 채운다

    func testSolidlyCoredBlobIsAccepted() {
        var dust = emptyMap()
        var strong = emptyMap()
        let cx = 150, cy = 150, radius = 10
        for y in (cy - radius)...(cy + radius) {
            for x in (cx - radius)...(cx + radius) {
                let dx = x - cx, dy = y - cy
                guard dx * dx + dy * dy <= radius * radius else { continue }
                dust[y * width + x] = true
                // 코어가 안쪽을 채운다(가장자리만 weak 프린지).
                if dx * dx + dy * dy <= (radius - 3) * (radius - 3) { strong[y * width + x] = true }
            }
        }

        let field = build(dust: dust, strong: strong)
        XCTAssertFalse(field.isEmpty, "코어가 찬 실제 이물은 채택되어야 한다")
        XCTAssertGreaterThan(largestComponent(field), 100)
    }

    // MARK: 작은 결함은 코어 하나로도 통과한다

    func testTinyDefectWithSingleCorePasses() {
        var dust = emptyMap()
        var strong = emptyMap()
        // 3x3 먼지에 코어 1개 = 11% — 밀도 하한(8%)을 넘는다.
        for y in 100..<103 {
            for x in 100..<103 { dust[y * width + x] = true }
        }
        strong[101 * width + 101] = true

        let field = build(dust: dust, strong: strong)
        XCTAssertFalse(field.isEmpty, "작은 먼지는 코어 하나로도 비율을 충족해 통과해야 한다")
    }
}
