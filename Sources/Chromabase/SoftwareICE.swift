import CoreImage

// MARK: - SoftwareICE (IR 없는 소프트웨어 먼지/스크래치 제거)
//
// Digital ICE는 IR 센서로 결함을 검출하지만, 하드웨어 IR이 없으면 RGB만으로 처리해야 한다.
// 검증된 RGB-only 방법론(Photoshop Dust&Scratches / darktable hot-pixels 계열):
//
//   1. median 레퍼런스 M = median(input)        — 엣지 보존(가우시안보다 오검출 적음)
//   2. 채널별 편차 D = |input - M|
//   3. 임계값 게이트: D > threshold 인 픽셀만 결함 후보
//   4. 채널 AND: 먼지는 무채색 occlusion이라 3채널 동시에 튄다.
//      → R·G·B 마스크를 곱해(교집합) 무채색 결함만 남기고 컬러 디테일/그레인은 배제.
//   5. morphological open(erode→dilate): 고립된 단일 픽셀(그레인)·얇은 선(엣지) 제거.
//   6. 마스크 영역만 median/blur로 inpaint.
//
// IR이 없으므로 "필름 dye와 같은 색의 결함"은 잡지 못한다(원리적 한계). 무채색 먼지/스크래치
// 위주로 안전하게 제거하고, strength로 강도를 조절한다.
public enum SoftwareICE {
    /// - Parameters:
    ///   - threshold: 결함 판정 편차(linear, 0...1). 기본 0.06 ≈ 15/255. 높일수록 보수적.
    ///   - strength:  보정 강도(0...1). 1이면 결함을 완전 대체, 낮추면 원본과 블렌드.
    public static func apply(to image: CIImage,
                             threshold: Double = 0.06,
                             strength: Double = 1.0) -> CIImage {
        guard strength > 1e-3 else { return image }
        let extent = image.extent

        // 1. median 레퍼런스(3x3, radius 1). 작은 먼지에 적합.
        let median = medianFiltered(image).cropped(to: extent)

        // 2-3. 채널별 |input - median|을 구하고 임계값으로 이진화.
        //      CIDifferenceBlendMode가 |a-b|를 직접 준다.
        let diff = CIFilter(name: "CIDifferenceBlendMode", parameters: [
            kCIInputImageKey: image,
            kCIInputBackgroundImageKey: median,
        ])?.outputImage?.cropped(to: extent) ?? image
        // threshold 게이트: (D - t)를 큰 게인으로 증폭 후 clamp → 0/1 근사.
        let gated = diff.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 40, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 40, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 40, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: CGFloat(-40 * threshold),
                                        y: CGFloat(-40 * threshold),
                                        z: CGFloat(-40 * threshold), w: 0),
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
        ]).cropped(to: extent)

        // 4. 채널 AND = min(R,G,B). 무채색(3채널 동시) 결함만 남긴다.
        //    luminance 가중이 아니라 곱(min 근사)으로 교집합을 만든다.
        let andMask = channelIntersection(gated).cropped(to: extent)

        // 5. dilate로 결함 블롭을 확장(halo 커버). erode는 단일 픽셀 먼지를 지우므로
        //    open(erode→dilate) 대신 close에 가까운 dilate 위주로 간다.
        //    오검출(그레인)은 채널 AND(4단계)에서 이미 크게 걸러진다.
        let opened = andMask
            .applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": 2.0])
            .cropped(to: extent)

        // strength 반영: 마스크 밝기를 strength로 스케일.
        let mask = strength < 1.0
            ? opened.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(strength), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: CGFloat(strength), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(strength), w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
              ]).cropped(to: extent)
            : opened

        // 6. inpaint: 마스크 영역에 median fill을 보여준다.
        return CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: median,
            kCIInputBackgroundImageKey: image,
            "inputMaskImage": mask,
        ])?.outputImage?.cropped(to: extent) ?? image
    }

    // MARK: helpers

    /// 3x3 median. CIMedianFilter는 고정 3x3(radius 1)이다.
    private static func medianFiltered(_ image: CIImage) -> CIImage {
        if let f = CIFilter(name: "CIMedianFilter") {
            f.setValue(image, forKey: kCIInputImageKey)
            if let out = f.outputImage { return out }
        }
        // 폴백: 약한 가우시안.
        return image.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 1.0])
    }

    /// 채널 교집합 마스크 = min(R,G,B)을 모든 채널에 복제한 그레이스케일.
    /// min은 직접 없으므로 R·G·B 곱으로 근사한다(0/1 마스크에서 곱 = AND).
    private static func channelIntersection(_ image: CIImage) -> CIImage {
        let extent = image.extent
        // gray = R*G*B 를 만들기 위해, 먼저 R*G를 곱하고 그 결과에 B를 곱한다.
        // CIMultiplyCompositing은 채널별 곱(component-wise)이라, 채널을 회전시켜 곱한다.
        // R 마스크: (R,R,R)
        func broadcast(_ src: CIImage, channel: Int) -> CIImage {
            let r = CIVector(x: channel == 0 ? 1 : 0, y: channel == 1 ? 1 : 0, z: channel == 2 ? 1 : 0, w: 0)
            return src.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": r, "inputGVector": r, "inputBVector": r,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ]).cropped(to: extent)
        }
        let rr = broadcast(image, channel: 0)
        let gg = broadcast(image, channel: 1)
        let bb = broadcast(image, channel: 2)
        let rg = CIFilter(name: "CIMultiplyCompositing", parameters: [
            kCIInputImageKey: rr, kCIInputBackgroundImageKey: gg,
        ])?.outputImage?.cropped(to: extent) ?? image
        return CIFilter(name: "CIMultiplyCompositing", parameters: [
            kCIInputImageKey: rg, kCIInputBackgroundImageKey: bb,
        ])?.outputImage?.cropped(to: extent) ?? rg
    }
}
