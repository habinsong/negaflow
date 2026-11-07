import CoreGraphics
import Foundation
import simd

/// 변환(원근) 보정 모드. `off` 외의 자동 모드는 고르는 순간 사진의 곧은 선을 한 번 찾아 풀고,
/// 그 결과를 `solved*` 에 저장한다 — 렌더는 선을 다시 찾지 않으므로 같은 값이면 같은 그림이다.
public enum PerspectiveMode: String, Codable, Sendable, CaseIterable {
    case off
    case auto
    case guided
    case level
    case vertical
    case full
}

/// 도우미 모드에서 사용자가 그린 안내선. 좌표는 회전·뒤집기 뒤, 원근 보정 앞의 정규좌표(y 아래).
public struct PerspectiveGuide: Codable, Sendable, Equatable, Hashable {
    public var start: CGPoint
    public var end: CGPoint

    public init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
    }
}

/// 변환 패널의 값. 원근은 가상의 카메라를 돌린 호모그래피 `K·R·K⁻¹` 로 만들고, 그 뒤에 종횡비·
/// 비율·오프셋을 평면에서 얹는다. 회전 `R` 은 축-각 벡터(라디안)로 만든다 — 축-각은 화면 회전·
/// 뒤집기로 옮길 때 성분을 바꾸고 부호만 뒤집으면 정확히 같은 보정이 된다(오일러 각은 순서 때문에
/// 근사가 된다).
public struct PerspectiveCorrection: Codable, Sendable, Equatable, Hashable {
    public var mode: PerspectiveMode
    /// 모드가 푼 회전(도). 가로축(수직 원근)·세로축(수평 원근)·화면축(회전).
    public var solvedVertical: Double
    public var solvedHorizontal: Double
    public var solvedRotate: Double
    /// 슬라이더. 수직·수평 −100…100, 회전 −10…10(도), 종횡비 −100…100, 비율 50…150(%),
    /// 오프셋 −100…100.
    public var vertical: Double
    public var horizontal: Double
    public var rotate: Double
    public var aspect: Double
    public var scale: Double
    public var offsetX: Double
    public var offsetY: Double
    /// 켜면 보정 뒤 빈 곳이 없도록 그림 안의 가장 큰 사각형(원래 비율)으로 자른다.
    public var constrainCrop: Bool
    public var guides: [PerspectiveGuide]

    public static let sliderRange: ClosedRange<Double> = -100...100
    public static let rotateRange: ClosedRange<Double> = -10...10
    public static let scaleRange: ClosedRange<Double> = 50...150
    public static let maximumGuides = 4

    public init(
        mode: PerspectiveMode = .off,
        solvedVertical: Double = 0,
        solvedHorizontal: Double = 0,
        solvedRotate: Double = 0,
        vertical: Double = 0,
        horizontal: Double = 0,
        rotate: Double = 0,
        aspect: Double = 0,
        scale: Double = 100,
        offsetX: Double = 0,
        offsetY: Double = 0,
        constrainCrop: Bool = false,
        guides: [PerspectiveGuide] = []
    ) {
        self.mode = mode
        self.solvedVertical = solvedVertical
        self.solvedHorizontal = solvedHorizontal
        self.solvedRotate = solvedRotate
        self.vertical = vertical
        self.horizontal = horizontal
        self.rotate = rotate
        self.aspect = aspect
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.constrainCrop = constrainCrop
        self.guides = guides
    }

