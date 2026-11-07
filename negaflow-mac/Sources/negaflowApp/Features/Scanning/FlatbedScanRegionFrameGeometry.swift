import Chromabase
import CoreGraphics
import Foundation

/// 화면 위 회전된 사각형. 캔버스 좌표(포인트)이며 `angle` 은 라디안, 화면 기준 시계방향이 양수다.
struct FlatbedRegionScreenShape: Equatable {
    var center: CGPoint
    var size: CGSize
    var angle: CGFloat

    /// 사각형 자기 좌표(왼쪽 위 원점, 0...width × 0...height)를 캔버스 좌표로.
    func screenPoint(local: CGPoint) -> CGPoint {
        let dx = local.x - size.width / 2
        let dy = local.y - size.height / 2
        let c = cos(angle), s = sin(angle)
        return CGPoint(x: center.x + dx * c - dy * s, y: center.y + dx * s + dy * c)
    }

    /// 캔버스 좌표를 사각형 자기 좌표로.
    func localPoint(screen: CGPoint) -> CGPoint {
        let dx = screen.x - center.x
        let dy = screen.y - center.y
        let c = cos(angle), s = sin(angle)
        return CGPoint(
            x: dx * c + dy * s + size.width / 2,
            y: -dx * s + dy * c + size.height / 2
        )
    }

    /// 자기 좌표의 사각형을 같은 회전으로 캔버스에 놓는다.
    func reshaped(localRect: CGRect) -> FlatbedRegionScreenShape {
        FlatbedRegionScreenShape(
            center: screenPoint(local: CGPoint(x: localRect.midX, y: localRect.midY)),
            size: localRect.size,
            angle: angle
        )
    }

    var corners: [CGPoint] {
        [
            screenPoint(local: CGPoint(x: 0, y: 0)),
            screenPoint(local: CGPoint(x: size.width, y: 0)),
            screenPoint(local: CGPoint(x: size.width, y: size.height)),
            screenPoint(local: CGPoint(x: 0, y: size.height)),
        ]
    }

    var boundingRect: CGRect {
        FlatbedScanRegionFrameGeometry.boundingRect(of: corners)
    }
}

/// 프레임 하나는 스캔할 물리 영역(base 좌표의 축 정렬 사각형 `unitRect`)과 그 안에서 기울어진
/// 필름 칸(`straightenAngle`)을 함께 들고 있다. 스캔 결과는 이 각도만큼 펴고 같은 비율의 최대
/// 내접 사각형으로 잘린다(`ImageTransformStage`). 여기서는 그 기울어진 칸을 base·화면 좌표로
/// 오간다.
///
/// 경계 상자(`unitRect`)를 그대로 화면에 옮기면, 각도가 들어간 프리뷰에서는 상자가 실제보다
/// 커 보이고 그 상자를 base 로 되돌리면 또 커진다. 프레임을 누를 때마다 커지던 원인이 이
/// 왕복이었다. 칸 자체를 오가면 왕복이 정확하다.
enum FlatbedScanRegionFrameGeometry {
    /// 화면에서 수평으로 보이는 칸이 base 에서 가져야 할 각도. 프리뷰가 뒤집혀 있으면(가로·세로
    /// 중 하나만) 같은 회전이 base 에서는 반대 방향이다 — 스캔 결과에 각도를 걸 때도 같은 규칙으로
    /// 되돌린다(`AppModel+FullScanPlan`).
    static func regionAngle(matching transform: ImageTransform) -> Double {
        let angle = transform.straightenAngle
        guard angle.isFinite else { return 0 }
        let clamped = min(max(angle, -45), 45)
        return transform.flipHorizontal != transform.flipVertical ? -clamped : clamped
    }

