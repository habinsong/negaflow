import Foundation
import CoreImage
import CoreGraphics
import ImageIO

public enum ImageRotation: Int, Codable, Sendable, CaseIterable {
    case deg0 = 0
    case deg90 = 1
    case deg180 = 2
    case deg270 = 3

    public var displayName: String {
        switch self {
        case .deg0: return "0"
        case .deg90: return "90"
        case .deg180: return "180"
        case .deg270: return "270"
        }
    }

    public func rotatedClockwise() -> ImageRotation {
        ImageRotation(rawValue: (rawValue + 1) % 4) ?? .deg0
    }

    public func rotatedCounterClockwise() -> ImageRotation {
        ImageRotation(rawValue: (rawValue + 3) % 4) ?? .deg0
    }
}

public struct ImageTransform: Codable, Sendable, Equatable {
    public var rotation: ImageRotation
    public var flipHorizontal: Bool
    public var flipVertical: Bool
    /// 정규화 crop 사각형 (x, y, w, h ∈ [0,1], post-transform 기준).
    /// nil이면 crop 없음(원본 전체). 색감 엔진과 무관하게 픽셀 단위 crop만.
    public var cropRect: SIMD4<Double>?
    /// 미세 회전(수평 보정) 각도, -45...45도. 0 = 없음. 회전 후 빈 모서리는 자동 크롭한다.
    public var straightenAngle: Double
    /// 크롭 종횡비 고정 값(가로/세로). nil = 자유. 픽셀에는 영향 없고 크롭 편집 제약용 메타데이터.
    public var cropAspect: Double?

    public init(
        rotation: ImageRotation = .deg0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        cropRect: SIMD4<Double>? = nil,
        straightenAngle: Double = 0,
        cropAspect: Double? = nil
    ) {
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.cropRect = cropRect
        self.straightenAngle = straightenAngle
        self.cropAspect = cropAspect
    }

    enum CodingKeys: String, CodingKey {
        case rotation, flipHorizontal, flipVertical, cropRect, straightenAngle, cropAspect
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rotation = try c.decodeIfPresent(ImageRotation.self, forKey: .rotation) ?? .deg0
        flipHorizontal = try c.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? false
        flipVertical = try c.decodeIfPresent(Bool.self, forKey: .flipVertical) ?? false
        cropRect = try c.decodeIfPresent(SIMD4<Double>.self, forKey: .cropRect)
        straightenAngle = try c.decodeIfPresent(Double.self, forKey: .straightenAngle) ?? 0
        cropAspect = try c.decodeIfPresent(Double.self, forKey: .cropAspect)
    }

    public static let identity = ImageTransform()

    public var orientationTemplate: ImageTransform {
        ImageTransform(
            rotation: rotation,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical
        )
    }

    public var isIdentity: Bool {
        rotation == .deg0 && !flipHorizontal && !flipVertical && cropRect == nil
            && abs(straightenAngle) < 1e-4
    }