    enum CodingKeys: String, CodingKey {
        case mode, solvedVertical, solvedHorizontal, solvedRotate
        case vertical, horizontal, rotate, aspect, scale, offsetX, offsetY, constrainCrop, guides
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys, _ fallback: Double, _ range: ClosedRange<Double>? = nil) throws -> Double {
            let value = try c.decodeIfPresent(Double.self, forKey: key) ?? fallback
            guard value.isFinite else { return fallback }
            return range.map { min(max(value, $0.lowerBound), $0.upperBound) } ?? value
        }
        mode = (try? c.decodeIfPresent(PerspectiveMode.self, forKey: .mode)) ?? .off
        solvedVertical = try number(.solvedVertical, 0, -PerspectiveGeometry.maximumSolvedDegrees...PerspectiveGeometry.maximumSolvedDegrees)
        solvedHorizontal = try number(.solvedHorizontal, 0, -PerspectiveGeometry.maximumSolvedDegrees...PerspectiveGeometry.maximumSolvedDegrees)
        solvedRotate = try number(.solvedRotate, 0, -45...45)
        vertical = try number(.vertical, 0, Self.sliderRange)
        horizontal = try number(.horizontal, 0, Self.sliderRange)
        rotate = try number(.rotate, 0, Self.rotateRange)
        aspect = try number(.aspect, 0, Self.sliderRange)
        scale = try number(.scale, 100, Self.scaleRange)
        offsetX = try number(.offsetX, 0, Self.sliderRange)
        offsetY = try number(.offsetY, 0, Self.sliderRange)
        constrainCrop = try c.decodeIfPresent(Bool.self, forKey: .constrainCrop) ?? false
        guides = Array((try c.decodeIfPresent([PerspectiveGuide].self, forKey: .guides) ?? [])
            .filter { $0.start.x.isFinite && $0.start.y.isFinite && $0.end.x.isFinite && $0.end.y.isFinite }
            .prefix(Self.maximumGuides))
    }

    public static let identity = PerspectiveCorrection()

    /// 그림을 바꾸는가. 모드·안내선만 있고 값이 0 이면 바꾸지 않는다.
    public var changesGeometry: Bool {
        let rotation = PerspectiveGeometry.rotationVector(for: self)
        return simd_length(rotation) > 1e-7
            || abs(aspect) > 1e-6
            || abs(scale - 100) > 1e-6
            || abs(offsetX) > 1e-6
            || abs(offsetY) > 1e-6
    }

    public var isIdentity: Bool { self == .identity }

    /// 원본이 닿지 않는 빈 곳이 결과에 남는가. 자르기 제한을 켜면 그림 안의 사각형만 남아 빈 곳이 없다.
    public var leavesUncoveredArea: Bool { changesGeometry && !constrainCrop }

    // MARK: 화면 방향이 바뀔 때 같은 보정 유지

    /// 화면 기준 좌우 뒤집기. 축-각 벡터는 거울에 대해 `ω' = −M·ω` 로 바뀐다.
    public func mirroredHorizontally() -> PerspectiveCorrection {
        var next = self
        next.solvedHorizontal = -solvedHorizontal
        next.solvedRotate = -solvedRotate
        next.horizontal = -horizontal
        next.rotate = -rotate
        next.offsetX = -offsetX
        next.guides = guides.map {
            PerspectiveGuide(start: CGPoint(x: 1 - $0.start.x, y: $0.start.y),
                             end: CGPoint(x: 1 - $0.end.x, y: $0.end.y))
        }
        return next
    }

    public func mirroredVertically() -> PerspectiveCorrection {
        var next = self
        next.solvedVertical = -solvedVertical
        next.solvedRotate = -solvedRotate
        next.vertical = -vertical
        next.rotate = -rotate
        next.offsetY = -offsetY
        next.guides = guides.map {
            PerspectiveGuide(start: CGPoint(x: $0.start.x, y: 1 - $0.start.y),
                             end: CGPoint(x: $0.end.x, y: 1 - $0.end.y))
        }
        return next
    }

    /// 화면 기준 90° 회전. 회전축이 함께 돈다: 시계방향이면 (가로축, 세로축) → (−세로축, 가로축).
    public func rotatedQuarterTurn(clockwise: Bool) -> PerspectiveCorrection {
        var next = self
        let s: Double = clockwise ? 1 : -1
        next.solvedVertical = -s * solvedHorizontal
        next.solvedHorizontal = s * solvedVertical
        next.vertical = -s * horizontal
        next.horizontal = s * vertical
        next.aspect = -aspect
        next.offsetX = -s * offsetY
        next.offsetY = s * offsetX
        next.guides = guides.map { guide in
            func turn(_ p: CGPoint) -> CGPoint {
                clockwise ? CGPoint(x: 1 - p.y, y: p.x) : CGPoint(x: p.y, y: 1 - p.x)
            }
            return PerspectiveGuide(start: turn(guide.start), end: turn(guide.end))
        }
        return next
    }
}

/// 원근 보정의 셈. 좌표는 모두 픽셀(y 아래)이며, 입력과 출력 캔버스는 같은 크기다.
public enum PerspectiveGeometry {
    /// 가상 카메라 초점거리(긴 변의 절반 = 1). 카메라 보정으로 추정하지 않는 고정값이다 — 원근을
    /// 펴는 데는 어떤 초점거리든 쓸 수 있고, 남는 세로 늘어남은 종횡비 슬라이더로 맞춘다.
    public static let focalLength = 1.2
    /// 수직·수평 슬라이더 100 이 주는 회전(도).
    public static let sliderDegrees = 35.0
    /// 자동 모드가 풀 수 있는 원근 회전의 한계(도).
    public static let maximumSolvedDegrees = 40.0
    /// 모서리가 카메라 뒤로 넘어가는 값은 그리지 않는다.
    static let minimumDepth = 0.05

