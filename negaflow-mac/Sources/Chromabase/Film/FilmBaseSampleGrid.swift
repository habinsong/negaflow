import CoreGraphics
import CoreImage

struct FilmBaseSample: Sendable {
    let x: Int
    let y: Int
    let color: SIMD3<Double>

    var luma: Double {
        (color.x + color.y + color.z) / 3
    }
}

struct FilmBaseSampleGrid: Sendable {
    let width: Int
    let height: Int
    let samples: [FilmBaseSample]

    init?(image: CIImage) {
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0 else { return nil }

        let width = max(32, min(256, Int(extent.width)))
        let scale = Double(width) / Double(extent.width)
        let height = max(1, Int(Double(extent.height) * scale))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        // 색관리 linear 샘플링 — 반전(NegativeInversion)이 base 를 소비하는 도메인과 동일.
        // 과거의 비색관리(raw 직독)는 스캐너 raw(linear 태그)에서만 우연히 일치했고, ICC 태그된
        // 가져오기/시뮬레이터 파일(sRGB 감마)에서는 감마 인코딩 값을 그대로 돌려줘 base 가
        // 감마 도메인으로 부풀었다(linear 0.3 → 0.58) — 반전이 하얗고 파랗게 뜨는 원인.
        let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        var bitmap = [Float](repeating: 0, count: width * height * 4)
        SamplingContextPool.context(workingColorSpace: colorSpace).render(
            scaled,
            toBitmap: &bitmap,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: colorSpace
        )

        var samples: [FilmBaseSample] = []
        samples.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                samples.append(FilmBaseSample(
                    x: x,
                    y: y,
                    color: SIMD3(
                        Double(bitmap[offset]),
                        Double(bitmap[offset + 1]),
                        Double(bitmap[offset + 2])
                    )
                ))
            }
        }

        self.width = width
        self.height = height
        self.samples = samples
    }

    private init(width: Int, height: Int, samples: [FilmBaseSample]) {
        self.width = width
        self.height = height
        self.samples = samples
    }

    /// 크롭(사진) 영역 안의 셀을 검정으로 지운 사본 — 베이스 후보를 크롭 바깥 띠에서만 찾는다.
    /// 지운 셀은 후보 판정(최소 luma)을 통과하지 못해 성분·모드·바닥 계산에 끼지 않는다.
    func excludingInterior(of region: AnalysisRegion) -> FilmBaseSampleGrid {
        let masked = samples.map { sample -> FilmBaseSample in
            guard isInterior(sample, of: region) else { return sample }
            return FilmBaseSample(x: sample.x, y: sample.y, color: .zero)
        }
        return FilmBaseSampleGrid(width: width, height: height, samples: masked)
    }

    /// 크롭(사진) 영역 **밖**의 셀을 검정으로 지운 사본 — 띠에 베이스가 없을 때 사진 안에서만 찾는다.
    func keepingInterior(of region: AnalysisRegion) -> FilmBaseSampleGrid {
        let masked = samples.map { sample -> FilmBaseSample in
            guard !isInterior(sample, of: region) else { return sample }
            return FilmBaseSample(x: sample.x, y: sample.y, color: .zero)
        }
        return FilmBaseSampleGrid(width: width, height: height, samples: masked)
    }

    /// 셀이 크롭(사진) 영역에 걸치는가 — 바깥으로 정수화한 격자 사각형 기준.
    func isInterior(_ sample: FilmBaseSample, of region: AnalysisRegion) -> Bool {
        // 격자 행 0 = 위(CI y 최대). 영역은 CI y-up 정규 좌표다.
        let rect = region.unitRect
        let x0 = Int((rect.minX * Double(width)).rounded(.down))
        let x1 = Int((rect.maxX * Double(width)).rounded(.up))
        let y0 = Int(((1 - rect.maxY) * Double(height)).rounded(.down))
        let y1 = Int(((1 - rect.minY) * Double(height)).rounded(.up))
        return sample.x >= x0 && sample.x < x1 && sample.y >= y0 && sample.y < y1
    }
}
