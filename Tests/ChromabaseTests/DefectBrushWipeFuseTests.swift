import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// 브러시 와이프 퓨즈 검증 — 실제 필름 그레인(덩어리·상관 노이즈)은 합성으로 재현이 안 되므로
// (롤백 교훈), 퓨즈가 막아야 하는 "채택 폭주" 상황을 후보 맵 레벨에서 직접 만든다:
//  ① preferredAngle 방향 적분이 그레인 잔차를 이은 "평행 줄무늬" 스크래치 컴포넌트 수십 개
//     → 응답 최강(실제 결함)만 남기고 스크래치 예산으로 컷.
//  ② 게이트를 각각 통과하는 먼지 blob 다수 → 전체 페인트 예산(칠 면적 40%)으로 컷.
// 퓨즈는 regionArea 가 주어진 브러시 경로 전용이라 전역/Region 경로는 기존 동작 그대로다.
final class DefectBrushWipeFuseTests: XCTestCase {
    private func maskedFraction(_ bytes: [UInt8], _ n: Int) -> Double {
        var c = 0
        for i in 0..<n where bytes[i * 4] > 0 { c += 1 }
        return Double(c) / Double(n)
    }
    private func covered(_ bytes: [UInt8], _ w: Int, _ pts: [(Int, Int)]) -> Double {
        guard !pts.isEmpty else { return 0 }
        var c = 0
        for (x, y) in pts where bytes[(y * w + x) * 4] > 0 { c += 1 }
        return Double(c) / Double(pts.count)
    }

    // ① 평행 그레인 줄무늬 25개 + 응답이 뚜렷한 실제 스크래치 1개: 실제 스크래치는 온전히
    //    마스크되고, 줄무늬 대량 채택(=칠 층층 재합성)은 예산으로 차단되어야 한다.
    func testParallelStripesCappedKeepingStrongestScratch() {
        let w = 520, h = 60
        let n = w * h
        let dust = [Bool](repeating: false, count: n)
        var scratch = [Bool](repeating: false, count: n)
        var response = [Float](repeating: 0, count: n)
        var stripePts: [(Int, Int)] = []
        var targetPts: [(Int, Int)] = []
        // 평행 줄무늬: y=2,4,...,58 (2px 간격, 폭 1) — 응답은 임계 언저리(0.007).
        for y in stride(from: 2, to: h, by: 2) where y != 30 {
            for x in 10..<510 {
                let p = y * w + x
                scratch[p] = true; response[p] = 0.007
                stripePts.append((x, y))
            }
        }
        // 실제 스크래치: y=30, 응답 뚜렷(0.03).
        for x in 10..<510 {
            let p = 30 * w + x
            scratch[p] = true; response[p] = 0.03
            targetPts.append((x, 30))
        }
        let regionArea = 500 * 56   // 칠 면적(대략)
        let bytes = DefectComponentMask.build(width: w, height: h, dust: dust, scratch: scratch,
                                           maxDustArea: 750, minScratchLength: 3,
                                           minScratchAspect: 1.8, dustDilate: 2,
                                           scratchResponse: response, regionArea: regionArea)
        let targetCov = covered(bytes, w, targetPts)
        let stripeCov = covered(bytes, w, stripePts)
        let frac = maskedFraction(bytes, n)
        print(String(format: "[fuse-stripe] target=%.0f%% stripes=%.0f%% masked=%.0f%%",
                     targetCov * 100, stripeCov * 100, frac * 100))
        XCTAssertGreaterThanOrEqual(targetCov, 0.95, "응답 최강(실제 스크래치)은 온전히 채택돼야 한다")
        XCTAssertLessThan(stripeCov, 0.25, "그레인 줄무늬 대량 채택(층층 와이프)은 예산으로 차단돼야 한다")
        XCTAssertLessThan(frac, 0.40, "마스크 총량은 칠 면적 예산을 넘을 수 없다")
    }

    // ①-보완: 퓨즈 없이(regionArea=nil, 전역/테스트 경로) 같은 입력이면 줄무늬가 전부
    //    채택된다 — 퓨즈가 실제로 차단 주체임을 고정한다(회귀 시 이 대비가 무너진다).
    func testStripesNotCappedWithoutRegionArea() {
        let w = 520, h = 60
        let n = w * h
        let dust = [Bool](repeating: false, count: n)
        var scratch = [Bool](repeating: false, count: n)
        for y in stride(from: 2, to: h, by: 2) {
            for x in 10..<510 { scratch[y * w + x] = true }
        }
        let bytes = DefectComponentMask.build(width: w, height: h, dust: dust, scratch: scratch,
                                           maxDustArea: 750, minScratchLength: 3,
                                           minScratchAspect: 1.8, dustDilate: 2)
        let frac = maskedFraction(bytes, n)
        XCTAssertGreaterThan(frac, 0.5, "퓨즈 비활성 경로는 기존 동작(전부 채택)이어야 한다")
    }

    // ② 게이트를 각각 통과하는 고립 먼지 blob 다수: 전체 페인트 예산(40%)이 총량을 막고,
    //    최강(최대) blob 은 항상 채택된다.
    func testManyDustBlobsCappedByTotalBudget() {
        let w = 400, h = 400
        let n = w * h
        var dust = [Bool](repeating: false, count: n)
        let scratch = [Bool](repeating: false, count: n)
        var bigPts: [(Int, Int)] = []
        // 큰 blob 1개(24×24) + 고립 blob 24개(14×14, 서로 80px 간격 — isolation/grain-field 통과).
        for y in 20..<44 { for x in 20..<44 { dust[y * w + x] = true; bigPts.append((x, y)) } }
        for gy in stride(from: 100, to: 400, by: 80) {
            for gx in stride(from: 20, to: 400, by: 80) {
                for y in gy..<min(h, gy + 14) { for x in gx..<min(w, gx + 14) { dust[y * w + x] = true } }
            }
        }
        let regionArea = 20_000   // 좁은 칠 면적 — 전부는 못 들어간다
        let bytes = DefectComponentMask.build(width: w, height: h, dust: dust, scratch: scratch,
                                           maxDustArea: 750, minScratchLength: 3,
                                           minScratchAspect: 1.8, dustDilate: 2,
                                           regionArea: regionArea)
        let bigCov = covered(bytes, w, bigPts)
        var painted = 0
        for i in 0..<n where bytes[i * 4] > 0 { painted += 1 }
        print("[fuse-dust] big=\(Int(bigCov * 100))% painted=\(painted) budget=\(Int(Double(regionArea) * 0.4))")
        XCTAssertGreaterThanOrEqual(bigCov, 0.99, "최대 blob(사용자가 노린 결함)은 항상 채택")
        // 페인트 추정(dilate 포함 상한 추정)이 예산을 지키므로 실제 페인트도 예산 근처를 넘지 않는다.
        XCTAssertLessThan(painted, Int(Double(regionArea) * 0.55), "먼지 대량 채택이 전체 예산으로 제한돼야 한다")
    }
}