    /// 변형된(표시) 이미지의 정규좌표(0..1, y 위→아래)를 **변형 전 base** 정규좌표로 역매핑한다.
    /// 브러시/Region ICE 마스크를 transform-독립적인 base 좌표로 저장해, 회전/플립/회전보정/크롭
    /// 후에도 같은 위치에 재적용되도록 한다. forward 순서(flipH→flipV→rotate→straighten→crop)의
    /// 역순으로 푼다.
    /// - baseSize: 변형 전 base 이미지의 픽셀 크기. straighten(미세 회전) 역변환은 내접 크롭 때문에
    ///   픽셀 종횡비가 필요하다. nil이면 straighten 역변환을 건너뛴다(straightenAngle==0이면 무영향;
    ///   하위호환). 정확한 정합이 필요한 호출부는 base 픽셀 크기를 넘긴다.
    public func displayUnitToBase(_ p: CGPoint, baseSize: CGSize? = nil) -> CGPoint {
        var x = Double(p.x), y = Double(p.y)   // y-down normalized on display

        // 1) un-crop: cropRect=(cx, cyUp, cw, ch)는 y-up. 표시점을 회전보정 후(crop 전) 좌표로.
        if let c = cropRect {
            let vUp = 1.0 - y
            let xRot = c.x + x * c.z
            let yUpRot = c.y + vUp * c.w
            x = xRot
            y = 1.0 - yUpRot
        }

        // 2) un-straighten: 중심 기준 회전 + 내접 크롭의 역. straighten 입력(=rotate 출력) 좌표계의
        //    픽셀 크기(sw,sh)가 있어야 정규좌표 회전을 비왜곡으로 풀 수 있다. ImageTransformStage의
        //    applyStraighten(중심 -θ 회전, 같은 종횡비 최대 내접 사각형 크롭)을 정확히 역으로 적용한다.
        if abs(straightenAngle) > 1e-4, let baseSize, baseSize.width > 0, baseSize.height > 0 {
            // rotate(90/270)는 종횡비를 뒤집는다 — straighten은 rotate 다음이므로 swap 후 크기를 쓴다.
            let sw: Double, sh: Double
            switch rotation {
            case .deg90, .deg270: sw = Double(baseSize.height); sh = Double(baseSize.width)
            default:              sw = Double(baseSize.width);  sh = Double(baseSize.height)
            }
            let theta = straightenAngle * .pi / 180.0
            let ct = abs(cos(theta)), st = abs(sin(theta))
            // applyStraighten 의 내접 사각형 크기(wp,hp). (w=sw, h=sh)
            let hp = min(sw * sh / (sw * ct + sh * st), sh * sh / (sw * st + sh * ct))
            let wp = (sw / sh) * hp
            let cx = sw / 2, cy = sh / 2
            // 출력 정규(y-down) → 출력 픽셀(y-up, crop rect 내) → rotated 좌표 픽셀.
            let vUp = 1.0 - y
            let pxp = x * wp + (cx - wp / 2)
            let pyp = vUp * hp + (cy - hp / 2)
            // forward 회전이 R(-θ)이므로 역은 R(+θ): (dx,dy) = R(θ)(P'-c), P = c + (dx,dy).
            let dxp = pxp - cx, dyp = pyp - cy
            let cosT = cos(theta), sinT = sin(theta)
            let dx = dxp * cosT - dyp * sinT
            let dy = dxp * sinT + dyp * cosT
            x = (cx + dx) / sw
            y = 1.0 - (cy + dy) / sh
        }

        // 3) un-rotate (y-down normalized).
        switch rotation {
        case .deg0:   break
        case .deg90:  (x, y) = (y, 1.0 - x)       // inverse of (bx,by)->(1-by, bx)
        case .deg180: (x, y) = (1.0 - x, 1.0 - y)
        case .deg270: (x, y) = (1.0 - y, x)       // inverse of (bx,by)->(by, 1-bx)
        }

        // 4) un-flipV, 5) un-flipH.
        if flipVertical { y = 1.0 - y }
        if flipHorizontal { x = 1.0 - x }

        return CGPoint(x: x, y: y)
    }

    /// base 정규좌표(0..1, y-down) → 표시(변형 후) 정규좌표. displayUnitToBase 의 정역(forward).
    /// Region ICE 가 base 좌표 컴포넌트를 화면에 빨강으로 표시할 때 쓴다. 순서는 forward
    /// (flipH→flipV→rotate→straighten→crop). straighten 은 픽셀 종횡비가 필요하므로 baseSize 를 받는다.
    public func baseUnitToDisplay(_ p: CGPoint, baseSize: CGSize? = nil) -> CGPoint {
        var x = Double(p.x), y = Double(p.y)

        // 1) flipH, 2) flipV
        if flipHorizontal { x = 1.0 - x }
        if flipVertical { y = 1.0 - y }

        // 3) rotate (base→display, y-down normalized).
        switch rotation {
        case .deg0:   break
        case .deg90:  (x, y) = (1.0 - y, x)       // (bx,by) -> (1-by, bx)
        case .deg180: (x, y) = (1.0 - x, 1.0 - y)
        case .deg270: (x, y) = (y, 1.0 - x)       // (bx,by) -> (by, 1-bx)
        }

        // 4) straighten (forward): rotate 출력 → 내접 크롭된 회전 출력. displayUnitToBase 의 un-straighten 역.
        if abs(straightenAngle) > 1e-4, let baseSize, baseSize.width > 0, baseSize.height > 0 {
            let sw: Double, sh: Double
            switch rotation {
            case .deg90, .deg270: sw = Double(baseSize.height); sh = Double(baseSize.width)
            default:              sw = Double(baseSize.width);  sh = Double(baseSize.height)
            }
            let theta = straightenAngle * .pi / 180.0
            let ct = abs(cos(theta)), st = abs(sin(theta))
            let hp = min(sw * sh / (sw * ct + sh * st), sh * sh / (sw * st + sh * ct))
            let wp = (sw / sh) * hp
            let cx = sw / 2, cy = sh / 2
            // 입력 정규(y-down) → 입력 픽셀(y-up) → R(-θ) → 출력 정규.
            let px = x * sw, py = (1.0 - y) * sh
            let dx = px - cx, dy = py - cy
            let cosT = cos(theta), sinT = sin(theta)
            let dxp = dx * cosT + dy * sinT          // R(-θ)
            let dyp = -dx * sinT + dy * cosT
            let ppx = cx + dxp, ppy = cy + dyp
            x = (ppx - (cx - wp / 2)) / wp
            let vUp = (ppy - (cy - hp / 2)) / hp
            y = 1.0 - vUp
        }

        // 5) crop (forward): straighten 출력 정규 → crop 정규. un-crop 의 역.
        if let c = cropRect {
            let vUpIn = 1.0 - y
            x = (x - c.x) / c.z
            let vUp = (vUpIn - c.y) / c.w
            y = 1.0 - vUp
        }

        return CGPoint(x: x, y: y)
    }

