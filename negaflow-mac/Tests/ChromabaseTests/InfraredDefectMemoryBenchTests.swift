import XCTest
import Darwin
@testable import Chromabase

// InfraredDefectRemoval 풀해상도 메모리/시간 벤치(옵트인).
//
//   NEGAFLOW_IR_BENCH=1 swift test --filter InfraredDefectMemoryBenchTests
//
// 24MP(6000×4000) 합성 평면에서 detect 의 wall time 과 phys_footprint 증가분을 측정해
// 출력한다. 다른 테스트와 같이 돌면 lifetime max 가 이미 높아져 delta 가 0이 될 수 있으므로
// 반드시 단독 필터로 실행한다. 판정 기준은 없고(환경 의존) 회귀 비교용 수치만 남긴다.
final class InfraredDefectMemoryBenchTests: XCTestCase {

    private static func physFootprint() -> (current: UInt64, lifetimeMax: UInt64) {
        var info = rusage_info_current()
        let status = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, $0)
            }
        }
        guard status == 0 else { return (0, 0) }
        return (info.ri_phys_footprint, info.ri_lifetime_max_phys_footprint)
    }

    func testFullResolutionDetectFootprint() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NEGAFLOW_IR_BENCH"] == "1",
            "옵트인 벤치: NEGAFLOW_IR_BENCH=1 로 실행"
        )
        let width = 6000, height = 4000
        let count = width * height
        var red = [Float](repeating: 0, count: count)
        var aligned = [Float](repeating: 0, count: count)
        var state: UInt64 = 977
        for y in 0..<height {
            for x in 0..<width {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let noise = Float((state >> 33) & 0xFFFF) / 65535.0 - 0.5
                var r: Float = 0.2 + 0.5 * Float(x) / Float(width)
                if (y / 160) % 2 == 0 { r += 0.08 }
                let i = y * width + x
                red[i] = min(1, r)
                aligned[i] = min(1, 0.84 + 0.08 * log(max(red[i], 1e-4))) + 0.004 * noise
            }
        }
        // 먼지 40개 + 세로 스크래치 2개.
        var spotState: UInt64 = 7
        for _ in 0..<40 {
            spotState = spotState &* 6364136223846793005 &+ 1442695040888963407
            let cx = 100 + Int((spotState >> 33) % UInt64(width - 200))
            spotState = spotState &* 6364136223846793005 &+ 1442695040888963407
            let cy = 100 + Int((spotState >> 33) % UInt64(height - 200))
            for y in (cy - 4)...(cy + 4) {
                for x in (cx - 4)...(cx + 4)
                where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= 16 {
                    aligned[y * width + x] = max(0, aligned[y * width + x] - 0.35)
                }
            }
        }
        for x in [1500, 4200] {
            for y in 400..<3600 {
                aligned[y * width + x] = max(0, aligned[y * width + x] - 0.3)
                aligned[y * width + x + 1] = max(0, aligned[y * width + x + 1] - 0.3)
            }
        }
        var scratch = [Bool](repeating: false, count: count)
        var ir = InfraredDefectRemoval.shiftPlane(aligned, width: width, height: height,
                                        dx: -5, dy: -3, outOfBounds: &scratch)
        scratch = []
        aligned = []

        let before = Self.physFootprint()
        let start = ContinuousClock().now
        // 실제 앱 경로(CI 렌더 → 유일 소유 평면)와 동일하게 소유권을 넘긴다 —
        // 단계별 조기 반납이 실측에 반영된다.
        let outcome = InfraredDefectRemoval.detectConsumingPlanes(
            infrared: &ir, red: &red,
            width: width, height: height,
            parameters: InfraredDefectRemoval.Parameters()
        )
        let elapsed = ContinuousClock().now - start
        let after = Self.physFootprint()

        guard case .success(let detection) = outcome else {
            return XCTFail("24MP 합성 장면 검출이 실패했습니다: \(outcome)")
        }
        let deltaMB = Double(after.lifetimeMax &- before.lifetimeMax) / 1_048_576
        print("""
        [ir-bench] 24MP detect: wall=\(elapsed) \
        peakAddedMB=\(String(format: "%.1f", deltaMB)) \
        currentMB=\(String(format: "%.1f", Double(after.current) / 1_048_576)) \
        clusters=\(detection.clusters.count) components=\(detection.components.count) \
        coverage=\(String(format: "%.5f", detection.coverage))
        """)
    }
}
