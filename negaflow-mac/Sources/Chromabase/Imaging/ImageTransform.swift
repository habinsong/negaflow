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
    /// 변환(원근) 보정. 회전·뒤집기 뒤, 수평 보정 앞에 적용한다.
    public var perspective: PerspectiveCorrection

    public init(
        rotation: ImageRotation = .deg0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        cropRect: SIMD4<Double>? = nil,
        straightenAngle: Double = 0,
        cropAspect: Double? = nil,
        perspective: PerspectiveCorrection = .identity
    ) {
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.cropRect = cropRect
        self.straightenAngle = straightenAngle
        self.cropAspect = cropAspect
        self.perspective = perspective
    }

    enum CodingKeys: String, CodingKey {
        case rotation, flipHorizontal, flipVertical, cropRect, straightenAngle, cropAspect, perspective
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rotation, forKey: .rotation)
        try c.encode(flipHorizontal, forKey: .flipHorizontal)
        try c.encode(flipVertical, forKey: .flipVertical)
        try c.encodeIfPresent(cropRect, forKey: .cropRect)
        try c.encode(straightenAngle, forKey: .straightenAngle)
        try c.encodeIfPresent(cropAspect, forKey: .cropAspect)
        // 원근 보정이 없으면 쓰지 않는다 — 기존 카탈로그·사이드카와 바이트가 같게 남는다.
        if !perspective.isIdentity {
            try c.encode(perspective, forKey: .perspective)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rotation = try c.decodeIfPresent(ImageRotation.self, forKey: .rotation) ?? .deg0
        flipHorizontal = try c.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? false
        flipVertical = try c.decodeIfPresent(Bool.self, forKey: .flipVertical) ?? false
        cropRect = try c.decodeIfPresent(SIMD4<Double>.self, forKey: .cropRect)
        straightenAngle = try c.decodeIfPresent(Double.self, forKey: .straightenAngle) ?? 0
        cropAspect = try c.decodeIfPresent(Double.self, forKey: .cropAspect)
        perspective = (try? c.decodeIfPresent(PerspectiveCorrection.self, forKey: .perspective)) ?? .identity
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
            && abs(straightenAngle) < 1e-4 && perspective.isIdentity
    }

    /// 회전(90° 단위)이 끝난 그림의 픽셀 크기 — 원근 보정의 입력 크기다.
    public func orientedSize(baseSize: CGSize) -> CGSize {
        switch rotation {
        case .deg90, .deg270: return CGSize(width: baseSize.height, height: baseSize.width)
        default: return baseSize
        }
    }

    /// 원근 보정의 매핑(입력 = 회전 뒤 크기). 보정이 없거나 그릴 수 없으면 nil.
    public func perspectiveMapping(baseSize: CGSize) -> PerspectiveGeometry.Mapping? {
        guard perspective.changesGeometry, baseSize.width > 0, baseSize.height > 0 else { return nil }
        return PerspectiveGeometry.mapping(for: perspective, size: orientedSize(baseSize: baseSize))
    }

    /// 수평 보정의 입력 크기 = 원근 보정의 출력 크기.
    func straightenInputSize(baseSize: CGSize) -> CGSize {
        perspectiveMapping(baseSize: baseSize)?.outputRect.size ?? orientedSize(baseSize: baseSize)
    }

    /// 변형된(표시) 이미지의 정규좌표(0..1, y 위→아래)를 **변형 전 base** 정규좌표로 역매핑한다.
    /// 브러시/영역 결함 제거 마스크를 transform-독립적인 base 좌표로 저장해, 회전/플립/회전보정/크롭
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
            // rotate(90/270)는 종횡비를 뒤집는다 — straighten은 rotate·원근 다음이므로 그 출력 크기를 쓴다.
            let inputSize = straightenInputSize(baseSize: baseSize)
            let sw = Double(inputSize.width), sh = Double(inputSize.height)
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

        // 2.5) un-perspective: 출력 사각형 기준 정규좌표 → 원근 보정 전(회전 뒤) 정규좌표.
        if let baseSize, let mapping = perspectiveMapping(baseSize: baseSize),
           let oriented = mapping.inverseUnit(CGPoint(x: x, y: y)) {
            x = Double(oriented.x)
            y = Double(oriented.y)
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

    /// 화면 점이 원본 위에 있으면 원본 정규좌표를, 원근 보정의 빈 곳이면 nil 을 돌려준다. 화소 읽기·
    /// 스포이드처럼 "그 자리의 원본 화소" 가 필요한 곳이 쓴다 — 0…1 로 잘라 쓰면 빈 곳에서 가장자리
    /// 화소를 읽는다. 역변환 오차(1e-6) 만큼은 안으로 본다.
    public func sourceUnit(atDisplayUnit p: CGPoint, baseSize: CGSize?) -> CGPoint? {
        let base = displayUnitToBase(p, baseSize: baseSize)
        let tolerance = 1e-6
        guard base.x.isFinite, base.y.isFinite,
              base.x >= -tolerance, base.x <= 1 + tolerance,
              base.y >= -tolerance, base.y <= 1 + tolerance else { return nil }
        return CGPoint(x: min(max(base.x, 0), 1), y: min(max(base.y, 0), 1))
    }

    /// base 정규좌표(0..1, y-down) → 표시(변형 후) 정규좌표. displayUnitToBase 의 정역(forward).
    /// 영역 결함 제거 가 base 좌표 컴포넌트를 화면에 빨강으로 표시할 때 쓴다. 순서는 forward
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

        // 3.5) perspective (forward): 회전 뒤 정규좌표 → 원근 출력 사각형 기준 정규좌표.
        if let baseSize, let mapping = perspectiveMapping(baseSize: baseSize),
           let corrected = mapping.forwardUnit(CGPoint(x: x, y: y)) {
            x = Double(corrected.x)
            y = Double(corrected.y)
        }

        // 4) straighten (forward): 원근 출력 → 내접 크롭된 회전 출력. displayUnitToBase 의 un-straighten 역.
        if abs(straightenAngle) > 1e-4, let baseSize, baseSize.width > 0, baseSize.height > 0 {
            let inputSize = straightenInputSize(baseSize: baseSize)
            let sw = Double(inputSize.width), sh = Double(inputSize.height)
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

    /// 회전·뒤집기만 건 그림(원근 보정 입력)의 정규좌표 ↔ 원본 정규좌표. 크기가 필요 없다.
    public func orientedUnitToBase(_ p: CGPoint) -> CGPoint {
        var x = Double(p.x), y = Double(p.y)
        switch rotation {
        case .deg0:   break
        case .deg90:  (x, y) = (y, 1.0 - x)
        case .deg180: (x, y) = (1.0 - x, 1.0 - y)
        case .deg270: (x, y) = (1.0 - y, x)
        }
        if flipVertical { y = 1.0 - y }
        if flipHorizontal { x = 1.0 - x }
        return CGPoint(x: x, y: y)
    }

    public func baseUnitToOriented(_ p: CGPoint) -> CGPoint {
        var x = Double(p.x), y = Double(p.y)
        if flipHorizontal { x = 1.0 - x }
        if flipVertical { y = 1.0 - y }
        switch rotation {
        case .deg0:   break
        case .deg90:  (x, y) = (1.0 - y, x)
        case .deg180: (x, y) = (1.0 - x, 1.0 - y)
        case .deg270: (x, y) = (y, 1.0 - x)
        }
        return CGPoint(x: x, y: y)
    }

    /// 원근 보정 입력 좌표 ↔ 화면 좌표. 도우미 안내선이 이 좌표에 저장된다.
    public func orientedUnitToDisplay(_ p: CGPoint, baseSize: CGSize?) -> CGPoint {
        baseUnitToDisplay(orientedUnitToBase(p), baseSize: baseSize)
    }

    public func displayUnitToOriented(_ p: CGPoint, baseSize: CGSize?) -> CGPoint {
        baseUnitToOriented(displayUnitToBase(p, baseSize: baseSize))
    }

    public var displayName: String {
        var parts = [rotation.displayName]
        if flipHorizontal { parts.append("H") }
        if flipVertical { parts.append("V") }
        if let c = cropRect {
            parts.append(String(format: "crop%.0f×%.0f", c.z * 100, c.w * 100))
        }
        if perspective.changesGeometry {
            parts.append("T")
        }
        return parts.joined(separator: " ")
    }
}

/// 원근 보정 뒤 원본이 닿지 않는 자리를 무엇으로 둘지.
///
/// 이 자리는 "데이터 없음"이다. 흰색으로 구워 버리면 뒤의 모든 소비자가 진짜 흰 화소와 구분하지
/// 못한다 — 투명해야 할 색역·클리핑 오버레이가 사진을 덮는 흰 판이 되고, 히스토그램·클리핑 경고·
/// 자동 톤/화이트 밸런스가 빈 곳을 하이라이트로 셌다. 그래서 기본값을 두지 않고 부르는 쪽이 고른다.
public enum ImageTransformFill: Sendable {
    /// 알파 0. 화면 표시·분석·오버레이. 표시하는 쪽이 필요하면 뒤에 흰 바탕을 깐다.
    case transparent
    /// 불투명한 흰색. 알파를 담지 않는 결과물(내보내기 인코딩, 썸네일 파일)만 쓴다.
    case white
}

public enum ImageTransformStage {
    public static func apply(to image: CIImage, transform: ImageTransform, fill: ImageTransformFill) -> CIImage {
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

        // 변환(원근) — 90°/플립 정규화 후, 수평 보정 전.
        if transform.perspective.changesGeometry {
            img = applyPerspective(img, correction: transform.perspective, fill: fill)
        }

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

    /// 원근 보정. 입력 extent 의 네 모서리를 호모그래피로 옮긴 자리에 두는 CIPerspectiveTransform 이
    /// 정확히 같은 호모그래피다. 보정으로 생긴 빈 곳은 `fill` 로 둔다. 어느 쪽이든 결과 extent 는
    /// 출력 사각형 전체다 — 투명이라도 뒤 단계(수평 보정·크롭)의 좌표가 어긋나지 않는다.
    /// 그릴 수 없는 값이면 그림을 그대로 둔다.
    static func applyPerspective(
        _ image: CIImage,
        correction: PerspectiveCorrection,
        fill: ImageTransformFill
    ) -> CIImage {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1,
              let mapping = PerspectiveGeometry.mapping(for: correction, size: extent.size) else {
            return image
        }
        let height = extent.height
        // y 아래 픽셀 → CI(y 위).
        func ci(_ p: CGPoint) -> CIVector { CIVector(x: p.x, y: height - p.y) }
        let corners = mapping.corners
        let warped = image.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": ci(corners[0]),
            "inputTopRight": ci(corners[1]),
            "inputBottomRight": ci(corners[2]),
            "inputBottomLeft": ci(corners[3]),
        ])
        let canvas = CGRect(origin: .zero, size: extent.size)
        let backdrop = switch fill {
        case .transparent: CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
        case .white: CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
        }
        let background = backdrop.cropped(to: canvas)
        let output = mapping.outputRect
        let ciOutput = CGRect(x: output.minX, y: height - output.maxY, width: output.width, height: output.height)
        return normalize(warped.composited(over: background).cropped(to: ciOutput))
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
