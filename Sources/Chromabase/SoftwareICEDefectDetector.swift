import Foundation
import CoreImage
import CoreGraphics

// 결함 검출 오케스트레이터. 실제 검출은 단일 책임 모듈들이 담당한다:
//   ICEContrastField  — 톤 정규화(Weber/log) 대비 + valid + 국소 통계
//   ICEDustDetector   — 먼지 후보
//   ICEScratchDetector— 다방향·다중스케일 스크래치 후보
//   ICEComponentMask  — 연결요소 형태 게이트 + 마스크 페인팅
// 여기서는 다운스케일 렌더 → 조립 → 원본 해상도 업스케일만 한다.
enum SoftwareICEDefectDetector {
    struct Tuning {
        var dustSensitivity: Double
        var scratchSensitivity: Double
        var protectDetail: Double
    }

    /// 검출 해상도 상한(긴 변). 이보다 크면 비율 유지로 축소해 검출한다.
    private static let maxDetectDim = 1800

    /// - brush: nil이면 전역 자동 검출. 주어지면(흰색=칠한 영역) 그 안에서만 검출하고
    ///   사용자가 결함 위치를 지정했으므로 더 민감하게(임계↓, 짧은 선 허용) 본다.
    static func detect(in image: CIImage,
                       extent: CGRect,
                       tuning: Tuning,
                       brush: CIImage? = nil,
                       preferredAngle: Double? = nil,
                       context: CIContext = ICEContext.detect) -> CIImage {
        let fullW = Int(extent.width.rounded())
        let fullH = Int(extent.height.rounded())
        guard fullW > 8, fullH > 8 else { return emptyMask(width: max(1, fullW), height: max(1, fullH)) }

        let longSide = max(fullW, fullH)
        let scale = longSide > maxDetectDim ? Double(maxDetectDim) / Double(longSide) : 1.0
        let dW = max(1, Int((Double(fullW) * scale).rounded()))
        let dH = max(1, Int((Double(fullH) * scale).rounded()))

        let source = image.cropped(to: extent)
        let scaled = scale < 1.0
            ? source.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0])
            : source
        let rgba = renderRGBAf(scaled, width: dW, height: dH, context: context)

        // 브러시 영역(있으면). 사용자가 결함 위치를 직접 칠했으므로 공격적으로(임계↓, 민감도↑) 본다.
        // 전역 자동 검출(brush==nil)은 보수적으로 — "주변과 크게 다른" 결함만 잡는다.
        let region = brush.map { renderRegion($0, extent: extent, width: dW, height: dH, context: context) }
        let regionArea = region?.reduce(0) { $0 + ($1 ? 1 : 0) } ?? 0
        let aggressive = brush != nil
        let boost = aggressive ? 0.2 : 0.0
        let dustSens = min(1.0, tuning.dustSensitivity + boost)
        let scratchSens = min(1.0, tuning.scratchSensitivity + boost)

        let field = ICEContrastField(rgba: rgba, width: dW, height: dH)
        let dust = ICEDustDetector.candidates(field, sensitivity: dustSens, region: region, aggressive: aggressive)
        let scratch = ICEScratchDetector.candidates(
            field, sensitivity: scratchSens, protectDetail: tuning.protectDetail,
            region: region, preferredAngle: preferredAngle, aggressive: aggressive)

        // 먼지 면적 상한: 전역은 작은 blob만(halo 오검출 방지). 브러시 영역에선 사용자가 결함을
        // 지목했으므로 짧고 두꺼운(뚱뚱한) 먼지·굵은 곡선도 허용한다. 단 칠한 영역 대비 비율로
        // 제한해, 칠 영역 전체를 통째로 결함 처리(=정상 구조 훼손)하지 않게 한다.
        let maxDustArea = region == nil ? 150 : max(400, Int(Double(regionArea) * 0.6))
        let bytes = ICEComponentMask.build(
            width: dW, height: dH,
            dust: dust, scratch: scratch,
            maxDustArea: maxDustArea,
            minScratchLength: region == nil ? max(10, dW / 120) : 3,
            minScratchAspect: region == nil ? 2.5 : 1.8,
            dustDilate: region == nil ? 0 : 2
        )

        let small = CIImage(
            bitmapData: Data(bytes), bytesPerRow: dW * 4,
            size: CGSize(width: dW, height: dH),
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        guard scale < 1.0 else {
            return small
                .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
                .cropped(to: extent)
        }
        return small
            .transformed(by: CGAffineTransform(scaleX: CGFloat(fullW) / CGFloat(dW),
                                               y: CGFloat(fullH) / CGFloat(dH)))
            .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
            .cropped(to: extent)
    }

    // MARK: Region ICE — 라벨 검출 (풀해상도)

    /// 주어진 extent(ROI 또는 타일)를 **다운스케일 없이** 검출해 컴포넌트 라벨맵을 낸다. 작은 결함을
    /// 보존하려고 풀해상도로 보므로 extent 가 크면 비싸다 — 호출측이 타일로 분할해 크기를 제한한다.
    ///
    /// ROI 는 "검출 범위 제한"일 뿐 결함 보증이 아니다(SilverFast SRDx 동일: 마킹 영역 안에서도
    /// 보수적 자동 검출이 돈다). 따라서 brush 의 공격 게이트가 아니라 전역 자동 검출과 같은 보수
    /// 게이트(aggressive=false)로 "주변과 크게 다른" 먼지/스크래치만 잡는다 — 넓은 평탄/그라데이션·
    /// 그레인을 통째로 결함 처리하지 않는다. 공간 범위 제한은 extent crop 이 담당한다.
    /// - maxDustArea: 먼지 면적 상한(픽셀). 호출측이 원본 raw 해상도 기준으로 계산해 ROI 크기와
    ///   무관하게 "물리 먼지 크기"를 일정하게 유지한다.
    static func detectLabeled(in image: CIImage, extent: CGRect, tuning: Tuning,
                              maxDustArea: Int,
                              preferredAngle: Double? = nil,
                              context: CIContext = ICEContext.detect) -> ICELabelField {
        let w = Int(extent.width.rounded()), h = Int(extent.height.rounded())
        guard w > 2, h > 2 else {
            return ICELabelField(width: max(1, w), height: max(1, h), labels: [], components: [])
        }
        let source = image.cropped(to: extent)
        let rgba = renderRGBAf(source, width: w, height: h, context: context)
        let field = ICEContrastField(rgba: rgba, width: w, height: h)
        let dust = ICEDustDetector.candidates(field, sensitivity: tuning.dustSensitivity, aggressive: false)
        let scratch = ICEScratchDetector.candidates(field, sensitivity: tuning.scratchSensitivity,
                                                    protectDetail: tuning.protectDetail,
                                                    preferredAngle: preferredAngle, aggressive: false)
        // 형태 게이트를 민감도(s∈0~1)로 완화한다. grain/하늘은 이미 후보 임계에서 걸러지므로
        // 형태를 풀어도 폭발하지 않는다 — 직선·컴팩트 가정을 완화해 곡선/꼬불꼬불·뚱뚱·짧은 결함을 살린다.
        //   dust aspect 상한 4→8(꼬불꼬불·길쭉), scratch 최소 길이↓(중간 길이 선), 최소 aspect 2.5→1.8.
        let s = tuning.dustSensitivity
        let dustMaxAspect = 4.0 + s * 4.0
        let minScratchAspect = 2.5 - s * 0.7
        let minScratchLength = max(6, max(w, h) / Int(120 + s * 120))
        // 두꺼운 결함(두꺼운 스크래치/꼬불꼬불 먼지) 두께 게이트. 평균 두께 [4, 12~24]px — 강도↑일수록
        // 더 두꺼운 결함까지 허용한다(가는 정상선·넓은 정상면은 배제). top-hat SE(≤radius12)가 폭을
        // 채우는 한도(~24px) 안이라, 마스크가 폭 중앙까지 덮여 복원(onion-peel)이 완전 제거한다.
        let minThick = 4
        let maxThick = Int(12 + s * 12)
        return ICEComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                             maxDustArea: maxDustArea, minScratchLength: minScratchLength,
                                             minScratchAspect: minScratchAspect, dustMaxAspect: dustMaxAspect,
                                             minThickDefect: minThick, maxThickDefect: maxThick)
    }

    // MARK: render

    private static func renderRGBAf(_ image: CIImage, width: Int, height: Int, context: CIContext) -> [Float] {
        // 검출은 sRGB 감마(디스플레이) 도메인에서 한다. 감마가 이미 ~지각 균일이라
        // 암부 결함도 명부 결함과 비슷한 진폭을 가진다(선형은 암부를 짓눌러 놓침).
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        var rgba = [Float](repeating: 0, count: width * height * 4)
        context.render(
            image, toBitmap: &rgba,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: image.extent.origin.x, y: image.extent.origin.y,
                           width: CGFloat(width), height: CGFloat(height)),
            format: .RGBAf, colorSpace: srgb
        )
        return rgba
    }

    /// 브러시 마스크를 검출 해상도의 bool 영역으로 렌더(흰색=칠한 영역).
    private static func renderRegion(_ brush: CIImage, extent: CGRect,
                                     width: Int, height: Int, context: CIContext) -> [Bool] {
        let scaleX = CGFloat(width) / extent.width
        let scaleY = CGFloat(height) / extent.height
        let scaled = brush
            .transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        var gray = [UInt8](repeating: 0, count: width * height * 4)
        context.render(
            scaled, toBitmap: &gray, rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        var region = [Bool](repeating: false, count: width * height)
        for i in 0..<(width * height) {
            // 칠한 색(빨강/흰색) 채널이 임계 이상이면 칠한 영역. 흑백·빨강 브러시 모두 대응.
            region[i] = gray[i * 4] > 64
        }
        return region
    }

    private static func emptyMask(width: Int, height: Int) -> CIImage {
        CIImage(
            bitmapData: Data(count: max(1, width * height * 4)),
            bytesPerRow: max(1, width) * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
    }
}
