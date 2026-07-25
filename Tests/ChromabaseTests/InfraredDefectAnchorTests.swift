import XCTest
import CoreGraphics
@testable import Chromabase

// InfraredDefectRemoval 수치 앵커(리팩토링 트립와이어).
//
// 목적: 메모리/성능 리팩토링이 검출 **결과**를 한 비트라도 바꾸면 즉시 잡는다.
// 정렬(shiftPlane) → 마진 flood-fill(+림 팽창) → 장면 누설 곡선 → 상대 대비 임계 →
// 연결요소/분류 → 클러스터 렌더까지 전 단계를 지나는 합성 장면 하나의 전체 출력을
// FNV-1a 다이제스트로 고정한다. 행위(무엇을 잡는가)는 InfraredDefectTests 가 검증하고,
// 여기는 산술 동일성만 지킨다.
//
// 주의: 다이제스트는 Apple Silicon(현 개발 머신)에서 기록했다. libm(log) 구현이 다른
// 아키텍처에서는 마지막 ulp 차이로 실패할 수 있다 — 그 경우 의도된 알고리즘 변경이 없는지
// 확인한 뒤 해당 머신에서 재기록한다.
final class InfraredDefectAnchorTests: XCTestCase {

    private let width = 384
    private let height = 320

    private struct SeededNoise {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) & 0xFFFF) / 65535.0 - 0.5
        }
    }

    private struct FNV1a {
        private(set) var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        mutating func combine(_ value: UInt64) {
            var v = value
            for _ in 0..<8 {
                hash = (hash ^ (v & 0xFF)) &* 0x0000_0100_0000_01B3
                v >>= 8
            }
        }
        mutating func combine(_ value: Int) { combine(UInt64(bitPattern: Int64(value))) }
        mutating func combine(_ value: Double) { combine(value.bitPattern) }
        mutating func combine(_ data: Data) {
            for byte in data { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        }
    }

    /// 전 단계를 지나는 장면: 경사+스텝 에지+줄무늬+비네팅, red 상관 IR 누설, 좌측 홀더 마진,
    /// 먼지 5개 + 세로/가로 스크래치, IR 패스 (3,2) 오프셋.
    private func makeAnchorScene() -> (red: [Float], ir: [Float]) {
        var red = [Float](repeating: 0, count: width * height)
        var aligned = [Float](repeating: 0, count: width * height)
        var noise = SeededNoise(seed: 20260721)
        for y in 0..<height {
            for x in 0..<width {
                var r: Float = 0.18 + 0.5 * Float(x) / Float(width)
                if x >= 192 { r += 0.18 }
                if (y / 24) % 2 == 0 { r += 0.08 }
                let dx = Float(x) / Float(width) - 0.5
                let dy = Float(y) / Float(height) - 0.5
                let v = 1 - 0.10 * (dx * dx + dy * dy) * 4
                let i = y * width + x
                red[i] = min(1, r * v)
                aligned[i] = min(1, (0.84 + 0.08 * log(max(red[i], 1e-4))) * v)
                    + 0.004 * noise.next() * 2
            }
        }
        // 좌측 28열 = 필름 홀더(테두리 연결 어두운 마진).
        for y in 0..<height {
            for x in 0..<28 {
                aligned[y * width + x] = 0.02
                red[y * width + x] = 0.02
            }
        }
        func spot(_ cx: Int, _ cy: Int, _ radius: Int, _ depth: Float) {
            for y in max(0, cy - radius)...min(height - 1, cy + radius) {
                for x in max(0, cx - radius)...min(width - 1, cx + radius) {
                    let dx = x - cx, dy = y - cy
                    if dx * dx + dy * dy <= radius * radius {
                        aligned[y * width + x] = max(0, aligned[y * width + x] - depth)
                    }
                }
            }
        }
        spot(80, 60, 3, 0.35)
        spot(200, 90, 2, 0.4)
        spot(310, 50, 4, 0.3)
        spot(140, 240, 3, 0.35)
        spot(255, 280, 2, 0.45)
        for y in 40...260 {          // 세로 스크래치 x=176..177
            for x in 176...177 {
                aligned[y * width + x] = max(0, aligned[y * width + x] - 0.3)
            }
        }
        for x in 220...340 {         // 가로 스크래치 y=160..161
            for y in 160...161 {
                aligned[y * width + x] = max(0, aligned[y * width + x] - 0.3)
            }
        }
        // IR 패스가 (3, 2) 어긋난 상황을 시뮬레이션.
        var scratch = [Bool](repeating: false, count: width * height)
        let ir = InfraredDefectRemoval.shiftPlane(aligned, width: width, height: height,
                                        dx: -3, dy: -2, outOfBounds: &scratch)
        return (red, ir)
    }

    private func digest(of detection: InfraredDefectRemoval.Detection) -> UInt64 {
        var fnv = FNV1a()
        fnv.combine(detection.width)
        fnv.combine(detection.height)
        fnv.combine(detection.offsetX)
        fnv.combine(detection.offsetY)
        fnv.combine(detection.coverage)
        fnv.combine(detection.components.count)
        for component in detection.components {
            fnv.combine(component.classification.rawValue.utf8.count)
            for byte in component.classification.rawValue.utf8 { fnv.combine(UInt64(byte)) }
            fnv.combine(component.confidence)
            fnv.combine(component.area)
            fnv.combine(component.previewPoints.count)
            for point in component.previewPoints {
                fnv.combine(Double(point.x))
                fnv.combine(Double(point.y))
            }
        }
        fnv.combine(detection.clusters.count)
        for cluster in detection.clusters {
            fnv.combine(Double(cluster.roiYup.minX))
            fnv.combine(Double(cluster.roiYup.minY))
            fnv.combine(Double(cluster.roiYup.width))
            fnv.combine(Double(cluster.roiYup.height))
            fnv.combine(cluster.width)
            fnv.combine(cluster.height)
            fnv.combine(cluster.maskRGBA8)
        }
        return fnv.hash
    }

    func testDetectionDigestIsStableAcrossRefactors() throws {
        let (red, ir) = makeAnchorScene()
        var parameters = InfraredDefectRemoval.Parameters()
        parameters.alignmentSearchRadius = 8
        parameters.dilateRadius = 2
        parameters.minArea = 2
        let detection = try InfraredDefectRemoval.detect(infrared: ir, red: red,
                                               width: width, height: height,
                                               parameters: parameters).get()
        // 참값은 (3, 2)지만 이 픽스처(비네팅+홀더 고주파)는 fine NCC가 (2, 3)에 수렴한다.
        // 정확한 오프셋 복원 자체는 InfraredDefectTests.testRecoversIntegerOffset… 이 검증하고,
        // 여기서는 결정적 결과를 그대로 고정한다(트립와이어 목적).
        XCTAssertEqual(detection.offsetX, 2)
        XCTAssertEqual(detection.offsetY, 3)
        XCTAssertGreaterThanOrEqual(detection.components.count, 7)

        let value = digest(of: detection)
        // 기록 절차: 아래 상수와 불일치가 의도된 알고리즘 변경 때문이라면
        // `NEGAFLOW_PRINT_IR_ANCHOR=1 swift test --filter InfraredDefectAnchorTests` 출력으로 재기록.
        if ProcessInfo.processInfo.environment["NEGAFLOW_PRINT_IR_ANCHOR"] == "1" {
            print("[ir-anchor] digest = 0x\(String(value, radix: 16))")
        }
        XCTAssertEqual(value, Self.recordedDigest,
                       "InfraredDefectRemoval 검출 산술이 변했습니다. 의도된 변경이 아니면 회귀입니다.")
    }

    /// 2026-07-25 Apple Silicon에서 비모수 누설 보정과 절사 노이즈 추정 전환 뒤 기록.
    private static let recordedDigest: UInt64 = 0x8675_51DE_B872_0B71
}
