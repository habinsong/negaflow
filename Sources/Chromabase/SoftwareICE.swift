import CoreImage

// MARK: - SoftwareICE (IR 없는 소프트웨어 먼지/스크래치 제거)

public struct SoftwareICEParameters: Sendable, Equatable {
    public var strength: Double
    public var dustSensitivity: Double
    public var scratchSensitivity: Double
    public var protectDetail: Double

    public init(strength: Double = 1.0,
                dustSensitivity: Double = 0.55,
                scratchSensitivity: Double = 0.65,
                protectDetail: Double = 0.75) {
        self.strength = strength
        self.dustSensitivity = dustSensitivity
        self.scratchSensitivity = scratchSensitivity
        self.protectDetail = protectDetail
    }
}

public enum SoftwareICE {
    /// - Parameters:
    ///   - threshold: 결함 판정 편차(linear, 0...1). 기본 0.06 ≈ 15/255. 높일수록 보수적.
    ///   - strength:  보정 강도(0...1). 1이면 결함을 완전 대체, 낮추면 원본과 블렌드.
    public static func apply(to image: CIImage,
                             threshold: Double = 0.06,
                             strength: Double = 1.0) -> CIImage {
        guard strength > 1e-3 else { return image }

        let parameters = SoftwareICEParameters(
            strength: strength,
            dustSensitivity: max(0, min(1, (0.10 - threshold) / 0.08)),
            scratchSensitivity: max(0, min(1, (0.11 - threshold) / 0.10)),
            protectDetail: 0.75
        )
        return apply(to: image, parameters: parameters)
    }

