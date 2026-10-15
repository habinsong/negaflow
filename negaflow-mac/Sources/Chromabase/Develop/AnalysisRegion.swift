import CoreGraphics
import CoreImage
import Foundation

// MARK: - AnalysisRegion
//
// 장면 측정(반전 Dmax, 자동 레벨·색상, 뮤트 채도, 커브 대역, 스캐너 타겟 앵커)을 할 영역.
// 사용자가 크롭한 사진 영역을 변형 전 원본 좌표로 되돌린 것이다.
//
// 왜: 디지털 카메라 스캔은 필름보다 넓게 찍혀 백라이트·홀더·리베이트·이웃 프레임이 함께
// 들어온다. 측정이 크롭 전 전체 프레임을 보면 홀더 가장자리 혼합 화소가 최농부(p0.2)를 차지해
// Dmax 가 채널마다 다르게 잡히고(2026-10-14 실측 R/B 0.72~0.98 캐스트), 자동 레벨은 홀더를
// 화이트포인트로 잡는다(R/B 0.90). 크롭 안에서 재면 같은 프레임이 R/B 1.00 이 된다.
// 베이스는 여기서 찾지 않는다 — 크롭 안에는 필름 베이스가 없다(FilmBaseEstimator 참고).
public struct AnalysisRegion: Sendable, Equatable {
    /// 이미지 extent 에 대한 정규 사각형(0…1, CI 와 같은 y-up).
    public let unitRect: CGRect

    public init?(unitRect: CGRect) {
        let clipped = unitRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clipped.isNull, clipped.width > 0.02, clipped.height > 0.02 else { return nil }
        // 사실상 전체 프레임이면 영역이 없는 것과 같다 — 기존 측정(6% 인셋)을 그대로 쓴다.
        guard clipped.width < 0.999 || clipped.height < 0.999 else { return nil }
        self.unitRect = clipped
    }

    /// 크롭·수평 보정이 있을 때만 영역이 생긴다. 회전·뒤집기만으로는 보이는 내용이 같다.
    /// `imageSize` 는 변형 전 원본의 픽셀 크기(비율만 쓴다 — 수평 보정 역변환에 필요).
    public init?(transform: ImageTransform, imageSize: CGSize) {
        guard transform.cropRect != nil || abs(transform.straightenAngle) > 1e-4,
              imageSize.width > 0, imageSize.height > 0 else { return nil }
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)]
            .map { transform.displayUnitToBase($0, baseSize: imageSize) }
        // 수평 보정이 있으면 표시 사각형은 원본에서 기운 사각형이다. 각 축의 두 번째로 작은 값과
        // 두 번째로 큰 값이 만드는 사각형은 기운 사각형 안에 들어간다(45° 미만) — 크롭 밖이 섞이지 않는다.
        let xs = corners.map(\.x).sorted(), ys = corners.map(\.y).sorted()
        // displayUnitToBase 는 y-down 이다 → CI y-up 으로 뒤집는다.
        self.init(unitRect: CGRect(x: xs[1], y: 1 - ys[2], width: xs[2] - xs[1], height: ys[2] - ys[1]))
    }

    /// 측정 영역을 바꾸는 변형 요소만 남긴 키 — 크롭·수평 보정이 없으면 nil. 종횡비 고정
    /// (cropAspect)은 편집 제약 메타데이터라 픽셀과 무관하므로 뺀다. 같은 프레임(같은 원본 비율)
    /// 에서 키가 같으면 영역도 같다.
    public static func cacheKey(for transform: ImageTransform) -> ImageTransform? {
        guard transform.cropRect != nil || abs(transform.straightenAngle) > 1e-4 else { return nil }
        var key = transform
        key.cropAspect = nil
        return key
    }

    /// 이미지 extent 위의 픽셀 사각형(바깥으로 정수화). 역변환을 거친 경계는 정수에서 1ulp 쯤
    /// 벗어나므로(830.00000000000011) 정수에 1e-6 화소 이내면 그 정수로 본다 — 그대로 올림하면
    /// 사각형이 한 화소 넓어져 크롭 밖이 섞인다. Windows `analysis_measurement_rect` 와 같다.
    public func pixelRect(in extent: CGRect) -> CGRect {
        let snap = 1e-6
        let x0 = (unitRect.minX * extent.width + snap).rounded(.down)
        let x1 = (unitRect.maxX * extent.width - snap).rounded(.up)
        let y0 = (unitRect.minY * extent.height + snap).rounded(.down)
        let y1 = (unitRect.maxY * extent.height - snap).rounded(.up)
        return CGRect(x: extent.minX + x0, y: extent.minY + y0, width: x1 - x0, height: y1 - y0)
            .intersection(extent)
    }

    /// 측정용 이미지 — 영역으로 잘라 원점(0,0)으로 옮긴다. 영역이 없거나 너무 작으면 원본.
    static func measurementImage(_ image: CIImage, region: AnalysisRegion?) -> CIImage {
        guard let region else { return image }
        let rect = region.pixelRect(in: image.extent)
        guard !rect.isNull, rect.width > 8, rect.height > 8 else { return image }
        return image.cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    }
}
