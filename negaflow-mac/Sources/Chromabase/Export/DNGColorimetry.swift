import Foundation
import simd

// MARK: - DNGRGBSpace
//
// DNG 에 싣는 선형 RGB 데이터는 사용자가 고른 출력 색공간(sRGB · Display P3 · Adobe RGB)의 원색으로
// 해석돼야 한다. DNG 는 색공간 이름이 아니라 "XYZ → 카메라 RGB" 행렬(ColorMatrix1)로 그것을 적으므로,
// 이 파일은 각 공간의 색도 좌표에서 그 행렬과 sRGB 작업공간에서의 변환 행렬을 계산한다.
//
// 색도 좌표는 각 공간의 공개 규격에 적힌 값이다(IEC 61966-2-1 의 sRGB, SMPTE EG 432-1 의 DCI-P3 원색에
// D65 백색점을 붙인 Display P3, Adobe RGB (1998) 규격). 행렬 계산은 원색 xy 에서 RGB→XYZ 를 만드는
// 교과서 방식(원색 열벡터에 백색점을 맞추는 대각 배율)이며, 다른 구현의 표나 코드를 옮기지 않았다.
struct DNGRGBSpace: Equatable {
    /// CIE 1931 xy 색도 좌표.
    let red: SIMD2<Double>
    let green: SIMD2<Double>
    let blue: SIMD2<Double>
    let white: SIMD2<Double>

    /// D65 백색점. 세 출력 색공간이 모두 이 백색점을 쓴다.
    static let d65 = SIMD2(0.3127, 0.3290)

    static let sRGB = DNGRGBSpace(
        red: SIMD2(0.640, 0.330), green: SIMD2(0.300, 0.600), blue: SIMD2(0.150, 0.060), white: d65)
    static let displayP3 = DNGRGBSpace(
        red: SIMD2(0.680, 0.320), green: SIMD2(0.265, 0.690), blue: SIMD2(0.150, 0.060), white: d65)
    static let adobeRGB = DNGRGBSpace(
        red: SIMD2(0.640, 0.330), green: SIMD2(0.210, 0.710), blue: SIMD2(0.150, 0.060), white: d65)

    /// EXIF LightSource 코드로 적은 백색점 이름. DNG 의 CalibrationIlluminant1 이 같은 코드를 쓴다.
    /// 21 = D65.
    static let d65LightSourceCode: UInt16 = 21

    /// 선형 RGB(이 공간) → CIE XYZ(백색점 Y = 1). 열 우선 행렬이다.
    var rgbToXYZ: simd_double3x3 {
        func xyz(_ chromaticity: SIMD2<Double>) -> SIMD3<Double> {
            SIMD3(chromaticity.x / chromaticity.y, 1, (1 - chromaticity.x - chromaticity.y) / chromaticity.y)
        }
        let primaries = simd_double3x3(columns: (xyz(red), xyz(green), xyz(blue)))
        let scale = primaries.inverse * xyz(white)
        return simd_double3x3(columns: (
            primaries.columns.0 * scale.x,
            primaries.columns.1 * scale.y,
            primaries.columns.2 * scale.z
        ))
    }

    /// DNG ColorMatrix1: CIE XYZ(백색점 기준) → 이 공간의 선형 RGB.
    var xyzToRGB: simd_double3x3 { rgbToXYZ.inverse }

    /// 선형 sRGB 값을 이 공간의 선형 RGB 값으로 바꾸는 행렬. 백색점이 같은 공간끼리만 정의된다
    /// (색 적응이 필요 없다). 백색점이 다르면 nil.
    func conversion(fromLinear source: DNGRGBSpace) -> simd_double3x3? {
        guard simd_distance(white, source.white) < 1e-9 else { return nil }
        return xyzToRGB * source.rgbToXYZ
    }
}

extension ExportColorSpace {
    var dngSpace: DNGRGBSpace {
        switch self {
        case .sRGB: return .sRGB
        case .displayP3: return .displayP3
        case .adobeRGB: return .adobeRGB
        }
    }
}