    /// 라디안 축-각 벡터 (가로축, 세로축, 화면축).
    public static func rotationVector(for c: PerspectiveCorrection) -> SIMD3<Double> {
        let degrees = SIMD3(
            c.solvedVertical + c.vertical / 100 * sliderDegrees,
            c.solvedHorizontal + c.horizontal / 100 * sliderDegrees,
            c.solvedRotate + c.rotate
        )
        return degrees * (.pi / 180)
    }

    /// 로드리게스 공식. y 아래 카메라 좌표(x 오른쪽, y 아래, z 앞).
    static func rotationMatrix(_ w: SIMD3<Double>) -> simd_double3x3 {
        let angle = simd_length(w)
        guard angle > 1e-12 else { return matrix_identity_double3x3 }
        let k = w / angle
        let kx = simd_double3x3(rows: [
            SIMD3(0, -k.z, k.y),
            SIMD3(k.z, 0, -k.x),
            SIMD3(-k.y, k.x, 0),
        ])
        return matrix_identity_double3x3 + sin(angle) * kx + (1 - cos(angle)) * (kx * kx)
    }

    /// 픽셀 → 픽셀 호모그래피(정규화·회전·평면 조정 포함). 값이 그림을 바꾸지 않으면 nil.
    public static func homography(for c: PerspectiveCorrection, size: CGSize) -> simd_double3x3? {
        guard c.changesGeometry, size.width > 1, size.height > 1 else { return nil }
        let w = Double(size.width), h = Double(size.height)
        let s = max(w, h) / 2
        let toNormal = simd_double3x3(rows: [
            SIMD3(1 / s, 0, -w / 2 / s),
            SIMD3(0, 1 / s, -h / 2 / s),
            SIMD3(0, 0, 1),
        ])
        let toPixel = simd_double3x3(rows: [
            SIMD3(s, 0, w / 2),
            SIMD3(0, s, h / 2),
            SIMD3(0, 0, 1),
        ])
        let f = focalLength
        let k = simd_double3x3(rows: [SIMD3(f, 0, 0), SIMD3(0, f, 0), SIMD3(0, 0, 1)])
        let kInverse = simd_double3x3(rows: [SIMD3(1 / f, 0, 0), SIMD3(0, 1 / f, 0), SIMD3(0, 0, 1)])
        let rotation = rotationMatrix(rotationVector(for: c))
        let stretch = pow(2, c.aspect / 200)
        let zoom = c.scale / 100
        let planar = simd_double3x3(rows: [
            SIMD3(zoom * stretch, 0, c.offsetX / 100 * 0.5),
            SIMD3(0, zoom / stretch, c.offsetY / 100 * 0.5),
            SIMD3(0, 0, 1),
        ])
        // 카메라를 기울이면 그림 중심도 옮겨 간다(세로 15° 면 높이의 24%). 그대로 두면 건물 꼭대기처럼
        // 바로 세운 쪽이 프레임 밖으로 밀리고 반대쪽에 빈 영역이 생긴다. 보정한 그림의 중심을 프레임
        // 가운데로 되돌린다 — 직선은 그대로 직선이고 각도도 변하지 않는다. 회전만 하면 이동은 0 이다.
        let tilt = k * rotation * kInverse
        let center = tilt * SIMD3(0, 0, 1)
        let recenter = center.z > minimumDepth
            ? simd_double3x3(rows: [
                SIMD3(1, 0, -center.x / center.z),
                SIMD3(0, 1, -center.y / center.z),
                SIMD3(0, 0, 1),
            ])
            : matrix_identity_double3x3
        return toPixel * planar * recenter * tilt * toNormal
    }

