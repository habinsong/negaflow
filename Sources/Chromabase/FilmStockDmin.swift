import Foundation
import simd

// MARK: - 필름별 Dmin/Dmax 레지스트리
//
// 자동 베이스 추정(FilmBaseEstimator + sampleStats)은 장면 의존적 한계가 있다: 파란 하늘·녹색 풀
// 같은 장면 색 분포가 채널별 Dmin/Dmax 추정을 어긋나게 해 보라/시안 hue shift를 만든다. 수학적으로
// "보라 방지(채널별 Dmax 단일화)"와 "염료 분리 보존(채널별 Dmax)"을 동시에 만족시킬 수 없다.
//
// 해결: 제조사 특성곡선에서 읽은 필름별 Dmin(오렌지 마스크 농도)과 Dmax(최대 밀도)를 제공한다.
// 이 값들은 장면 독립적인 **필름 물성**이므로, 프리셋이 선택되면 자동 추정을 덮어쓴다 → 보라와
// 염료 분리를 동시에 만족시킨다(negadoctor 모델: Dmin/Dmax는 필름 고정값).
//
// 출처: Kodak/Fuji 공식 데이터시트의 "Typical densities for D-min" 및 sensitometric curve
// (Status M, C-41/ECN-2)에서 읽은 대략값. 스캐너 RGB 채널(650/550/450nm 근사)에 대응.
// 밀도(D) → 투과율(T) 변환: T = 10^(-D). 현상 조건/로트/보관/스캐너 광원에 따라 ±0.05~0.15D 흔들림.

/// 단일 필름의 밀도 특성(R/G/B 채널별 Dmin, Dmax).
public struct FilmStockDmin: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    /// 사용자 표시명(예: "Kodak Portra 400").
    public let displayName: String
    /// 제조사 그룹(UI 그룹화용).
    public let manufacturer: String
    /// ISO 감도(정렬/표시용).
    public let iso: Int
    /// 현상 공정(예: "C-41", "ECN-2").
    public let process: String
    /// D-min(오렌지 마스크) 밀도. R/G/B.
    public let dminDensity: SIMD3<Double>
    /// D-max(최대 밀도, 특성곡선 과노출 끝 근사). R/G/B.
    public let dmaxDensity: SIMD3<Double>

    public init(id: String, displayName: String, manufacturer: String, iso: Int, process: String,
                dminDensity: SIMD3<Double>, dmaxDensity: SIMD3<Double>) {
        self.id = id
        self.displayName = displayName
        self.manufacturer = manufacturer
        self.iso = iso
        self.process = process
        self.dminDensity = dminDensity
        self.dmaxDensity = dmaxDensity
    }

    /// D-min 밀도 → 스캐너 linear 투과율. T = 10^(-D). 이 값이 NegativeInversion의 base.rgb/Dmin이 된다.
    public var dminTransmission: SIMD3<Double> {
        SIMD3(pow(10.0, -dminDensity.x), pow(10.0, -dminDensity.y), pow(10.0, -dminDensity.z))
    }

    /// D-max 밀도 → 투과율. 가장 어두운(밀도 높은) 픽셀의 하한.
    public var dmaxTransmission: SIMD3<Double> {
        SIMD3(pow(10.0, -dmaxDensity.x), pow(10.0, -dmaxDensity.y), pow(10.0, -dmaxDensity.z))
    }

    /// 채널별 정규화 밀도 범위(Dmax - Dmin). dmaxNorm으로 사용 — 장면 독립적 필름 물성.
    public var dmaxNorm: SIMD3<Double> {
        SIMD3(dmaxDensity.x - dminDensity.x, dmaxDensity.y - dminDensity.y, dmaxDensity.z - dminDensity.z)
    }
}

