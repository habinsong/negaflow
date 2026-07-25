import Foundation
import simd

// MARK: - LightSourceProfile (스캔 광원 프로파일)
//
// 필름 데이터시트의 Dmin은 Status M 농도계 기준이고, 스캐너가 읽는 투과율은
// 광원 스펙트럼 × 센서 감도에 따라 달라진다. 같은 필름이라도 광원이 다르면
// 베이스가 다르게 찍힌다 — 이것이 "필름 프로파일 따로, 광원 프로파일 따로"가
// 필요한 이유다(분리하면 색이 예측 가능해진다).
//
// 원칙(실측 우선 — 측정 base 가 프리셋보다 우선):
//   1. 스캔에서 베이스를 실측(스포이드/가장자리)할 수 있으면 그것이 항상 Dmin 앵커다.
//      실측값은 광원+센서+퇴색을 전부 흡수하므로 광원 프로파일이 필요 없다.
//   2. 실측이 불가능할 때만(베이스가 프레임에 없음) 필름 프리셋 Dmin에 이 프로파일의
//      채널별 게인을 곱해 근사한다.
//   3. calibratedGain: 같은 (스캐너, 광원) 조합에서 한 번 실측했다면 그 비율을 광원
//      보정으로 재사용할 수 있다 — 이것이 "진짜" 광원 프로파일이다.
//
// 내장 게인 값은 정밀 측정치가 아니라 광원 유형별 경향(백열등=적색 과다, 백색 LED=청색
// 소폭 과다 등)을 반영한 보수적 시작점이다. 데이터 출처가 없는 값을 정밀한 척 하지 않는다.
public struct LightSourceProfile: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    /// 필름 Dmin 투과율에 곱하는 채널별 게인. (1,1,1) = 보정 없음.
    public let gain: SIMD3<Double>

    public init(id: String, displayName: String, gain: SIMD3<Double>) {
        self.id = id
        self.displayName = displayName
        self.gain = gain
    }

    /// 임의의 base 투과율(실측/프리셋)에 광원 채널 게인을 적용한다. (0, 1] 클램프.
    /// base(=Dmin, WB 앵커)를 채널별로 밀어 스캐너 광원 스펙트럼 편향을 반영/보정한다.
    public func applyGain(to base: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            min(max(base.x * gain.x, 1e-4), 1.0),
            min(max(base.y * gain.y, 1e-4), 1.0),
            min(max(base.z * gain.z, 1e-4), 1.0)
        )
    }

    /// 필름 프리셋 Dmin 투과율에 광원 게인을 적용한 유효 투과율. (0, 1] 클램프.
    public func effectiveDminTransmission(for stock: FilmStockDmin) -> SIMD3<Double> {
        applyGain(to: stock.dminTransmission)
    }
}

public enum LightSourceProfileRegistry {
    /// 중립(보정 없음). UI에서 nil(선택 안 함)과 동일하게 동작한다.
    public static let neutral = LightSourceProfile(
        id: "neutral", displayName: "Neutral (5000–5500K)", gain: SIMD3(1.0, 1.0, 1.0))

    // 경향 기반 시작점(±10% 이내 보수적). 정밀 보정은 실측 base가 대신한다.
    public static let all: [LightSourceProfile] = [
        neutral,
        .init(id: "white-led", displayName: "White LED (high CRI)", gain: SIMD3(0.98, 1.00, 1.04)),
        .init(id: "warm-led", displayName: "Warm LED (~3500K)", gain: SIMD3(1.06, 1.00, 0.92)),
        .init(id: "halogen", displayName: "Halogen / Tungsten (~3200K)", gain: SIMD3(1.09, 1.00, 0.88)),
        .init(id: "fluorescent", displayName: "Fluorescent (CCFL)", gain: SIMD3(0.97, 1.03, 1.00)),
    ]

    public static func find(_ id: String?) -> LightSourceProfile? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// 실측 베이스와 필름 프리셋 Dmin으로부터 (스캐너 × 광원) 보정 게인을 역산한다.
    /// 같은 스캐너/광원 조합에서 재사용하면 베이스가 안 보이는 컷에도 실측 수준의 Dmin을 얻는다.
    public static func calibratedGain(measuredBase: SIMD3<Double>,
                                      stock: FilmStockDmin) -> SIMD3<Double> {
        let t = stock.dminTransmission
        func ratio(_ measured: Double, _ reference: Double) -> Double {
            guard reference > 1e-6, measured > 1e-6 else { return 1.0 }
            return min(max(measured / reference, 0.25), 4.0)
        }
        return SIMD3(ratio(measuredBase.x, t.x), ratio(measuredBase.y, t.y), ratio(measuredBase.z, t.z))
    }
}
