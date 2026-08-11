import CoreGraphics
import Foundation
import ImageIO

/// 프리뷰의 실제 물리 크기를 아는 상태에서 필름 프레임을 찾는다.
///
/// 에지 기반 검출기는 프레임 비율만 알고 경계를 추측하므로 필름 내용에 휘둘린다. 평판 프리뷰는
/// 스캔한 영역이 몇 mm인지 이미 알고 있으므로 규격이 몇 px인지 정확히 계산할 수 있다. 이
/// 검출기는 그 사전지식을 쓴다.
///
/// 순서는 홀더 구조를 그대로 따라간다.
///   1. 열 질감 프로파일 — **필름에만 그레인과 그림이 있다.**
///   2. 질감이 살아 있는 열을 슬롯으로 묶는다. 빈 창·흰 바탕·홀더 마스크는 균일해서 떨어진다.
///   3. 규격 폭에 맞지 않거나 스캔 영역에 걸려 잘린 슬롯을 버린다.
///   4. 슬롯 안에서 필름이 놓인 세로 구획을 찾는다.
///   5. 구획마다 여백 주기를 **재서** 격자를 세우고, 경계마다 국소 보정한다.
///
/// 1단계가 핵심이다. 밝기로 필름을 가리면 한 슬롯만 채운 홀더에서 빈 창(0.92)이 필름(0.10)보다
/// 밝아 빈 창을 집고 진짜 필름을 버린다 — 실측으로 확인한 실패다.
public enum FlatbedFrameGridDetector {

    /// 검출에 쓸 프리뷰 한 장. 밝기는 0...1 로 정규화된 행 우선 배열이다.
    public struct Preview: Sendable {
        public let luminance: [Double]
        public let width: Int
        public let height: Int
        /// 이 프리뷰가 담고 있는 실제 영역(mm).
        public let physicalSize: CGSize

        public init(luminance: [Double], width: Int, height: Int, physicalSize: CGSize) {
            self.luminance = luminance
            self.width = width
            self.height = height
            self.physicalSize = physicalSize
        }

        var pixelsPerMillimeterX: Double { Double(width) / physicalSize.width }
        var pixelsPerMillimeterY: Double { Double(height) / physicalSize.height }

        /// 프리뷰 파일에서 밝기만 뽑아 온다. 축소 한도를 낮게 잡으면 안 된다 — 35mm 프레임
        /// 사이 여백은 2mm 뿐이라 1024px 로 줄이면 뭉개져서 컷을 놓친다(실측 12개 중 4개).
        public init?(url: URL, physicalSize: CGSize, maxAnalysisDimension: Int = 2_048) {
            guard physicalSize.width > 0, physicalSize.height > 0,
                  maxAnalysisDimension >= 128,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(
                      source,
                      0,
                      [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: false,
                          kCGImageSourceThumbnailMaxPixelSize: maxAnalysisDimension,
                      ] as CFDictionary
                  ) else { return nil }
            self.init(image: image, physicalSize: physicalSize)
        }

        public init?(image: CGImage, physicalSize: CGSize) {
            let width = image.width
            let height = image.height
            guard width > 0, height > 0,
                  physicalSize.width > 0, physicalSize.height > 0 else { return nil }
            var gray = [UInt8](repeating: 0, count: width * height)
            // 선형 그레이로 그리면 감마가 풀려 어두운 쪽이 더 눌린다. 홀더와 필름을 가르는
            // 임계가 그만큼 흔들리므로, 스캔이 담고 있는 표시 감마 그대로 읽는다.
            guard let space = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
                  let context = gray.withUnsafeMutableBytes({ buffer -> CGContext? in
                      CGContext(
                          data: buffer.baseAddress,
                          width: width,
                          height: height,
                          bitsPerComponent: 8,
                          bytesPerRow: width,
                          space: space,
                          bitmapInfo: CGImageAlphaInfo.none.rawValue
                      )
                  }) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            self.init(
                luminance: gray.map { Double($0) / 255 },
                width: width,
                height: height,
                physicalSize: physicalSize
            )
        }
    }

    /// 규격을 픽셀로 옮긴 값.
    ///
    /// `stripWidthMM` 은 **스트립을 따라가는** 축의 이미지 길이(=프레임 피치 방향), `stripHeightMM`
    /// 은 **스트립 폭 방향**의 이미지 길이(=슬롯 폭)다. 예전 코드는 이 둘을 min/max 로 골라서
    /// 하프프레임(18×24)과 645(41.5×56)에서 두 축이 뒤바뀌었다.
    struct FrameGeometry {
        let alongMM: Double
        let acrossMM: Double
        let gapRangeMM: ClosedRange<Double>
        /// 35mm 는 퍼포레이션이 이송을 정해 피치가 사실상 고정(36+여백)이다. 120 은 카메라
        /// 이송 기구가 정하므로 노광 길이 자체가 흔들린다.
        let hasRigidPitch: Bool
        let pixelsPerMillimeterX: Double
        let pixelsPerMillimeterY: Double

