import XCTest
@testable import Chromabase

// 스크래치 검출 최적화(캐시 연속화)가 출력을 바꾸지 않음을 비트 단위로 보증하는 안전망.
//
// 최적화는 "메모리 접근 순서만" 바꾸고 수학(어떤 값을 더하는지·순서)은 불변이어야 한다. 여러
// 방향(가로/세로/대각/급경사)의 합성 선 + 그레인으로 후보 맵을 만들고, strong/weak 의 켜진 픽셀
// 수와 위치 해시를 골든으로 고정한다. 최적화 후 이 값이 어긋나면(=출력 변경) 즉시 실패한다.
final class DefectScratchEquivalenceTests: XCTestCase {
    /// 합성 rgba(sRGB 감마 도메인 값). 다양한 방향의 어두운 선 + 결정적 그레인.
    private func syntheticRGBA(_ w: Int, _ h: Int) -> [Float] {
        var px = [Float](repeating: 0, count: w * h * 4)
        // 배경 0.55 회색 + 결정적 의사난수 그레인(채널 독립).
        var state: UInt64 = 0x1234_5678_9abc_def0
        func rnd() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 40) & 0xFFFF) / 65535.0
        }
        for i in 0..<(w * h) {
            let o = i * 4
            for c in 0..<3 { px[o + c] = 0.55 + (rnd() - 0.5) * 0.06 }
            px[o + 3] = 1
        }
        func darken(_ x: Int, _ y: Int, _ amt: Float) {
            guard x >= 0, x < w, y >= 0, y < h else { return }
            let o = (y * w + x) * 4
            for c in 0..<3 { px[o + c] = max(0, px[o + c] - amt) }
        }
        // 가로선, 세로선, 45° 대각, 급경사(≈72°), 완경사(≈18°).
        for x in 20..<300 { darken(x, 120, 0.25) }
        for y in 20..<300 { darken(160, y, 0.25) }
        for t in 0..<250 { darken(40 + t, 40 + t, 0.25) }
        for t in 0..<250 { darken(60 + t / 3, 40 + t, 0.25) }   // 급경사
        for t in 0..<250 { darken(40 + t, 60 + t / 3, 0.25) }   // 완경사
        return px
    }

    private func checksum(_ map: [Bool]) -> (count: Int, hash: UInt64) {
        var count = 0
        var hash: UInt64 = 1469598103934665603   // FNV-1a
        for (i, v) in map.enumerated() where v {
            count += 1
            hash = (hash ^ UInt64(i)) &* 1099511628211
        }
        return (count, hash)
    }

    func testCandidatesLeveledStableChecksum() {
        let w = 360, h = 360
        let field = DefectContrastField(rgba: syntheticRGBA(w, h), width: w, height: h, parallel: false)
        let r = DefectScratchDetector.candidatesLeveled(
            field, sensitivity: 0.7, protectDetail: 0.6, aggressive: false, parallel: false)
        let strong = checksum(r.strong)
        let weak = checksum(r.weak)
        // 골든(현재 구현 캡처, 2026-07-23). 최적화 후 이 값이 어긋나면 출력이 바뀐 것 → 실패.
        XCTAssertEqual(strong.count, DefectScratchEquivalenceGolden.strongCount, "strong count")
        XCTAssertEqual(strong.hash, DefectScratchEquivalenceGolden.strongHash, "strong hash")
        XCTAssertEqual(weak.count, DefectScratchEquivalenceGolden.weakCount, "weak count")
        XCTAssertEqual(weak.hash, DefectScratchEquivalenceGolden.weakHash, "weak hash")
        // 골든 캡처용(환경변수로 현재값 출력).
        if ProcessInfo.processInfo.environment["PRINT_GOLDEN"] != nil {
            print("GOLDEN strongCount=\(strong.count) strongHash=\(strong.hash) weakCount=\(weak.count) weakHash=\(weak.hash)")
        }
    }
}

enum DefectScratchEquivalenceGolden {
    static let strongCount = 1407
    static let strongHash: UInt64 = 17024625552919706857
    static let weakCount = 1435
    static let weakHash: UInt64 = 15131133059003356370
}
