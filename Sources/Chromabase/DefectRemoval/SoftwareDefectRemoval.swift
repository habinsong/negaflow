import CoreImage

// MARK: - SoftwareDefectRemoval (IR 없는 소프트웨어 먼지/스크래치 제거)

public struct SoftwareDefectParameters: Sendable, Equatable {
    public var strength: Double
    public var dustSensitivity: Double
    public var scratchSensitivity: Double
    public var protectDetail: Double
    /// 미세 입자(현상 찌꺼기·유분, 2~7px) 추가 검출 — DefectSpeckDetector 채널 동시성 패스.
    /// 기본 off: 기존 검출 경로·결과는 바이트 동일하게 유지된다.
    public var detectMicroSpecks: Bool

    public init(strength: Double = 1.0,
                dustSensitivity: Double = 0.55,
                scratchSensitivity: Double = 0.65,
                protectDetail: Double = 0.75,
                detectMicroSpecks: Bool = false) {
        self.strength = strength
        self.dustSensitivity = dustSensitivity
        self.scratchSensitivity = scratchSensitivity
        self.protectDetail = protectDetail
        self.detectMicroSpecks = detectMicroSpecks
    }
}

public enum SoftwareDefectRemoval {
    /// repair(image:roi:mask:) 가 마스크 픽셀 주변에서 참조하는 최대 문맥 거리(px)의 안전 상한.
    /// 구조 채움 탐색(maxStep ≤ 128), 질감 전사 변위(2d ≤ 256 + 이웃 1), 컨텍스트 링(bbox+5),
    /// grain σ(bbox+5)를 모두 덮는다. 마스크 경계에서 이 여백 이상을 확보한 부분 ROI 복원은
    /// 전체 ROI 복원과 픽셀 단위로 동일하다 — 호출측이 저장/재계산 창을 결함 크기 비례로
    /// 줄이는 근거다(여백 미달 crop 은 결과가 달라질 수 있으므로 금지).
    public static let repairContextRadius = 264
    /// 전체 프레임 자동 모드에서 "오검출 위험 높음" 경고를 띄우는 검출 원픽셀 비율 기준.
    /// FILM-R v2 44쌍에서 이 값을 넘긴 프레임 상당수가 실제로 큰 오검출이었다. 다만 정상 구조가
    /// 대량 검출된 경우와 실제로 먼지가 많은 장면은 RGB만으로 구분할 수 없으므로 **검출 결과를
    /// 버리지 않고 경고만** 한다 — 최종 판단(컴포넌트 클릭 제외)은 사용자가 한다.
    static let wholeFrameAutomaticCandidateFractionLimit = 0.0006
    /// 같은 경고의 지역 밀도 기준. 타일 크기는 해상도에 비례해 2K~3K FILM-R에서는 약 128px가 된다.
    static let wholeFrameAutomaticLocalDensityLimit = 0.02

    private struct RegionDefectTileResult {
        let dx0: Int
        let fieldY0: Int
        let dw: Int
        let coreX0: Int
        let coreY0: Int
        let coreX1: Int
        let coreY1: Int
        let field: DefectLabelField
    }

    private struct MappedDefectComponent {
        let kind: DefectComponent.Kind
        let pixels: [Int]
        let classification: DefectClass
        let confidence: Double
    }

    private struct ComponentUnion {
        var parent: [Int]

        init(count: Int) {
            parent = Array(0..<count)
        }

        mutating func root(of value: Int) -> Int {
            var value = value
            while parent[value] != value {
                parent[value] = parent[parent[value]]
                value = parent[value]
            }
            return value
        }

        mutating func merge(_ lhs: Int, _ rhs: Int) {
            let a = root(of: lhs)
            let b = root(of: rhs)
            if a != b { parent[max(a, b)] = min(a, b) }
        }
    }

