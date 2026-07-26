import Foundation
import CoreImage
import CoreGraphics

// 결함 검출 오케스트레이터. 실제 검출은 단일 책임 모듈들이 담당한다:
//   DefectContrastField  — 톤 정규화(Weber/log) 대비 + valid + 국소 통계
//   DefectDustDetector   — 먼지 후보
//   DefectScratchDetector— 다방향·다중스케일 스크래치 후보
//   DefectComponentMask  — 연결요소 형태 게이트 + 마스크 페인팅
// 여기서는 다운스케일 렌더 → 조립 → 원본 해상도 업스케일만 한다.
enum SoftwareDefectDetector {
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
                       context: CIContext = DefectContext.detect) -> CIImage {
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
        let aggressive = brush != nil
        let boost = aggressive ? 0.2 : 0.0
        let dustSens = min(1.0, tuning.dustSensitivity + boost)
        let scratchSens = min(1.0, tuning.scratchSensitivity + boost)

        let field = DefectContrastField(rgba: rgba, width: dW, height: dH)
        // 먼지는 히스테리시스(strong=far 컨텍스트 게이트, weak=soft 연결)로 낸다 — 디테일 섬/구조물은
        // strong 코어가 없어 기각되고, 텍스처 카펫은 soft 연결로 거대 컴포넌트가 되어 면적/aspect
        // 게이트에서 통째로 기각된다(칠 면적 와이프 방지).
        let (dustStrong, dust, _) = DefectDustDetector.candidatesLeveled(
            field, sensitivity: dustSens, region: region, aggressive: aggressive)
        let (scratch, scratchResponse) = DefectScratchDetector.candidatesWithResponse(
            field, sensitivity: scratchSens, protectDetail: tuning.protectDetail,
            region: region, preferredAngle: preferredAngle, aggressive: aggressive)

        // 먼지 면적 상한: 전역은 작은 blob만(halo 오검출 방지). 브러시 영역에선 사용자가 결함을
        // 지목했으므로 짧고 두꺼운(뚱뚱한) 먼지·굵은 곡선도 허용하되, 상한은 "물리 먼지 크기"
        // (원본 raw 해상도 기준 — detectComponents 와 같은 스케일 법칙)로 잡는다. 칠 면적 비율로
        // 잡으면 넓은 일자 칠에서 디테일 섬/텍스처 덩어리가 통째로 먼지가 되어 칠 면적이 재합성
        // (블러)되는 와이프가 생긴다 — 구조 가드(min-cap), 임계는 불변.
        let maxDustArea: Int
        if region == nil {
            maxDustArea = 150
        } else {
            let rawLong = Double(max(image.extent.width, image.extent.height))
            let rr = rawLong / Double(maxDetectDim)
            // ×3: 컴포넌트는 soft(연결) 후보로 재므로 top-hat 스커트/weak 프린지가 코어의 ~3배까지
            // 부풀 수 있다 — 물리 코어 상한에 그 여유를 더한다(디테일 섬 수천 px 는 여전히 기각).
            let physical = max(150.0, rr * rr * 150.0) * (1.0 + dustSens * 5.0) * 3.0 * (scale * scale)
            maxDustArea = max(400, Int(physical.rounded()))
        }
        // 와이프 퓨즈 입력(브러시 전용): 칠 면적 = 브러시 마스크가 켜진 픽셀 수(검출 해상도).
        let regionArea = region.map { r in r.reduce(0) { $0 + ($1 ? 1 : 0) } }
        let bytes = DefectComponentMask.build(
            width: dW, height: dH,
            dust: dust, scratch: scratch,
            dustStrong: dustStrong,
            maxDustArea: maxDustArea,
            minScratchLength: region == nil ? max(10, dW / 120) : 3,
            minScratchAspect: region == nil ? 2.5 : 1.8,
            dustDilate: region == nil ? 0 : 2,
            scratchResponse: region == nil ? nil : scratchResponse,
            regionArea: regionArea
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

    // MARK: 영역 결함 제거 — 라벨 검출 (풀해상도)

    /// 주어진 extent(ROI 또는 타일)를 **다운스케일 없이** 검출해 컴포넌트 라벨맵을 낸다. 작은 결함을
    /// 보존하려고 풀해상도로 보므로 extent 가 크면 비싸다 — 호출측이 타일로 분할해 크기를 제한한다.
    ///
    /// ROI 는 "검출 범위 제한"일 뿐 결함 보증이 아니다(마킹 영역 안에서도 보수적 자동 검출이
    /// 돈다). 따라서 brush 의 공격 게이트가 아니라 전역 자동 검출과 같은 보수
    /// 게이트(aggressive=false)로 "주변과 크게 다른" 먼지/스크래치만 잡는다 — 넓은 평탄/그라데이션·
    /// 그레인을 통째로 결함 처리하지 않는다. 공간 범위 제한은 extent crop 이 담당한다.
    /// - maxDustArea: 먼지 면적 상한(픽셀). 호출측이 원본 raw 해상도 기준으로 계산해 ROI 크기와
    ///   무관하게 "물리 먼지 크기"를 일정하게 유지한다.
    static func detectLabeled(in image: CIImage, extent: CGRect, tuning: Tuning,
                              maxDustArea: Int,
                              classificationMaxDustArea: Int? = nil,
                              extendedDustScales: Bool = false,
                              detectSpecks: Bool = false,
                              rejectLineGrid: Bool = false,
                              preferredAngle: Double? = nil,
                              fieldParallel: Bool = true,
                              context: CIContext = DefectContext.detect) -> DefectLabelField {
        detectLabeledWithResponse(in: image, extent: extent, tuning: tuning, maxDustArea: maxDustArea,
                                  classificationMaxDustArea: classificationMaxDustArea,
                                  extendedDustScales: extendedDustScales, detectSpecks: detectSpecks,
                                  rejectLineGrid: rejectLineGrid, preferredAngle: preferredAngle,
                                  fieldParallel: fieldParallel, context: context).field
    }

    /// detectLabeled 와 동일하되 스크래치 방향 적분 응답도 함께 낸다. 타일 검출이 이 응답을 전역
    /// 맵으로 모아 두면 stitch 이후 프레임 전체에서 연장 증거 판정을 할 수 있다 — 타일 안에서는
    /// 연장 구간이 halo 밖으로 나가 판정 자체가 불가능하다. 응답은 이미 계산된 값을 넘길 뿐이라
    /// 검출 비용은 늘지 않는다.
    /// - deferContinuationFilter: true 면 타일 로컬 연장 판정을 건너뛴다(전역에서 대신 한다).
    static func detectLabeledWithResponse(in image: CIImage, extent: CGRect, tuning: Tuning,
                                          maxDustArea: Int,
                                          classificationMaxDustArea: Int? = nil,
                                          extendedDustScales: Bool = false,
                                          detectSpecks: Bool = false,
                                          rejectLineGrid: Bool = false,
                                          deferContinuationFilter: Bool = false,
                                          preferredAngle: Double? = nil,
                                          fieldParallel: Bool = true,
                                          context: CIContext = DefectContext.detect)
        -> (field: DefectLabelField, scratchResponse: [Float]) {
        let w = Int(extent.width.rounded()), h = Int(extent.height.rounded())
        guard w > 2, h > 2 else {
            return (DefectLabelField(width: max(1, w), height: max(1, h), labels: [], components: []), [])
        }
        let source = image.cropped(to: extent)
        let rgba = renderRGBAf(source, width: w, height: h, context: context)
        // fieldParallel=false: 타일 병렬 검출 내부 — 필드 내부 병렬을 중첩하지 않는다(타일이 이미 코어를 채움).
        let field = DefectContrastField(rgba: rgba, width: w, height: h,
                                     parallel: fieldParallel, extendedDustScales: extendedDustScales)
        // 먼지도 히스테리시스(strong 코어 + weak 프린지)로 낸다 — 작은 불규칙 먼지의 흐린 가장자리/
        // 조각까지 마스크가 덮어 복원이 완결된다. weak 은 SNR floor 유지라 그레인 컴포넌트는 안 생긴다.
        let (dustStrong, dust, dustTrustedStrong) = DefectDustDetector.candidatesLeveled(
            field, sensitivity: tuning.dustSensitivity, aggressive: false)
        // 스크래치·가는 구조를 히스테리시스(strong/weak)로 낸다. strong 은 기존 보수 임계, weak 는
        // 절대 임계만 낮추고 SNR floor(그레인 안전선)는 유지 — buildLabeled 가 strong 코어를 포함한
        // 컴포넌트만 채택하므로, 조각나거나 저대비로 끊긴 가늘고 긴 스크래치·불규칙 곡선을 잇되
        // 그레인은 strong 코어가 없어 컴포넌트를 만들지 못한다(Canny 이중 임계 정신).
        var (scratchStrong, scratch, scratchResponse) = DefectScratchDetector.candidatesLeveled(
            field, sensitivity: tuning.scratchSensitivity, protectDetail: tuning.protectDetail,
            preferredAngle: preferredAngle, aggressive: false, parallel: fieldParallel)
        // 가는 구조(꼬불꼬불 머리카락·가는 스크래치)를 thinMag(작은 SE)로 잡아 scratch 후보에 합친다.
        // dustMag 멀티스케일은 밀집 곡선 사이를 채워 큰 blob 으로 오인하므로, 가는 결함은 thinMag 로
        // 선 자체만 잡고 scratch 의 길이/aspect·가는곡선 게이트로 통과시킨다.
        let (thinStrong, thinWeak) = DefectDustDetector.thinCandidatesLeveled(
            field, sensitivity: tuning.scratchSensitivity, aggressive: false)
        for i in 0..<(w * h) {
            scratchStrong[i] = scratchStrong[i] || thinStrong[i]
            scratch[i] = scratch[i] || thinWeak[i]
        }
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
        let labeled = DefectComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                    scratchStrong: scratchStrong, dustStrong: dustStrong,
                                                    maxDustArea: maxDustArea, minScratchLength: minScratchLength,
                                                    minScratchAspect: minScratchAspect, dustMaxAspect: dustMaxAspect,
                                                    minThickDefect: minThick, maxThickDefect: maxThick,
                                                    dustTrustedStrong: extendedDustScales ? dustTrustedStrong : nil,
                                                    microDustMinArea: extendedDustScales ? 3 : 1,
                                                    grainFieldSmallMax: extendedDustScales
                                                        ? DefectComponentMask.constrainedRegionGrainFieldSmallMax
                                                        : DefectComponentMask.grainFieldSmallMax,
                                                    rejectLineGrid: rejectLineGrid,
                                                    scratchResponse: deferContinuationFilter ? nil : scratchResponse)
        // v2: 물리 분류(dust/pinhole/방향별 scratch/emulsion) + confidence. 검출 채택은 위에서
        // 이미 끝났고 여기는 메타데이터만 채운다 — 임계·게이트 불변.
        for i in 0..<(w * h) where dustStrong[i] { scratchStrong[i] = true }
        let classificationArea = classificationMaxDustArea ?? maxDustArea
        let classified = DefectClassifier.classify(field: labeled, contrast: field, strong: scratchStrong,
                                            pinholeMaxArea: max(16, classificationArea / 25),
                                            emulsionMinArea: max(200, classificationArea / 3))
        guard detectSpecks else { return (classified, scratchResponse) }
        // 미세 입자 추가 패스(옵트인). 같은 rgba/valid 를 재사용하고 결과에 컴포넌트만 더한다 —
        // 기존 검출 임계·게이트·라벨은 불변이다(겹치는 입자는 기존 결과 우선).
        let specks = DefectSpeckDetector.detect(rgba: rgba, width: w, height: h,
                                                valid: field.valid, sensitivity: tuning.dustSensitivity)
        return (DefectSpeckDetector.merged(into: classified, specks: specks), scratchResponse)
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