    public static func apply(_ m: simd_double3x3, _ p: CGPoint) -> CGPoint? {
        let v = m * SIMD3(Double(p.x), Double(p.y), 1)
        guard abs(v.z) > 1e-12 else { return nil }
        let x = v.x / v.z, y = v.y / v.z
        guard x.isFinite, y.isFinite else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// 한 사진에 대한 원근 보정의 정역 매핑과 출력 사각형.
    public struct Mapping {
        public let size: CGSize
        public let forward: simd_double3x3
        public let inverse: simd_double3x3
        /// 출력에서 남길 픽셀 사각형(y 아래). 자르기 제한이 꺼져 있으면 캔버스 전체다.
        public let outputRect: CGRect
        /// 보정한 그림의 네 모서리(y 아래, 좌상·우상·우하·좌하).
        public let corners: [CGPoint]

        /// 입력 정규좌표(y 아래) → 출력 사각형 기준 정규좌표.
        public func forwardUnit(_ p: CGPoint) -> CGPoint? {
            guard let q = PerspectiveGeometry.apply(
                forward,
                CGPoint(x: p.x * size.width, y: p.y * size.height)
            ) else { return nil }
            return CGPoint(
                x: (q.x - outputRect.minX) / outputRect.width,
                y: (q.y - outputRect.minY) / outputRect.height
            )
        }

        public func inverseUnit(_ p: CGPoint) -> CGPoint? {
            let q = CGPoint(
                x: outputRect.minX + p.x * outputRect.width,
                y: outputRect.minY + p.y * outputRect.height
            )
            guard let r = PerspectiveGeometry.apply(inverse, q) else { return nil }
            return CGPoint(x: r.x / size.width, y: r.y / size.height)
        }
    }

    /// 보정이 없거나, 모서리가 카메라 뒤로 넘어가 그릴 수 없는 값이면 nil(그림을 그대로 둔다).
    public static func mapping(for c: PerspectiveCorrection, size: CGSize) -> Mapping? {
        guard let forward = homography(for: c, size: size) else { return nil }
        let w = Double(size.width), h = Double(size.height)
        let source = [CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0), CGPoint(x: w, y: h), CGPoint(x: 0, y: h)]
        var corners: [CGPoint] = []
        for point in source {
            let v = forward * SIMD3(Double(point.x), Double(point.y), 1)
            guard v.z > minimumDepth, let mapped = apply(forward, point) else { return nil }
            corners.append(mapped)
        }
        let inverse = forward.inverse
        guard inverse.columns.0.x.isFinite, inverse.columns.2.z.isFinite else { return nil }
        let canvas = CGRect(origin: .zero, size: size)
        let outputRect: CGRect
        if c.constrainCrop {
            guard let inscribed = inscribedRect(
                in: corners,
                canvas: canvas,
                center: apply(forward, CGPoint(x: w / 2, y: h / 2)) ?? CGPoint(x: w / 2, y: h / 2)
            ) else { return nil }
            outputRect = inscribed
        } else {
            outputRect = canvas
        }
        return Mapping(size: size, forward: forward, inverse: inverse, outputRect: outputRect, corners: corners)
    }

    /// 볼록 사각형 `quad` 와 캔버스 안에 들어가는, 캔버스와 같은 비율의 가장 큰 사각형. 중심은
    /// 보정한 그림의 중심에 두되 캔버스 밖이면 캔버스 안으로 당긴다. 정수 화소로 줄여 돌려준다.
    static func inscribedRect(in quad: [CGPoint], canvas: CGRect, center rawCenter: CGPoint) -> CGRect? {
        let center = CGPoint(
            x: min(max(rawCenter.x, canvas.minX + 1), canvas.maxX - 1),
            y: min(max(rawCenter.y, canvas.minY + 1), canvas.maxY - 1)
        )
        guard contains(quad, center) else { return nil }
        let aspect = canvas.width / canvas.height
        func fits(_ halfHeight: CGFloat) -> Bool {
            let halfWidth = halfHeight * aspect
            let rect = CGRect(x: center.x - halfWidth, y: center.y - halfHeight,
                              width: halfWidth * 2, height: halfHeight * 2)
            guard canvas.insetBy(dx: -1e-6, dy: -1e-6).contains(rect) else { return false }
            return [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
                .allSatisfy { contains(quad, $0) }
        }
        var low: CGFloat = 0, high = canvas.height / 2
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if fits(mid) { low = mid } else { high = mid }
        }
        let halfHeight = low, halfWidth = low * aspect
        guard halfHeight >= 4, halfWidth >= 4 else { return nil }
        let rect = CGRect(x: center.x - halfWidth, y: center.y - halfHeight,
                          width: halfWidth * 2, height: halfHeight * 2)
        // 바깥 화소가 섞이지 않도록 안쪽 정수 경계로 줄인다.
        let x0 = ceil(rect.minX), y0 = ceil(rect.minY)
        let x1 = floor(rect.maxX), y1 = floor(rect.maxY)
        guard x1 - x0 >= 8, y1 - y0 >= 8 else { return nil }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// 볼록 다각형 안(경계 포함)인가. 꼭짓점 차례는 시계·반시계 어느 쪽이든 된다.
    static func contains(_ polygon: [CGPoint], _ p: CGPoint) -> Bool {
        var sign: CGFloat = 0
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if abs(cross) < 1e-9 { continue }
            if sign == 0 { sign = cross > 0 ? 1 : -1 } else if (cross > 0 ? 1 : -1) != sign { return false }
        }
        return true
    }
}