    /// - brush: nil이면 전역 자동. 주어지면(흰색=칠한 영역) 그 안에서만 검출·복원한다.
    /// - preferredAngle: 브러시 주축 방향(도). 그와 정렬된 스크래치만 잡아, 칠을 가로지르는
    ///   정상 구조선(가로 칠 위의 세로선 등)이 결함으로 검출·파괴되지 않게 한다.
    public static func apply(to image: CIImage,
                             parameters: SoftwareICEParameters,
                             brush: CIImage? = nil,
                             repairExtent: CGRect? = nil,
                             preferredAngle: Double? = nil) -> CIImage {
        guard parameters.strength > 1e-3 else { return image }
        let extent = image.extent
        let roi = repairExtent.map { $0.integral.intersection(extent) } ?? extent
        guard roi.width > 1, roi.height > 1 else { return image }

        let source = image.cropped(to: roi)
        let median = medianFiltered(source).cropped(to: roi)
        let baseMask = detectMask(in: image, extent: roi, parameters: parameters,
                                  brush: brush, preferredAngle: preferredAngle)
        let mask = scaled(baseMask, by: max(0, min(1, parameters.strength))).cropped(to: roi)
        let useLocalRepair = repairExtent != nil && roi.width * roi.height <= 4_000_000
        let repairSource = useLocalRepair
            ? (ICEScratchRepairer.repair(image: source, mask: mask, extent: roi,
                                         preferredAngle: preferredAngle) ?? median)
            : median

        let repaired = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: repairSource,
            kCIInputBackgroundImageKey: source,
            "inputMaskImage": mask,
        ])?.outputImage?.cropped(to: roi) ?? source

        guard roi != extent else { return repaired.cropped(to: extent) }
        return repaired.composited(over: image).cropped(to: extent)
    }

    // MARK: Region ICE — 검출/복원 분리 진입점 (브러시 apply 와 별개)

    /// ROI 안의 결함을 풀해상도로 검출해 컴포넌트 라벨을 낸다(미리보기·클릭 제외용). 반환 좌표는
    /// ROI 로컬(0..rw, 0..rh). 작은 ROI 는 단일 검출, 큰 ROI 는 overlap-tile 병렬 검출로 처리해
    /// 풀해상도 정확도를 유지하면서 시간을 분산한다.
    public static func detectComponents(in image: CIImage, roi: CGRect,
                                        parameters: SoftwareICEParameters,
                                        preferredAngle: Double? = nil,
                                        tileMax: Int = 1400, halo: Int = 48) -> ICELabelField {
        let extent = roi.integral.intersection(image.extent)
        let rw = Int(extent.width.rounded()), rh = Int(extent.height.rounded())
        guard rw > 2, rh > 2 else { return ICELabelField(width: 1, height: 1, labels: [], components: []) }
        let tuning = SoftwareICEDefectDetector.Tuning(
            dustSensitivity: parameters.dustSensitivity,
            scratchSensitivity: parameters.scratchSensitivity,
            protectDetail: parameters.protectDetail)

        // 먼지 면적 상한 = "물리 먼지 크기" 상한. ROI 를 작게/크게 그려도 일정하도록 원본 raw
        // 해상도(image.extent) 긴 변 기준으로 잡는다 — 전역 자동 검출(다운스케일 ≤1800px 에서 150)과
        // 같은 물리 크기다. 이보다 큰 연결 영역(하늘 등)은 먼지가 아니라 피사체로 보고 통과시키지 않는다.
        let baseLong = Double(max(image.extent.width, image.extent.height))
        let ratio = baseLong / 1800.0
        let baseMaxDust = max(150, Int((ratio * ratio * 150).rounded()))
        // 민감도↑일수록 더 큰(뚱뚱한) 먼지까지 허용. s=0: ×1, s=1: ×6. 하늘 등 평탄면은 임계에서
        // 후보가 안 생겨 면적 상한을 키워도 통째 검출되지 않는다.
        let maxDustArea = Int(Double(baseMaxDust) * (1.0 + parameters.dustSensitivity * 5.0))

        // 작은 ROI: 단일 풀해상도 검출. 좌표는 extent 로컬 = roi 로컬.
        if max(rw, rh) <= tileMax {
            return SoftwareICEDefectDetector.detectLabeled(in: image, extent: extent, tuning: tuning,
                                                           maxDustArea: maxDustArea, preferredAngle: preferredAngle)
        }

        // 큰 ROI: overlap-tile. 각 타일을 halo 만큼 넓혀 검출(경계 결함을 온전히 보되), centroid 가
        // 코어(비중첩 격자 셀)에 든 컴포넌트만 채택해 인접 타일과의 중복을 없앤다. 타일은 비중첩이라
        // 병렬 검출이 안전하다(DefectBrush.removeDefects 와 동일 패턴).
        let cols = Int(ceil(Double(rw) / Double(tileMax)))
        let rows = Int(ceil(Double(rh) / Double(tileMax)))
        let tw = Int(ceil(Double(rw) / Double(cols)))
        let th = Int(ceil(Double(rh) / Double(rows)))

        struct TileResult { let dx0: Int; let dy0: Int; let dw: Int
                            let coreX0: Int; let coreY0: Int; let coreX1: Int; let coreY1: Int
                            let field: ICELabelField }
        var results = [TileResult?](repeating: nil, count: cols * rows)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: cols * rows) { t in
            let cx = t % cols, cy = t / cols
            let coreX0 = cx * tw, coreY0 = cy * th
            let coreX1 = min(rw, coreX0 + tw), coreY1 = min(rh, coreY0 + th)
            guard coreX1 > coreX0, coreY1 > coreY0 else { return }
            let dx0 = max(0, coreX0 - halo), dy0 = max(0, coreY0 - halo)
            let dx1 = min(rw, coreX1 + halo), dy1 = min(rh, coreY1 + halo)
            let detectRect = CGRect(x: extent.minX + CGFloat(dx0), y: extent.minY + CGFloat(dy0),
                                    width: CGFloat(dx1 - dx0), height: CGFloat(dy1 - dy0))
            let field = SoftwareICEDefectDetector.detectLabeled(in: image, extent: detectRect, tuning: tuning,
                                                               maxDustArea: maxDustArea, preferredAngle: preferredAngle)
            let r = TileResult(dx0: dx0, dy0: dy0, dw: Int(detectRect.width.rounded()),
                               coreX0: coreX0, coreY0: coreY0, coreX1: coreX1, coreY1: coreY1, field: field)
            lock.lock(); results[t] = r; lock.unlock()
        }

        // 순차 병합(결정적 id). centroid-in-core 컴포넌트만 전역 라벨맵에 기록한다.
        var labels = [Int32](repeating: -1, count: rw * rh)
        var components: [ICEComponent] = []
        var nextID: Int32 = 0
        for case let r? in results {
            for comp in r.field.components where !comp.pixels.isEmpty {
                var sx = 0, sy = 0
                for p in comp.pixels { sx += p % r.dw; sy += p / r.dw }
                let gcx = r.dx0 + sx / comp.pixels.count
                let gcy = r.dy0 + sy / comp.pixels.count
                guard gcx >= r.coreX0, gcx < r.coreX1, gcy >= r.coreY0, gcy < r.coreY1 else { continue }
                let id = nextID; nextID += 1
                var gpixels: [Int] = []
                var minX = rw, minY = rh, maxX = 0, maxY = 0
                for p in comp.pixels {
                    let ggx = r.dx0 + p % r.dw, ggy = r.dy0 + p / r.dw
                    guard ggx >= 0, ggx < rw, ggy >= 0, ggy < rh else { continue }
                    let gi = ggy * rw + ggx
                    if labels[gi] < 0 { labels[gi] = id }
                    gpixels.append(gi)
                    if ggx < minX { minX = ggx }; if ggx > maxX { maxX = ggx }
                    if ggy < minY { minY = ggy }; if ggy > maxY { maxY = ggy }
                }
                if !gpixels.isEmpty {
                    components.append(ICEComponent(id: id, kind: comp.kind, pixels: gpixels,
                                                   minX: minX, minY: minY, maxX: maxX, maxY: maxY))
                }
            }
        }
        return ICELabelField(width: rw, height: rh, labels: labels, components: components)
    }

    /// 검출을 건너뛰고 주어진 마스크(흰색=제거)로 ROI 안을 복원한다. mask 는 image 와 같은 좌표계(roi
    /// 영역에 정렬)여야 한다. apply 의 복원 후반부(ICEScratchRepairer + CIBlendWithMask)와 동일하다.
    public static func repair(image: CIImage, roi: CGRect, mask: CIImage,
                              preferredAngle: Double? = nil) -> CIImage {
        let extent = roi.integral.intersection(image.extent)
        guard extent.width > 1, extent.height > 1 else { return image }
        let source = image.cropped(to: extent)
        let mask = mask.cropped(to: extent)
        let median = medianFiltered(source).cropped(to: extent)
        let repairSource = ICEScratchRepairer.repair(image: source, mask: mask, extent: extent,
                                                     preferredAngle: preferredAngle) ?? median
        let repaired = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: repairSource,
            kCIInputBackgroundImageKey: source,
            "inputMaskImage": mask,
        ])?.outputImage?.cropped(to: extent) ?? source
        // roi 가 이미지 일부면 복원한 roi 를 원본 위에 합성해 **전체 이미지**를 반환한다. roi 로
        // 다시 crop 하면 roi 조각만 남아, 호출측 createCGImage(from: 원본 전체 extent)에서 roi 밖이
        // 0=검정으로 채워진다 — "검은 배경 + 네모" 깨짐의 원인이었다.
        guard extent != image.extent else { return repaired.cropped(to: extent) }
        return repaired.composited(over: image).cropped(to: image.extent)
    }

    /// 편집된 컴포넌트(excluded 제외)를 렌더한 결함 마스크(RGBA8, 흰색=제거). 편집 히스토리에 저장해
    /// 두었다가 repair(image:roi:mask:)로 재적용하기 위한 진입점 — 무거운 ICELabelField 전체 대신
    /// roi 크기의 마스크 bytes 만 보관하면 되므로 메모리에 가볍다.
    public static func componentMaskBytes(field: ICELabelField, excluded: Set<Int32>,
                                          dustDilate: Int = 2) -> [UInt8] {
        ICEComponentMask.renderMask(field, excluded: excluded,
                                    maxHoleArea: field.width * field.height, dustDilate: dustDilate)
    }

    /// 편집된 컴포넌트(excluded 제외)를 마스크로 렌더해 ROI 안을 복원한다. ICEComponentMask 내부에
    /// 접근하지 않고 검출(detectComponents)→복원을 잇는 진입점이다. mask 좌표 정렬(roi 로 translate)도
    /// 여기서 처리한다. roi 는 검출에 쓴 CIImage(y-up) ROI 와 같아야 한다.
    public static func repairComponents(image: CIImage, roi: CGRect, field: ICELabelField,
                                        excluded: Set<Int32>, dustDilate: Int = 2) -> CIImage? {
        guard !field.isEmpty, field.width > 0, field.height > 0 else { return nil }
        let maskBytes = ICEComponentMask.renderMask(field, excluded: excluded,
                                                    maxHoleArea: field.width * field.height, dustDilate: dustDilate)
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let maskCI = CIImage(
            bitmapData: Data(maskBytes), bytesPerRow: field.width * 4,
            size: CGSize(width: field.width, height: field.height),
            format: .RGBA8, colorSpace: linear
        ).transformed(by: CGAffineTransform(translationX: roi.minX, y: roi.minY))
        return repair(image: image, roi: roi, mask: maskCI)
    }

    public static func detectMask(in image: CIImage,
                                  parameters: SoftwareICEParameters = SoftwareICEParameters(),
                                  brush: CIImage? = nil) -> CIImage {
        let extent = image.extent
        return detectMask(in: image, extent: extent, parameters: parameters, brush: brush)
    }

    private static func detectMask(in image: CIImage,
                                   extent: CGRect,
                                   parameters: SoftwareICEParameters,
                                   brush: CIImage?,
                                   preferredAngle: Double? = nil) -> CIImage {
        return SoftwareICEDefectDetector.detect(
            in: image,
            extent: extent,
            tuning: SoftwareICEDefectDetector.Tuning(
                dustSensitivity: parameters.dustSensitivity,
                scratchSensitivity: parameters.scratchSensitivity,
                protectDetail: parameters.protectDetail
            ),
            brush: brush,
            preferredAngle: preferredAngle
        ).cropped(to: extent)
    }

    public static func overlayMask(on image: CIImage, mask: CIImage, opacity: Double = 0.65) -> CIImage {
        let extent = image.extent
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        let scaledMask = scaled(mask.cropped(to: extent), by: max(0, min(1, opacity)))
        return CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: red,
            kCIInputBackgroundImageKey: image,
            "inputMaskImage": scaledMask,
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

    private static func scaled(_ image: CIImage, by scale: Double) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(scale), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(scale), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(scale), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
    }

}