        init(format: FilmFrameFormat, preview: Preview) {
            alongMM = format.stripWidthMM
            acrossMM = format.stripHeightMM
            gapRangeMM = FlatbedFrameGridDetector.gapRangeMM(for: format)
            hasRigidPitch = format.is35mm
            pixelsPerMillimeterX = preview.pixelsPerMillimeterX
            pixelsPerMillimeterY = preview.pixelsPerMillimeterY
        }

        var alongPixelsY: Double { alongMM * pixelsPerMillimeterY }
        var acrossPixelsX: Double { acrossMM * pixelsPerMillimeterX }
        var gapMinPixelsY: Double { gapRangeMM.lowerBound * pixelsPerMillimeterY }
        var gapMaxPixelsY: Double { gapRangeMM.upperBound * pixelsPerMillimeterY }

        /// 빗살 탐색 범위 = 노광 길이 + 여백. 어떤 카메라·필름·홀더인지 모르므로 피치를 특정
        /// 값으로 못 박지 않는다. 다만 무한정 열면 필름 내용의 주기에 물리므로(실측에서 38mm
        /// 스트립이 40.9mm 로 잡혔다) 규격이 허용하는 범위까지만 연다. 35mm 는 이송이
        /// 퍼포레이션에 묶여 노광 길이가 거의 흔들리지 않고, 120 은 카메라 이송 기구가 정하므로
        /// 노광 길이까지 함께 흔들린다.
        var pitchRangePixelsY: ClosedRange<Double> {
            let slack = hasRigidPitch ? 0.02 : 0.05
            let low = alongMM * (1 - slack) + gapRangeMM.lowerBound
            let high = alongMM * (1 + slack) + gapRangeMM.upperBound
            return (low * pixelsPerMillimeterY)...(high * pixelsPerMillimeterY)
        }
    }

    /// 프레임 사이 여백. 35mm 는 퍼포레이션 이송이 정하므로 사실상 고정(38mm 피치 → 2mm)이고,
    /// 120 은 카메라 이송 기구에 달려 있어 표준이 없다. 그래서 120 은 넓게 잡는다.
    static func gapRangeMM(for format: FilmFrameFormat) -> ClosedRange<Double> {
        format.is35mm ? 1.0...3.5 : 2.0...9.0
    }

    /// 프리뷰 파일에서 바로 검출한다. `physicalSize` 는 그 스캔이 담은 실제 영역(mm)이다.
    public static func detect(
        url: URL,
        physicalSize: CGSize,
        frameFormat: FilmFrameFormat,
        maxAnalysisDimension: Int = 2_048
    ) -> [FlatbedFrameDetection] {
        guard let preview = Preview(
            url: url,
            physicalSize: physicalSize,
            maxAnalysisDimension: maxAnalysisDimension
        ) else { return [] }
        return detect(preview: preview, frameFormat: frameFormat)
    }

    public static func detect(
        preview: Preview,
        frameFormat: FilmFrameFormat
    ) -> [FlatbedFrameDetection] {
        guard preview.width > 32,
              preview.height > 32,
              preview.luminance.count == preview.width * preview.height,
              preview.physicalSize.width > 0,
              preview.physicalSize.height > 0 else { return [] }

        let geometry = FrameGeometry(format: frameFormat, preview: preview)
        guard geometry.alongPixelsY >= 8, geometry.acrossPixelsX >= 8 else { return [] }

        let columns = ColumnProfiles(preview: preview)
        let slots = slots(preview: preview, profiles: columns, geometry: geometry)
        guard !slots.isEmpty else { return [] }
        let floor = noiseFloor(profiles: columns, slots: slots, width: preview.width)

        var detections: [FlatbedFrameDetection] = []
        for (row, slot) in slots.enumerated() {
            let rows = RowProfiles(preview: preview, slot: slot.measured)
            let bands = filmBands(
                preview: preview,
                slot: slot,
                rows: rows,
                geometry: geometry
            )
            var column = 0
            for band in bands {
                let evidence = gapEvidence(rows: rows, band: band, geometry: geometry)
                guard let grid = fitGrid(evidence: evidence, geometry: geometry) else { continue }
                let spans = frameSpans(grid: grid, band: band, geometry: geometry)
                for span in occupied(spans, rows: rows, noiseFloor: floor, height: preview.height) {
                    detections.append(FlatbedFrameDetection(
                        normalizedRect: CGRect(
                            x: Double(slot.snapped.lowerBound) / Double(preview.width),
                            y: span.lowerBound / Double(preview.height),
                            width: Double(slot.snapped.count) / Double(preview.width),
                            height: (span.upperBound - span.lowerBound) / Double(preview.height)
                        ),
                        straightenAngle: 0,
                        confidence: grid.confidence,
                        row: row,
                        column: column
                    ))
                    column += 1
                }
            }
        }
        return detections
    }