    /// - Parameters:
    ///   - threshold: 결함 판정 편차(linear, 0...1). 기본 0.06 ≈ 15/255. 높일수록 보수적.
    ///   - strength:  보정 강도(0...1). 1이면 결함을 완전 대체, 낮추면 원본과 블렌드.
    public static func apply(to image: CIImage,
                             threshold: Double = 0.06,
                             strength: Double = 1.0) -> CIImage {
        guard strength > 1e-3 else { return image }

        let parameters = SoftwareDefectParameters(
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
                             parameters: SoftwareDefectParameters,
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
        let repairResult = useLocalRepair
            ? DefectScratchRepairer.repairResult(image: source, mask: mask, extent: roi,
                                              preferredAngle: preferredAngle)
            : nil
        let repairSource = repairResult?.image ?? median
        let blendMask = repairResult?.blendMask ?? mask

        let repaired = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: repairSource,
            kCIInputBackgroundImageKey: source,
            "inputMaskImage": blendMask,
        ])?.outputImage?.cropped(to: roi) ?? source

        guard roi != extent else { return repaired.cropped(to: extent) }
        return repaired.composited(over: image).cropped(to: extent)
    }

    // MARK: 영역 결함 제거 — 검출/복원 분리 진입점 (브러시 apply 와 별개)

    /// ROI 안의 결함을 풀해상도로 검출해 컴포넌트 라벨을 낸다(미리보기·클릭 제외용). 반환 좌표는
    /// ROI 로컬(0..rw, 0..rh). 작은 ROI 는 단일 검출, 큰 ROI 는 overlap-tile 병렬 검출로 처리해
    /// 풀해상도 정확도를 유지하면서 시간을 분산한다.
    /// - wholeFrameAuto: 자동(전체 프레임) 모드. true면 ROI 가 좌표 변환/반올림으로 image.extent 와
    ///   정확히 일치하지 않아도 **전역 자동 계약**(보수 검출 + 구조선 격자 배제)을 강제한다. 이걸
    ///   기하학적 일치(extent == image.extent)로만 판정하면, 앱의 자동 모드가 넘기는 0..1 ROI 가
    ///   변환 후 1px 어긋나 "부분 ROI(공격적 확장 + 격자 배제 off)"로 오판돼 오검출이 폭증한다.
    public static func detectComponents(in image: CIImage, roi: CGRect,
                                        parameters: SoftwareDefectParameters,
                                        wholeFrameAuto: Bool = false,
                                        preferredAngle: Double? = nil,
                                        tileMax: Int = 1400, halo: Int = 48,
                                        shouldCancel: (() -> Bool)? = nil) -> DefectLabelField {
        let extent = roi.integral.intersection(image.extent)
        let rw = Int(extent.width.rounded()), rh = Int(extent.height.rounded())
        func emptyField() -> DefectLabelField {
            DefectLabelField(width: max(1, rw), height: max(1, rh), labels: [], components: [])
        }
        guard rw > 2, rh > 2, shouldCancel?() != true else { return emptyField() }
        let tuning = SoftwareDefectDetector.Tuning(
            dustSensitivity: parameters.dustSensitivity,
            scratchSensitivity: parameters.scratchSensitivity,
            protectDetail: parameters.protectDetail)

        // 먼지 면적 상한 = "물리 먼지 크기" 상한. ROI 를 작게/크게 그려도 일정하도록 원본 raw
        // 해상도(image.extent) 긴 변 기준으로 잡는다 — 전역 자동 검출(다운스케일 ≤1800px 에서 150)과
        // 같은 물리 크기다. 이보다 큰 연결 영역(하늘 등)은 먼지가 아니라 피사체로 보고 통과시키지 않는다.
        let baseLong = Double(max(image.extent.width, image.extent.height))
        let ratio = baseLong / 1800.0
        let baseMaxDust = max(150, Int((ratio * ratio * 150).rounded()))
        // 전체 프레임 자동 검출은 FILM-R no-regression 기준의 기존 보수 계약을 유지한다. 사용자가
        // 부분 ROI를 그려 범위를 지정한 가이드 경로에서만 미세/대형/밀집 이물 확장 규칙을 켠다.
        // wholeFrameAuto 면 ROI 반올림 어긋남과 무관하게 보수(비제약) 경로를 강제한다.
        let constrainedRegion = wholeFrameAuto ? false : (extent != image.extent.integral)
        // 민감도↑일수록 큰 먼지·현상 찌꺼기까지 허용. 대형 luma 국소 편차가 내부를 실제 후보로
        // 확인한 뒤에만 이 면적 게이트에 도달한다. 부분 ROI에서 s=1은 ×49로
        // 4K~5K 스캔의 수십~백여 px 이물도 받되, aspect/고립/SNR 게이트는 그대로 유지한다.
        let dustSensitivity = max(0, min(1, parameters.dustSensitivity))
        let areaScale = constrainedRegion ? 48.0 : 5.0
        let maxDustArea = Int(Double(baseMaxDust) * (1.0 + dustSensitivity * areaScale))
        // 분류 임계는 기존 물리 스케일을 유지한다. 큰 이물 검출 허용치를 pinhole/emulsion 분류에
        // 재사용하면 같은 컴포넌트가 단순 dust로 재분류되므로 서로 다른 계약으로 전달한다.
        let classificationMaxDustArea = Int(Double(baseMaxDust) * (1.0 + dustSensitivity * 5.0))

        // 작은 ROI: 단일 풀해상도 검출. 좌표는 extent 로컬 = roi 로컬.
        // 격자 배제는 전체 프레임 자동(비제약)에서만 켠다 — 사용자가 ROI 로 특정 결함을 지목한
        // 가이드에서는 대상 스크래치를 격자로 오인해 지우지 않도록 끈다.
        let rejectLineGrid = !constrainedRegion
        if max(rw, rh) <= tileMax {
            let field = SoftwareDefectDetector.detectLabeled(in: image, extent: extent, tuning: tuning,
                                                                maxDustArea: maxDustArea,
                                                                classificationMaxDustArea: classificationMaxDustArea,
                                                                extendedDustScales: constrainedRegion,
                                                                detectSpecks: parameters.detectMicroSpecks,
                                                                rejectLineGrid: rejectLineGrid,
                                                                preferredAngle: preferredAngle)
            guard shouldCancel?() != true else { return emptyField() }
            return wholeFrameAuto ? applyingWholeFrameAutomaticRiskFlag(to: field) : field
        }

        // 큰 ROI: overlap-tile. 각 타일을 halo 만큼 넓혀 검출하고, 결과 픽셀은 비중첩 core에서만
        // 채택한 뒤 전역 8-연결로 다시 잇는다. 경계 결함 누락·중복 없이 타일을 병렬 검출한다.
        let cols = Int(ceil(Double(rw) / Double(tileMax)))
        let rows = Int(ceil(Double(rh) / Double(tileMax)))
        let tw = Int(ceil(Double(rw) / Double(cols)))
        let th = Int(ceil(Double(rh) / Double(rows)))

        let tileCount = cols * rows
        let results = ConcurrentResultStore<RegionDefectTileResult>(count: tileCount)
        // 검출기의 최대 문맥 반경보다 작은 halo는 타일 경계에서 통계를 잘라 같은 결함을 누락하거나
        // 중복 검출한다. 호출자가 더 큰 값을 요청한 경우는 그대로 존중한다.
        let effectiveHalo = max(halo, DefectContrastField.maximumDetectionSupportRadius)
        // 큰 ROI도 한 번에 최대 4타일만 실행한다. 모든 타일을 동시에 시작하면 각 타일의 full-size
        // Float 버퍼가 겹쳐 CPU·메모리 피크와 UI 프리징을 만든다. 배치 사이에서 취소도 반영한다.
        // 참고(2026-07-23 실측): 검출은 메모리 대역 바운드라 타일 동시성/내부 병렬을 바꿔도(1~10,
        // fieldParallel on/off) 전체 시간이 15~17초로 동일하다 — 병렬성이 아닌 알고리즘/GPU가 레버다.
        let maxConcurrentTiles = 4
        for batchStart in stride(from: 0, to: tileCount, by: maxConcurrentTiles) {
            if shouldCancel?() == true { return emptyField() }
            let batchCount = min(maxConcurrentTiles, tileCount - batchStart)
            DispatchQueue.concurrentPerform(iterations: batchCount) { offset in
                let t = batchStart + offset
                let cx = t % cols, cy = t / cols
                let coreX0 = cx * tw, coreY0 = cy * th
                let coreX1 = min(rw, coreX0 + tw), coreY1 = min(rh, coreY0 + th)
                guard coreX1 > coreX0, coreY1 > coreY0 else { return }
                let dx0 = max(0, coreX0 - effectiveHalo), dy0 = max(0, coreY0 - effectiveHalo)
                let dx1 = min(rw, coreX1 + effectiveHalo), dy1 = min(rh, coreY1 + effectiveHalo)
                let detectRect = CGRect(x: extent.minX + CGFloat(dx0), y: extent.minY + CGFloat(dy0),
                                        width: CGFloat(dx1 - dx0), height: CGFloat(dy1 - dy0))
                let field = SoftwareDefectDetector.detectLabeled(in: image, extent: detectRect, tuning: tuning,
                                                                   maxDustArea: maxDustArea,
                                                                   classificationMaxDustArea: classificationMaxDustArea,
                                                                   extendedDustScales: constrainedRegion,
                                                                   detectSpecks: parameters.detectMicroSpecks,
                                                                   rejectLineGrid: rejectLineGrid,
                                                                   preferredAngle: preferredAngle,
                                                                   fieldParallel: false)
                let r = RegionDefectTileResult(
                    dx0: dx0,
                    // detector 라벨 행은 bitmap 순서(y-down), dy0/dy1과 CIImage ROI는 y-up이다.
                    // 타일 원점과 core 경계를 영역 결함 제거 필드의 y-down 좌표 계약으로 바꿔 병합한다.
                    fieldY0: rh - dy1,
                    dw: Int(detectRect.width.rounded()),
                    coreX0: coreX0,
                    coreY0: rh - coreY1,
                    coreX1: coreX1,
                    coreY1: rh - coreY0,
                    field: field
                )
                results.set(r, at: t)
            }
        }
        if shouldCancel?() == true { return emptyField() }

        let field = stitchRegionDefectTiles(results.snapshot(), width: rw, height: rh)
        return wholeFrameAuto ? applyingWholeFrameAutomaticRiskFlag(to: field) : field
    }

    /// 자동(전체 프레임) 결과에 오검출 위험 플래그만 붙인다. **컴포넌트는 하나도 버리지 않는다.**
    /// 정상 구조가 대량 검출된 경우와 실제로 먼지가 많은 장면을 단일 RGB 이미지로 구분할 수 없어서
    /// 예전에는 자동을 통째로 중지했지만, 그러면 정작 먼지·스크래치가 많은 프레임에서 자동을 전혀
    /// 쓸 수 없었다. 이제는 결과를 그대로 돌려주고 UI가 경고만 표시한다 — 제외는 사용자가 한다.
    static func applyingWholeFrameAutomaticRiskFlag(to field: DefectLabelField) -> DefectLabelField {
        let area = field.width.multipliedReportingOverflow(by: field.height)
        guard !area.overflow, area.partialValue > 0 else { return field }
        let candidatePixels = field.components.reduce(into: 0) { count, component in
            let addition = count.addingReportingOverflow(component.pixelCount)
            count = addition.overflow ? area.partialValue : addition.partialValue
        }
        let fraction = Double(candidatePixels) / Double(area.partialValue)
        let fractionLimit = max(
            wholeFrameAutomaticCandidateFractionLimit,
            512.0 / Double(area.partialValue)
        )
        let risk = fraction > fractionLimit
            || maximumLocalCandidateDensity(of: field) > wholeFrameAutomaticLocalDensityLimit
        return DefectLabelField(
            width: field.width,
            height: field.height,
            labels: field.labels,
            components: field.components,
            automaticFalsePositiveRisk: risk,
            automaticCandidatePixelFraction: fraction
        )
    }

    /// 후보가 가장 몰린 국소 타일의 밀도. 경고 판정 입력이며 컴포넌트를 거르지 않는다.
    private static func maximumLocalCandidateDensity(of field: DefectLabelField) -> Double {
        guard !field.components.isEmpty,
              min(field.width, field.height) >= 1_024 else { return 0 }
        let tileSide = max(64, max(field.width, field.height) / 24)
        let columns = (field.width + tileSide - 1) / tileSide
        let rows = (field.height + tileSide - 1) / tileSide
        let tileCount = columns.multipliedReportingOverflow(by: rows)
        guard !tileCount.overflow, tileCount.partialValue > 0 else { return 0 }
        var counts = [Int](repeating: 0, count: tileCount.partialValue)
        for component in field.components {
            for pixel in component.pixels {
                guard pixel >= 0, pixel < field.width * field.height else { continue }
                let y = pixel / field.width
                let x = pixel - y * field.width
                counts[(y / tileSide) * columns + x / tileSide] += 1
            }
        }
        var maximumDensity = 0.0
        for row in 0..<rows {
            let tileHeight = min(tileSide, field.height - row * tileSide)
            for column in 0..<columns {
                let tileWidth = min(tileSide, field.width - column * tileSide)
                let density = Double(counts[row * columns + column]) / Double(tileWidth * tileHeight)
                maximumDensity = max(maximumDensity, density)
            }
        }
        return maximumDensity
    }

    /// 각 타일의 비중첩 core 픽셀을 전역 좌표로 옮기고 경계에서 8-연결 union한 뒤 라벨/픽셀을
    /// 한 번만 재구성한다. 기존 centroid-only 병합은 경계를 넘은 실제 결함을 통째로 버리거나 같은
    /// 픽셀을 중복 보관했다. dust와 scratch는 검출 계약이 다르므로 종류별로 stitch한다.
    private static func stitchRegionDefectTiles(
        _ results: [RegionDefectTileResult?],
        width: Int,
        height: Int
    ) -> DefectLabelField {
        var mapped: [MappedDefectComponent] = []
        for case let result? in results {
            for component in result.field.components where !component.pixels.isEmpty {
                let pixels = component.pixels.compactMap { pixel -> Int? in
                    let x = result.dx0 + pixel % result.dw
                    let y = result.fieldY0 + pixel / result.dw
                    // 각 픽셀은 halo 경계가 아니라 자신의 비중첩 core 타일 결과만 채택한다.
                    // 컴포넌트 centroid가 다른 core에 있다는 이유로 경계 반대편 픽셀을 통째로
                    // 버리던 누락을 막고, 동일 전역 픽셀이 여러 타일에 중복되는 것도 없앤다.
                    guard x >= result.coreX0, x < result.coreX1,
                          y >= result.coreY0, y < result.coreY1,
                          x >= 0, x < width, y >= 0, y < height else { return nil }
                    return y * width + x
                }
                guard !pixels.isEmpty else { continue }
                mapped.append(MappedDefectComponent(
                    kind: component.kind,
                    pixels: pixels,
                    classification: component.classification,
                    confidence: component.confidence
                ))
            }
        }

        var labels = [Int32](repeating: -1, count: width * height)
        var components: [DefectComponent] = []
        var nextID: Int32 = 0
        for kind in [DefectComponent.Kind.dust, .scratch] {
            let sameKind = mapped.filter { $0.kind == kind }
            guard !sameKind.isEmpty else { continue }
            var union = ComponentUnion(count: sameKind.count)
            var owner = [Int32](repeating: -1, count: width * height)
            for (index, component) in sameKind.enumerated() {
                for pixel in component.pixels {
                    if owner[pixel] >= 0 {
                        union.merge(index, Int(owner[pixel]))
                    } else {
                        owner[pixel] = Int32(index)
                    }
                }
            }
            // 비중첩 core로 자른 같은 결함의 양쪽 조각은 공통 픽셀이 없다. 전역 8-연결성으로
            // core 경계에서 다시 union해 하나의 컴포넌트로 복원한다. 소유 픽셀(희소)만 순회한다 —
            // 큰 ROI 에서 전체 픽셀 이중 루프와 [Int] 전체 스캔이 만들던 직렬 병목·메모리 피크를
            // 없앤다. 검사하는 (픽셀, 전방 이웃) 쌍 집합은 전체 스캔과 동일하므로 결과도 같다.
            let neighborOffsets = [(1, 0), (0, 1), (1, 1), (-1, 1)]
            for component in sameKind {
                for pixel in component.pixels {
                    let sourceOwner = owner[pixel]
                    guard sourceOwner >= 0 else { continue }
                    let y = pixel / width, x = pixel - y * width
                    for (ox, oy) in neighborOffsets {
                        let nx = x + ox, ny = y + oy
                        guard nx >= 0, nx < width, ny < height else { continue }
                        let targetOwner = owner[ny * width + nx]
                        if targetOwner >= 0, targetOwner != sourceOwner {
                            union.merge(Int(sourceOwner), Int(targetOwner))
                        }
                    }
                }
            }

            var pixelsByRoot = [[Int]](repeating: [], count: sameKind.count)
            for (index, component) in sameKind.enumerated() {
                for pixel in component.pixels where owner[pixel] == Int32(index) {
                    pixelsByRoot[union.root(of: index)].append(pixel)
                }
            }
            // 전체 스캔 순회와 동일한 픽셀 순서(오름차순)를 유지한다 — 미리보기 다운샘플이
            // 뽑는 점이 달라지지 않게 한다.
            for root in pixelsByRoot.indices where pixelsByRoot[root].count > 1 {
                pixelsByRoot[root].sort()
            }
            var metadataByRoot: [(classification: DefectClass, confidence: Double)?]
                = [Optional<(DefectClass, Double)>](repeating: nil, count: sameKind.count)
            for (index, component) in sameKind.enumerated() {
                let root = union.root(of: index)
                if metadataByRoot[root] == nil
                    || component.confidence > metadataByRoot[root]!.confidence {
                    metadataByRoot[root] = (component.classification, component.confidence)
                }
            }

            for root in pixelsByRoot.indices where !pixelsByRoot[root].isEmpty {
                let pixels = pixelsByRoot[root]
                var minX = width
                var minY = height
                var maxX = 0
                var maxY = 0
                for pixel in pixels {
                    let x = pixel % width
                    let y = pixel / width
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                    if labels[pixel] < 0 { labels[pixel] = nextID }
                }
                let metadata = metadataByRoot[root]!
                components.append(DefectComponent(
                    id: nextID,
                    kind: kind,
                    pixels: pixels,
                    minX: minX,
                    minY: minY,
                    maxX: maxX,
                    maxY: maxY,
                    classification: metadata.classification,
                    confidence: metadata.confidence
                ))
                nextID += 1
            }
        }
        return DefectLabelField(width: width, height: height, labels: labels, components: components)
    }

    /// 검출을 건너뛰고 주어진 마스크(흰색=제거)로 ROI 안을 복원한다. mask 는 image 와 같은 좌표계(roi
    /// 영역에 정렬)여야 한다. apply 의 복원 후반부(DefectScratchRepairer + CIBlendWithMask)와 동일하다.
    public static func repair(image: CIImage, roi: CGRect, mask: CIImage,
                              preferredAngle: Double? = nil) -> CIImage {
        repair(image: image, roi: roi, mask: mask,
               preparedMaskData: nil, preferredAngle: preferredAngle)
    }

    /// RGBA8 마스크 바이트를 이미 가진 Region/IR 경로용 진입점. 크기와 ROI가 정확히 맞을 때
    /// 마스크를 Core Image에서 다시 CPU로 렌더하지 않고 복원 코어에 그대로 전달한다.
    public static func repair(image: CIImage, roi: CGRect, maskRGBA8: Data,
                              width: Int, height: Int,
                              preferredAngle: Double? = nil) -> CIImage? {
        let extent = roi.integral.intersection(image.extent)
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (expectedBytes, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard extent.width > 1, extent.height > 1,
              width > 0, height > 0,
              !pixelOverflow, !byteOverflow,
              width == Int(extent.width.rounded()),
              height == Int(extent.height.rounded()),
              maskRGBA8.count == expectedBytes else { return nil }
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let mask = CIImage(
            bitmapData: maskRGBA8,
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: linear
        ).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        return repair(image: image, roi: extent, mask: mask,
                      preparedMaskData: maskRGBA8, preferredAngle: preferredAngle)
    }

    private static func repair(image: CIImage, roi: CGRect, mask: CIImage,
                               preparedMaskData: Data?,
                               preferredAngle: Double? = nil) -> CIImage {
        let extent = roi.integral.intersection(image.extent)
        guard extent.width > 1, extent.height > 1 else { return image }
        let source = image.cropped(to: extent)
        let mask = mask.cropped(to: extent)
        let median = medianFiltered(source).cropped(to: extent)
        let repairResult = DefectScratchRepairer.repairResult(image: source, mask: mask, extent: extent,
                                                           preferredAngle: preferredAngle,
                                                           preparedMaskData: preparedMaskData)
        let repairSource = repairResult?.image ?? median
        let blendMask = repairResult?.blendMask ?? mask
        let repaired = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: repairSource,
            kCIInputBackgroundImageKey: source,
            "inputMaskImage": blendMask,
        ])?.outputImage?.cropped(to: extent) ?? source
        // roi 가 이미지 일부면 복원한 roi 를 원본 위에 합성해 **전체 이미지**를 반환한다. roi 로
        // 다시 crop 하면 roi 조각만 남아, 호출측 createCGImage(from: 원본 전체 extent)에서 roi 밖이
        // 0=검정으로 채워진다 — "검은 배경 + 네모" 깨짐의 원인이었다.
        guard extent != image.extent else { return repaired.cropped(to: extent) }
        return repaired.composited(over: image).cropped(to: image.extent)
    }

    /// 편집된 컴포넌트(excluded 제외)를 렌더한 결함 마스크(RGBA8, 흰색=제거). 편집 히스토리에 저장해
    /// 두었다가 repair(image:roi:mask:)로 재적용하기 위한 진입점 — 무거운 DefectLabelField 전체 대신
    /// roi 크기의 마스크 bytes 만 보관하면 되므로 메모리에 가볍다.
    public static func componentMaskBytes(field: DefectLabelField, excluded: Set<Int32>,
                                          dustDilate: Int = 2,
                                          scratchDilate: Int = 1) -> [UInt8] {
        DefectComponentMask.renderMask(field, excluded: excluded,
                                    maxHoleArea: field.width * field.height,
                                    dustDilate: dustDilate,
                                    scratchDilate: scratchDilate)
    }

    /// componentMaskBytes 의 창 버전 — 필드 좌표(y-down) 창만 렌더한다. 창이 생존 컴포넌트
    /// bbox + 팽창 반경을 전부 덮으면 결과는 전체 렌더를 같은 창으로 자른 것과 바이트 동일하다.
    /// 큰 검출 ROI 에서 커밋 비용/메모리를 결함 창 크기 비례로 줄이는 진입점.
    public static func componentMaskBytes(field: DefectLabelField, excluded: Set<Int32>,
                                          dustDilate: Int = 2,
                                          scratchDilate: Int = 1,
                                          windowX: Int, windowY: Int,
                                          windowWidth: Int, windowHeight: Int) -> [UInt8] {
        DefectComponentMask.renderMaskWindow(field, excluded: excluded,
                                          maxHoleArea: field.width * field.height,
                                          dustDilate: dustDilate,
                                          scratchDilate: scratchDilate,
                                          windowX: windowX, windowY: windowY,
                                          windowWidth: windowWidth, windowHeight: windowHeight)
    }

    /// 편집된 컴포넌트(excluded 제외)를 마스크로 렌더해 ROI 안을 복원한다. DefectComponentMask 내부에
    /// 접근하지 않고 검출(detectComponents)→복원을 잇는 진입점이다. mask 좌표 정렬(roi 로 translate)도
    /// 여기서 처리한다. roi 는 검출에 쓴 CIImage(y-up) ROI 와 같아야 한다.
    public static func repairComponents(image: CIImage, roi: CGRect, field: DefectLabelField,
                                        excluded: Set<Int32>, dustDilate: Int = 2,
                                        scratchDilate: Int = 1) -> CIImage? {
        guard !field.isEmpty, field.width > 0, field.height > 0 else { return nil }
        let extent = roi.integral.intersection(image.extent)
        guard extent.width > 1, extent.height > 1 else { return nil }
        let maskBytes = DefectComponentMask.renderMask(field, excluded: excluded,
                                                    maxHoleArea: field.width * field.height,
                                                    dustDilate: dustDilate,
                                                    scratchDilate: scratchDilate)
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let maskData = Data(maskBytes)
        if let repaired = repair(image: image, roi: extent, maskRGBA8: maskData,
                                 width: field.width, height: field.height) {
            return repaired
        }
        let maskCI = CIImage(
            bitmapData: maskData, bytesPerRow: field.width * 4,
            size: CGSize(width: field.width, height: field.height),
            format: .RGBA8, colorSpace: linear
        ).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        return repair(image: image, roi: extent, mask: maskCI)
    }

    public static func detectMask(in image: CIImage,
                                  parameters: SoftwareDefectParameters = SoftwareDefectParameters(),
                                  brush: CIImage? = nil) -> CIImage {
        let extent = image.extent
        return detectMask(in: image, extent: extent, parameters: parameters, brush: brush)
    }

    private static func detectMask(in image: CIImage,
                                   extent: CGRect,
                                   parameters: SoftwareDefectParameters,
                                   brush: CIImage?,
                                   preferredAngle: Double? = nil) -> CIImage {
        return SoftwareDefectDetector.detect(
            in: image,
            extent: extent,
            tuning: SoftwareDefectDetector.Tuning(
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