public enum FilmStockDminRegistry {
    // 밀도(D) 중간값들을 저장. 투과율/정규화는 FilmStockDmin이 계산.
    // 데이터 출처: Kodak/Fuji 공식 데이터시트 "Typical densities for D-min" + 특성곡선(과노출 끝).
    // CineStill/Reflx는 Vision3 기반 추정, Lomo는 표준 C-41 범위 추정, Harman/ORWO는 마스크 없음/회색 베이스.
    public static let all: [FilmStockDmin] = [
        // --- Kodak still C-41 ---
        .init(id: "kodak-portra-160", displayName: "Kodak Portra 160", manufacturer: "Kodak", iso: 160, process: "C-41",
              dminDensity: SIMD3(0.22, 0.62, 0.82), dmaxDensity: SIMD3(2.20, 2.80, 3.00)),
        .init(id: "kodak-portra-400", displayName: "Kodak Portra 400", manufacturer: "Kodak", iso: 400, process: "C-41",
              dminDensity: SIMD3(0.21, 0.62, 0.82), dmaxDensity: SIMD3(2.25, 2.85, 3.05)),
        .init(id: "kodak-portra-800", displayName: "Kodak Portra 800", manufacturer: "Kodak", iso: 800, process: "C-41",
              dminDensity: SIMD3(0.27, 0.70, 0.95), dmaxDensity: SIMD3(2.20, 2.75, 2.95)),
        .init(id: "kodak-ektar-100", displayName: "Kodak Ektar 100", manufacturer: "Kodak", iso: 100, process: "C-41",
              dminDensity: SIMD3(0.25, 0.62, 0.82), dmaxDensity: SIMD3(2.25, 2.85, 3.05)),
        .init(id: "kodak-gold-200", displayName: "Kodak Gold 200", manufacturer: "Kodak", iso: 200, process: "C-41",
              dminDensity: SIMD3(0.24, 0.65, 0.88), dmaxDensity: SIMD3(2.05, 2.60, 2.80)),
        .init(id: "kodak-ultramax-400", displayName: "Kodak UltraMax 400", manufacturer: "Kodak", iso: 400, process: "C-41",
              dminDensity: SIMD3(0.25, 0.65, 0.90), dmaxDensity: SIMD3(2.05, 2.60, 2.80)),
        .init(id: "kodak-pro-image-100", displayName: "Kodak Pro Image 100", manufacturer: "Kodak", iso: 100, process: "C-41",
              dminDensity: SIMD3(0.25, 0.65, 0.85), dmaxDensity: SIMD3(2.05, 2.60, 2.85)),
        .init(id: "kodak-colorplus-200", displayName: "Kodak ColorPlus 200", manufacturer: "Kodak", iso: 200, process: "C-41",
              dminDensity: SIMD3(0.25, 0.65, 0.90), dmaxDensity: SIMD3(2.05, 2.60, 2.90)),
        // --- Fujifilm C-41/CN-16 ---
        .init(id: "fuji-c200", displayName: "Fujicolor C200", manufacturer: "Fujifilm", iso: 200, process: "C-41",
              dminDensity: SIMD3(0.20, 0.58, 0.88), dmaxDensity: SIMD3(1.85, 2.35, 2.65)),
        .init(id: "fuji-200", displayName: "Fujifilm 200", manufacturer: "Fujifilm", iso: 200, process: "C-41",
              dminDensity: SIMD3(0.20, 0.58, 0.88), dmaxDensity: SIMD3(1.85, 2.35, 2.65)),
        .init(id: "fuji-400", displayName: "Fujifilm 400", manufacturer: "Fujifilm", iso: 400, process: "C-41",
              dminDensity: SIMD3(0.14, 0.55, 0.95), dmaxDensity: SIMD3(2.00, 2.60, 2.80)),
        .init(id: "fuji-superia-400", displayName: "Fujifilm Superia X-TRA 400", manufacturer: "Fujifilm", iso: 400, process: "C-41",
              dminDensity: SIMD3(0.20, 0.58, 0.88), dmaxDensity: SIMD3(2.00, 2.60, 2.80)),
        .init(id: "fuji-100", displayName: "Fujicolor 100", manufacturer: "Fujifilm", iso: 100, process: "C-41",
              dminDensity: SIMD3(0.20, 0.58, 0.85), dmaxDensity: SIMD3(1.85, 2.35, 2.65)),
        // --- Kodak Vision3 (ECN-2, 영화용) ---
        .init(id: "vision3-50d", displayName: "Kodak Vision3 50D (5203)", manufacturer: "Kodak", iso: 50, process: "ECN-2",
              dminDensity: SIMD3(0.16, 0.60, 0.85), dmaxDensity: SIMD3(1.90, 2.70, 2.90)),
        .init(id: "vision3-200t", displayName: "Kodak Vision3 200T (5213)", manufacturer: "Kodak", iso: 200, process: "ECN-2",
              dminDensity: SIMD3(0.20, 0.62, 0.87), dmaxDensity: SIMD3(2.05, 2.75, 2.95)),
        .init(id: "vision3-250d", displayName: "Kodak Vision3 250D (5207)", manufacturer: "Kodak", iso: 250, process: "ECN-2",
              dminDensity: SIMD3(0.17, 0.62, 0.87), dmaxDensity: SIMD3(2.00, 2.70, 2.95)),
        .init(id: "vision3-500t", displayName: "Kodak Vision3 500T (5219)", manufacturer: "Kodak", iso: 500, process: "ECN-2",
              dminDensity: SIMD3(0.20, 0.62, 0.87), dmaxDensity: SIMD3(2.05, 2.75, 2.95)),
        // --- CineStill (Vision3 기반, remjet 제거, C-41 크로스) ---
        .init(id: "cinestill-50d", displayName: "CineStill 50D", manufacturer: "CineStill", iso: 50, process: "C-41",
              dminDensity: SIMD3(0.20, 0.65, 0.90), dmaxDensity: SIMD3(2.00, 2.70, 2.90)),
        .init(id: "cinestill-400d", displayName: "CineStill 400D", manufacturer: "CineStill", iso: 400, process: "C-41",
              dminDensity: SIMD3(0.24, 0.67, 0.92), dmaxDensity: SIMD3(2.05, 2.75, 2.95)),
        .init(id: "cinestill-800t", displayName: "CineStill 800T", manufacturer: "CineStill", iso: 800, process: "C-41",
              dminDensity: SIMD3(0.24, 0.70, 0.95), dmaxDensity: SIMD3(2.10, 2.75, 3.00)),
        // --- Lomography C-41 ---
        .init(id: "lomo-cn-100", displayName: "Lomo Color Negative 100", manufacturer: "Lomography", iso: 100, process: "C-41",
              dminDensity: SIMD3(0.22, 0.62, 0.88), dmaxDensity: SIMD3(2.00, 2.55, 2.80)),
        .init(id: "lomo-cn-400", displayName: "Lomo Color Negative 400", manufacturer: "Lomography", iso: 400, process: "C-41",
              dminDensity: SIMD3(0.24, 0.67, 0.92), dmaxDensity: SIMD3(2.05, 2.65, 2.90)),
        .init(id: "lomo-cn-800", displayName: "Lomo Color Negative 800", manufacturer: "Lomography", iso: 800, process: "C-41",
              dminDensity: SIMD3(0.27, 0.72, 0.97), dmaxDensity: SIMD3(2.10, 2.70, 2.95)),
        // --- 예외적 마스크 필름 ---
        .init(id: "harman-phoenix-200", displayName: "Harman Phoenix 200", manufacturer: "Harman", iso: 200, process: "C-41",
              dminDensity: SIMD3(0.22, 0.32, 0.40), dmaxDensity: SIMD3(1.70, 1.80, 2.15)),
        .init(id: "harman-phoenix-ii", displayName: "Harman Phoenix II", manufacturer: "Harman", iso: 200, process: "C-41",
              dminDensity: SIMD3(0.22, 0.32, 0.47), dmaxDensity: SIMD3(1.70, 1.80, 2.15)),
        .init(id: "orwo-wolfen-nc400", displayName: "ORWO Wolfen NC400", manufacturer: "ORWO", iso: 400, process: "C-41",
              dminDensity: SIMD3(0.40, 0.42, 0.55), dmaxDensity: SIMD3(1.85, 1.90, 2.10)),
        .init(id: "orwo-wolfen-nc500", displayName: "ORWO Wolfen NC500", manufacturer: "ORWO", iso: 500, process: "C-41",
              dminDensity: SIMD3(0.45, 0.48, 0.62), dmaxDensity: SIMD3(1.85, 1.90, 2.15)),
    ]

    /// id로 필름을 찾는다. 없으면 nil.
    public static func find(_ id: String) -> FilmStockDmin? {
        all.first { $0.id == id }
    }

    /// 제조사별 그룹화(UI Picker용). 정렬: 제조사 알파벳, 같은 제조사 내 ISO 오름차순.
    public static var groupedByManufacturer: [(manufacturer: String, stocks: [FilmStockDmin])] {
        let order = all.sorted { lhs, rhs in
            if lhs.manufacturer != rhs.manufacturer { return lhs.manufacturer < rhs.manufacturer }
            if lhs.iso != rhs.iso { return lhs.iso < rhs.iso }
            return lhs.displayName < rhs.displayName
        }
        var result: [(String, [FilmStockDmin])] = []
        for stock in order {
            if let idx = result.lastIndex(where: { $0.0 == stock.manufacturer }) {
                result[idx].1.append(stock)
            } else {
                result.append((stock.manufacturer, [stock]))
            }
        }
        return result
    }
}