    public var displayName: String {
        var parts = ["R\(rotation.displayName)"]
        if flipHorizontal { parts.append("H") }
        if flipVertical { parts.append("V") }
        if let c = cropRect {
            parts.append(String(format: "crop%.0f×%.0f", c.z * 100, c.w * 100))
        }
        return parts.joined(separator: " ")
    }
}

public enum ImageTransformStage {
    public static func apply(to image: CIImage, transform: ImageTransform) -> CIImage {
        // 회전/플립(crop 없이도 동작).
        var img = normalize(image)
        if transform.flipHorizontal {
            let extent = img.extent.integral
            img = applyAffine(
                img,
                CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: extent.width, ty: 0)
            )
        }
        if transform.flipVertical {
            let extent = img.extent.integral
            img = applyAffine(
                img,
                CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: extent.height)
            )
        }

        switch transform.rotation {
        case .deg0:
            break
        case .deg90:
            let extent = img.extent.integral
            img = applyAffine(
                img,
                CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: extent.width)
            )
        case .deg180:
            let extent = img.extent.integral
            img = applyAffine(
                img,
                CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: extent.width, ty: extent.height)
            )
        case .deg270:
            let extent = img.extent.integral
            img = applyAffine(
                img,
                CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: extent.height, ty: 0)
            )
        }
        img = normalize(img)

        // 미세 회전(수평 보정) — 90°/플립 정규화 후, 사용자 크롭 전에 적용. 중심 기준 회전 후
        // 같은 종횡비의 최대 내접 사각형으로 자동 크롭해 빈 모서리를 없앤다.
        if abs(transform.straightenAngle) > 1e-4 {
            img = applyStraighten(img, degrees: transform.straightenAngle)
        }

        // crop — 회전/플립 정규화 후 적용. 정규화(0~1) 사각형을 절대 좌표로 변환.
        if let crop = transform.cropRect {
            let extent = img.extent
            let rect = CGRect(
                x: extent.minX + crop.x * extent.width,
                y: extent.minY + crop.y * extent.height,
                width: crop.z * extent.width,
                height: crop.w * extent.height
            )
            img = img.cropped(to: rect)
            img = normalize(img)
        }
        return img
    }

    private static func applyAffine(_ image: CIImage, _ transform: CGAffineTransform) -> CIImage {
        normalize(image.transformed(by: transform))
    }

    /// 중심 기준으로 `degrees`만큼 회전한 뒤, 원본 종횡비를 유지하는 최대 내접 사각형으로 크롭.
    private static func applyStraighten(_ image: CIImage, degrees: Double) -> CIImage {
        let extent = image.extent
        let w = extent.width, h = extent.height
        guard w > 1, h > 1 else { return image }
        let cx = extent.midX, cy = extent.midY
        let theta = degrees * .pi / 180.0
        // 양수 각도 = 시계방향(수평 기울기 보정). CI는 y-up이라 -theta가 시계방향.
        let t = CGAffineTransform(translationX: cx, y: cy)
            .rotated(by: CGFloat(-theta))
            .translatedBy(x: -cx, y: -cy)
        let rotated = image.transformed(by: t)
        // 같은 종횡비(r=w/h)의 최대 내접 사각형.
        let c = abs(cos(theta)), s = abs(sin(theta))
        let hp = min(Double(w) * Double(h) / (Double(w) * c + Double(h) * s),
                     Double(h) * Double(h) / (Double(w) * s + Double(h) * c))
        let wp = (Double(w) / Double(h)) * hp
        let rect = CGRect(
            x: cx - CGFloat(wp) / 2, y: cy - CGFloat(hp) / 2,
            width: CGFloat(wp), height: CGFloat(hp)
        )
        return normalize(rotated.cropped(to: rect))
    }

    private static func normalize(_ image: CIImage) -> CIImage {
        let extent = image.extent.integral
        guard extent.origin != .zero else {
            return image.cropped(to: CGRect(origin: .zero, size: extent.size))
        }
        let translated = image.transformed(by: CGAffineTransform(
            translationX: -extent.origin.x,
            y: -extent.origin.y
        ))
        return translated.cropped(to: CGRect(origin: .zero, size: extent.size))
    }
}
