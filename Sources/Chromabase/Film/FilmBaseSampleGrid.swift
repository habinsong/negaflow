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
}