    /// 격자가 필름 밖으로 한 칸 삐져나간 컷을 걷어낸다.
    ///
    /// 구획은 필름이 놓인 범위를 잡지만 완벽하지 않다 — 사제 홀더에서 필름 위쪽 빈 창까지
    /// 구획에 들어가 격자가 그 자리에 컷 하나를 만들어 냈다(실측). 기준은 **같은 스트립의 다른
    /// 컷들**이다. 절대값을 쓰면 필름·스캐너마다 다시 맞춰야 하지만, 옆 컷과의 비교는 그대로
    /// 통한다.
    static func occupied(
        _ spans: [Range<Double>],
        rows: RowProfiles,
        noiseFloor: Double,
        height: Int
    ) -> [Range<Double>] {
        guard spans.count > 1 else { return spans }
        // 컷마다 그레인의 중앙값. 평균이 아니라 중앙값이라 홀더 경계 몇 행이 섞여도 흔들리지 않는다.
        let levels = spans.map { span -> Double in
            let lower = max(0, Int(span.lowerBound.rounded()))
            let upper = min(height, Int(span.upperBound.rounded()))
            guard upper > lower else { return 0 }
            return median((lower..<upper).map { rows.grain[$0] })
        }
        // 문턱은 홀더에서 잰 잡음 바닥이다. 상수를 박으면 스캐너·해상도가 바뀔 때마다 다시
        // 맞춰야 하지만, "필름이 아닌 곳은 이만큼 조용하다"는 같은 스캔 안에서 늘 성립한다.
        // 필름이 없는 자리는 광원이나 마스크가 그대로 보이는 균일면이라 **홀더보다도 조용하다**
        // (실측 0.00000 vs 홀더 잡음 바닥). 반대로 아무리 평평한 컷이라도 필름이 얹혀 있으면
        // 그보다는 시끄럽다. 그래서 바닥 그 자체를 문턱으로 쓴다.
        let threshold = noiseFloor * 2
        guard threshold > 0 else { return spans }
        // **양끝에서만 걷어낸다.** 가운데 컷은 위아래가 필름이므로 그 자리에도 필름이 있다 —
        // 미노광이라 그림이 없을 뿐이다. 그걸 지우면 롤에서 컷 하나가 사라진다.
        var lower = spans.startIndex
        var upper = spans.endIndex
        while lower < upper, levels[lower] < threshold { lower += 1 }
        while upper > lower, levels[upper - 1] < threshold { upper -= 1 }
        return Array(spans[lower..<upper])
    }

    /// 이웃한 두 여백 중심 사이가 컷 하나다. 자리는 **잰 경계**가 정하고 크기는 **규격**이
    /// 정한다 — 필름 폭과 노광 폭은 물리적으로 정해져 있고, 잰 값은 평평한 그림에서 좁아진다.
    static func frameSpans(
        grid: StripGrid,
        band: Range<Int>,
        geometry: FrameGeometry
    ) -> [Range<Double>] {
        let length = geometry.alongPixelsY
        let bandLength = Double(band.count)
        var spans: [Range<Double>] = []
        for (start, end) in zip(grid.boundaries, grid.boundaries.dropFirst()) {
            let center = (start + end) / 2
            let lower = center - length / 2
            let upper = center + length / 2
            // 잘린 조각을 내보내면 본 스캔이 엉뚱한 영역을 찍는다. 반대로 너무 빡빡하게 잡으면
            // 랩이 컷 한가운데를 자른 스트립에서 맨 앞 컷이 통째로 사라진다(실측). 대부분
            // 들어와 있으면 살린다.
            let overlap = min(upper, bandLength) - max(lower, 0)
            guard overlap >= length * 0.8 else { continue }
            spans.append(
                (Double(band.lowerBound) + lower)..<(Double(band.lowerBound) + upper)
            )
        }
        return spans
    }
}
