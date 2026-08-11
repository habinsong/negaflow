import Chromabase

/// IR(적외선) 결함 제거를 걸 수 있는 필름인지.
///
/// 판정 기준은 **은이 남아 있는가** 하나다. 적외선 채널이 결함만 비추려면 화상을 이루는 물질이
/// 적외선을 통과시켜야 한다. 컬러 필름은 현상 과정에서 은을 표백해 없애고 색소만 남으며, 색소는
/// 적외선에 투명하다 — 네거티브든 슬라이드(E-6)든 마찬가지다. 반면 흑백 필름은 화상 자체가
/// 은입자라 적외선을 그대로 막는다. 그 상태로 IR 보정을 돌리면 사진이 통째로 결함으로 잡혀
/// 지워지므로 열어 주지 않는다.
enum InfraredFilmCompatibility: Equatable {
    /// 색소로 화상을 만드는 필름 — 컬러 네거티브와 컬러 슬라이드.
    case dyeImage
    /// 은으로 화상을 만드는 필름 — 흑백. 적외선이 통과하지 않는다.
    case silverImage

    init(filmType: FilmType) {
        switch filmType {
        case .colorNegative, .colorPositive:
            self = .dyeImage
        case .bwNegative, .bwPositive:
            self = .silverImage
        }
    }

    var allowsAutomaticCorrection: Bool {
        self == .dyeImage
    }
}