    /// 칸의 네 모서리(base 정규좌표, y 아래). 차례는 칸 기준 좌상·우상·우하·좌하.
    ///
    /// 경계 상자 `Wb×Hb` 와 각도 α 로 칸 `W×H` 를 푼다(픽셀 공간):
    /// `Wb = W·|cos α| + H·|sin α|`, `Hb = W·|sin α| + H·|cos α|`.
    /// 칸의 가로 변은 y 아래 좌표에서 −α 방향이다 — 시계방향 α 로 펴면 수평이 된다.
    static func frameCorners(
        unitRect: CGRect,
        straightenAngle: Double,
        baseSize: CGSize?
    ) -> [CGPoint] {
        let axis = axisCorners(unitRect)
        guard abs(straightenAngle) > 1e-4,
              straightenAngle.isFinite,
              let baseSize,
              baseSize.width > 0,
              baseSize.height > 0 else { return axis }
        let pixelWidth = Double(baseSize.width)
        let pixelHeight = Double(baseSize.height)
        let boundsWidth = Double(unitRect.width) * pixelWidth
        let boundsHeight = Double(unitRect.height) * pixelHeight
        let radians = straightenAngle * .pi / 180
        let c = abs(cos(radians)), s = abs(sin(radians))
        let determinant = c * c - s * s
        guard determinant > 1e-6 else { return axis }
        let width = (boundsWidth * c - boundsHeight * s) / determinant
        let height = (boundsHeight * c - boundsWidth * s) / determinant
        guard width > 0, height > 0 else { return axis }
        let centerX = Double(unitRect.midX) * pixelWidth
        let centerY = Double(unitRect.midY) * pixelHeight
        let along = (x: cos(radians) * width / 2, y: -sin(radians) * width / 2)
        let across = (x: sin(radians) * height / 2, y: cos(radians) * height / 2)
        let signs: [(Double, Double)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        return signs.map { a, b in
            CGPoint(
                x: (centerX + a * along.x + b * across.x) / pixelWidth,
                y: (centerY + a * along.y + b * across.y) / pixelHeight
            )
        }
    }

    /// base 칸 → 화면 위 회전 사각형.
    static func screenShape(
        unitRect: CGRect,
        straightenAngle: Double,
        transform: ImageTransform,
        baseSize: CGSize?,
        imageFrame: CGRect
    ) -> FlatbedRegionScreenShape {
        let points = frameCorners(
            unitRect: unitRect,
            straightenAngle: straightenAngle,
            baseSize: baseSize
        ).map { point -> CGPoint in
            let display = transform.baseUnitToDisplay(point, baseSize: baseSize)
            return CGPoint(
                x: imageFrame.minX + display.x * imageFrame.width,
                y: imageFrame.minY + display.y * imageFrame.height
            )
        }
        return shape(fromScreenCorners: points)
    }

    /// 화면 사각형(회전 포함)을 base 프레임으로. 각도는 그대로 두고 경계 상자만 새로 잰다 — 칸의
    /// 네 모서리가 이미 그 각도로 기울어 있으므로 상자에서 다시 풀면 같은 칸이 나온다.
    static func unitRect(
        for shape: FlatbedRegionScreenShape,
        transform: ImageTransform,
        baseSize: CGSize?,
        imageFrame: CGRect
    ) -> CGRect {
        let corners = shape.corners.map { point -> CGPoint in
            let display = CGPoint(
                x: (point.x - imageFrame.minX) / max(imageFrame.width, 1),
                y: (point.y - imageFrame.minY) / max(imageFrame.height, 1)
            )
            return transform.displayUnitToBase(display, baseSize: baseSize)
        }
        return boundingRect(of: corners)
    }

    /// 칸을 자기 방향으로 눕힌 정규 사각형. 규격 비율 맞춤과 다음 칸 제안이 이 좌표에서 돈다 —
    /// 픽셀을 칸 각도만큼 펴면 mm 길이가 그대로이므로 기존 셈을 그대로 쓸 수 있다.
    static func frameLocalRect(
        unitRect: CGRect,
        straightenAngle: Double,
        localAngle: Double,
        baseSize: CGSize?
    ) -> CGRect {
        // 기울기가 없으면 모서리를 거치지 않는다. 모서리로 돌아오면 폭이 (x+w)−x 로 다시 재져
        // 0.091 이 0.09099999… 가 되는 식의 오차가 붙는다.
        if abs(straightenAngle) <= 1e-4, abs(localAngle) <= 1e-4 { return unitRect }
        let corners = frameCorners(
            unitRect: unitRect,
            straightenAngle: straightenAngle,
            baseSize: baseSize
        )
        return boundingRect(of: corners.map {
            rotate($0, degrees: localAngle, baseSize: baseSize)
        })
    }

    /// `frameLocalRect` 의 역: 눕힌 사각형을 각도만큼 다시 기울여 base 경계 상자로.
    static func unitRect(
        fromFrameLocal localRect: CGRect,
        localAngle: Double,
        baseSize: CGSize?
    ) -> CGRect {
        if abs(localAngle) <= 1e-4 { return localRect }
        return boundingRect(of: axisCorners(localRect).map {
            rotate($0, degrees: -localAngle, baseSize: baseSize)
        })
    }

    /// 네 점을 화면 기준으로 가장 덜 기운 회전 사각형으로 읽는다. 뒤집기·90° 회전이 모서리 차례를
    /// 바꿔도 가로축은 늘 오른쪽, 세로축은 늘 아래를 향하게 고른다.
    static func shape(fromScreenCorners points: [CGPoint]) -> FlatbedRegionScreenShape {
        guard points.count == 4 else {
            return FlatbedRegionScreenShape(center: .zero, size: .zero, angle: 0)
        }
        let center = CGPoint(
            x: points.map(\.x).reduce(0, +) / 4,
            y: points.map(\.y).reduce(0, +) / 4
        )
        let u = CGPoint(x: points[1].x - points[0].x, y: points[1].y - points[0].y)
        let v = CGPoint(x: points[3].x - points[0].x, y: points[3].y - points[0].y)
        let candidates = [u, v, CGPoint(x: -u.x, y: -u.y), CGPoint(x: -v.x, y: -v.y)]
        let index = candidates.indices.max { candidates[$0].x < candidates[$1].x } ?? 0
        let xAxis = candidates[index]
        let other = index % 2 == 0 ? v : u
        let yAxis = other.y >= 0 ? other : CGPoint(x: -other.x, y: -other.y)
        return FlatbedRegionScreenShape(
            center: center,
            size: CGSize(width: hypot(xAxis.x, xAxis.y), height: hypot(yAxis.x, yAxis.y)),
            angle: atan2(xAxis.y, xAxis.x)
        )
    }

    static func boundingRect(of points: [CGPoint]) -> CGRect {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else {
            return .zero
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func axisCorners(_ rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]
    }

    /// base 정규좌표의 점을 픽셀 공간에서 그림 중심 기준으로 돌린다(y 아래, 양수 = 시계방향).
    private static func rotate(_ point: CGPoint, degrees: Double, baseSize: CGSize?) -> CGPoint {
        guard abs(degrees) > 1e-4,
              let baseSize,
              baseSize.width > 0,
              baseSize.height > 0 else { return point }
        let width = Double(baseSize.width), height = Double(baseSize.height)
        let radians = degrees * .pi / 180
        let c = cos(radians), s = sin(radians)
        let dx = Double(point.x) * width - width / 2
        let dy = Double(point.y) * height - height / 2
        return CGPoint(
            x: (width / 2 + dx * c - dy * s) / width,
            y: (height / 2 + dx * s + dy * c) / height
        )
    }
}
