import Foundation
import CoreImage
import CoreGraphics

// MARK: - FilmBasePicker (베이스 스포이드 샘플링)
//
// 사용자가 캔버스에서 미노광 필름 베이스(프레임 사이/가장자리)를 클릭하면, 그 주변 영역을
// linear 공간에서 평균해 Dmin 투과율로 쓴다 — 업계 도구들의 D-min/film-base picker 와
// 동일한 의미론(절대값).
public enum FilmBasePicker {
    /// 로컬 스냅 창 한 변 = 짧은 변 × 이 값. 멀티 스트립 스캔에서 베이스 띠는 화면상 몇
    /// px 두께라 클릭 정밀도가 픽 결과를 좌우했다("찍을 때마다 랜덤") — 클릭 주변 창에서
    /// 베이스 연결 성분을 찾아 스냅하면 조준 오차·퍼포레이션/백라이트 인접이 무해해진다.
    static let snapWindowFraction = 0.12

    /// raw 스캔(반전 전, linear)에서 클릭 지점의 베이스 RGB 를 반환한다.
    /// 1차: 클릭 주변 로컬 창에서 베이스 연결 성분 검출(조준 오차 허용) —
    ///      FilmBaseEstimator.connectedBaseComponent 와 같은 물리 불변량.
    /// 2차: 성분이 없으면 기존 영역 중앙값(절대값 semantics — 업계 D-min picker).
    /// - Parameters:
    ///   - unit: 0...1 정규좌표, y-down(화면 관례). CIImage(y-up) 좌표로 변환해 샘플한다.
    ///   - regionFraction: 폴백 샘플 영역 한 변 = 짧은 변 × 이 값(최소 3px).
    ///   - neutralBase: B&W 네거티브(중립 베이스) 여부 — 후보 판정에 사용.
    public static func sample(in image: CIImage,
                              atUnit unit: CGPoint,
                              regionFraction: Double = 0.01,
                              neutralBase: Bool = false) -> SIMD3<Double>? {
        let extent = image.extent
        guard extent.width > 2, extent.height > 2 else { return nil }
        let u = min(max(unit.x, 0), 1)
        let v = min(max(unit.y, 0), 1)
        let cx = extent.minX + u * extent.width
        let cy = extent.minY + (1.0 - v) * extent.height   // y-down → y-up

        if let snapped = snapToBase(in: image, centerX: cx, centerY: cy, neutralBase: neutralBase) {
            return snapped
        }

        let side = max(3.0, Double(min(extent.width, extent.height)) * regionFraction)
        let half = side / 2
        // 정수 경계로 스냅: 소수점 origin 영역은 CIAreaAverage 가 정수 그리드로 샘플하며
        // 영역 밖 투명 픽셀을 섞어 알파 < 1 로 희석된 평균을 낸다(실측: 0.8 → 0.45).
        let region = CGRect(x: cx - half, y: cy - half, width: side, height: side)
            .integral
            .intersection(extent.integral)
        guard !region.isEmpty, region.width >= 1, region.height >= 1 else { return nil }
        // 평균이 아니라 채널별 **중앙값**: 베이스 위 엣지 마킹 글자/바코드/먼지/퍼포레이션이
        // 영역에 걸치면 평균은 어두운(또는 밝은) 쪽으로 끌려가 잘못된 Dmin 이 된다.
        let rgb = medianRGB(of: image.cropped(to: region), region: region)
        guard let rgb, rgb.x.isFinite, rgb.y.isFinite, rgb.z.isFinite,
              rgb.x > 0 || rgb.y > 0 || rgb.z > 0 else { return nil }
        return SIMD3(
            min(max(rgb.x, 0), 1),
            min(max(rgb.y, 0), 1),
            min(max(rgb.z, 0), 1)
        )
    }

    /// 클릭 주변 로컬 창에서 베이스 연결 성분을 찾아 그 채널 중앙값으로 스냅한다.
    /// 창 안에 백라이트/퍼포레이션이 있어도 성분 검출이 물리 불변량으로 걸러낸다.
    static func snapToBase(in image: CIImage,
                           centerX: CGFloat, centerY: CGFloat,
                           neutralBase: Bool) -> SIMD3<Double>? {
        let extent = image.extent
        let side = Double(min(extent.width, extent.height)) * snapWindowFraction
        guard side >= 48 else { return nil }
        let half = side / 2
        let window = CGRect(x: centerX - half, y: centerY - half, width: side, height: side)
            .integral
            .intersection(extent.integral)
        guard window.width >= 32, window.height >= 32 else { return nil }
        // FilmBaseSampleGrid 는 원점 (0,0) 을 가정한다 — 크롭 창을 원점으로 이동.
        let windowImage = image.cropped(to: window)
            .transformed(by: CGAffineTransform(translationX: -window.minX, y: -window.minY))
        guard let grid = FilmBaseSampleGrid(image: windowImage) else { return nil }
        guard let measurement = FilmBaseEstimator.connectedBaseComponent(
            from: grid, neutralBase: neutralBase
        ) else { return nil }
        let rgb = measurement.rgb
        guard rgb.x.isFinite, rgb.y.isFinite, rgb.z.isFinite else { return nil }
        return SIMD3(
            min(max(rgb.x, 0), 1),
            min(max(rgb.y, 0), 1),
            min(max(rgb.z, 0), 1)
        )
    }

    /// 영역을 linear 로 렌더해 채널별 중앙값을 구한다.
    static func medianRGB(of image: CIImage, region: CGRect) -> SIMD3<Double>? {
        let width = Int(region.width), height = Int(region.height)
        guard width >= 1, height >= 1,
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        var bitmap = [Float](repeating: 0, count: width * height * 4)
        SamplingContextPool.context(workingColorSpace: linear).render(
            image.transformed(by: CGAffineTransform(translationX: -region.minX, y: -region.minY)),
            toBitmap: &bitmap,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        var red: [Double] = [], green: [Double] = [], blue: [Double] = []
        red.reserveCapacity(width * height)
        for i in 0..<(width * height) {
            let r = Double(bitmap[i * 4]), g = Double(bitmap[i * 4 + 1]), b = Double(bitmap[i * 4 + 2])
            guard r.isFinite, g.isFinite, b.isFinite else { continue }
            red.append(r); green.append(g); blue.append(b)
        }
        guard !red.isEmpty else { return nil }
        red.sort(); green.sort(); blue.sort()
        return SIMD3(red[red.count / 2], green[green.count / 2], blue[blue.count / 2])
    }
}
