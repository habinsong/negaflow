import Foundation
import CoreGraphics
import CoreImage

// CIImage(raw 스캔 + IR 채널 TIFF) → Float 평면 렌더 → 코어 detect 호출.
extension InfraredDefectRemoval {

    /// raw 스캔(컬러)과 IR 채널 이미지를 받아 결함을 검출한다.
    /// IR 이미지 크기가 raw 와 다르면(백엔드 편차) raw 크기로 리샘플한 뒤 검출한다.
    public static func detect(raw: CIImage, infrared: CIImage,
                              parameters: Parameters = Parameters(),
                              isCancelled: (() -> Bool)? = nil) -> Result<Detection, Failure> {
        let extent = raw.extent.integral
        let width = Int(extent.width), height = Int(extent.height)
        guard width >= 64, height >= 64 else { return .failure(.tooSmall) }

        let rawOrigin = raw.transformed(by: CGAffineTransform(translationX: -extent.minX,
                                                              y: -extent.minY))
        var irImage = infrared
        let irExtent = irImage.extent.integral
        irImage = irImage.transformed(by: CGAffineTransform(translationX: -irExtent.minX,
                                                            y: -irExtent.minY))
        if Int(irExtent.width) != width || Int(irExtent.height) != height {
            guard irExtent.width > 1, irExtent.height > 1 else { return .failure(.unreadable) }
            let scaleX = extent.width / irExtent.width
            let scaleY = extent.height / irExtent.height
            irImage = irImage
                .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                .cropped(to: CGRect(x: 0, y: 0, width: extent.width, height: extent.height))
        }

        guard var red = renderRedPlane(rawOrigin, width: width, height: height),
              var ir = renderRedPlane(irImage, width: width, height: height) else {
            return .failure(.unreadable)
        }
        // 이 경로가 평면의 유일한 소유자다 — 소유권을 넘겨 단계별 조기 반납이 실제로 일어난다.
        return detectConsumingPlanes(infrared: &ir, red: &red,
                                     width: width, height: height,
                                     parameters: parameters, isCancelled: isCancelled)
    }

    /// R 채널을 단일 Float 평면(y-down 행 순서)으로 렌더한다.
    /// 풀프레임 RGBAf(픽셀당 16B)를 통째로 잡는 대신 가로 스트립으로 나눠 렌더해 임시 메모리를
    /// 상한(스트립 폭 × 256행)에 묶는다 — 55MP(V850 6400dpi)에서도 수십 MB 수준.
    static func renderRedPlane(_ image: CIImage, width: Int, height: Int) -> [Float]? {
        guard let linearRGB = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        let context = SamplingContextPool.context(workingColorSpace: linearRGB)
        var plane = [Float](repeating: 0, count: width * height)
        let stripRows = max(16, min(256, height))
        var strip = [Float](repeating: 0, count: width * stripRows * 4)
        var topRow = 0   // y-down
        while topRow < height {
            let rows = min(stripRows, height - topRow)
            // y-down 행 [topRow, topRow+rows) = CI(y-up) 사각형 y ∈ [height-topRow-rows, height-topRow).
            let bounds = CGRect(x: 0, y: CGFloat(height - topRow - rows),
                                width: CGFloat(width), height: CGFloat(rows))
            strip.withUnsafeMutableBytes { rawBuffer in
                context.render(
                    image,
                    toBitmap: rawBuffer.baseAddress!,
                    rowBytes: width * 4 * MemoryLayout<Float>.size,
                    bounds: bounds,
                    format: .RGBAf,
                    colorSpace: linearRGB
                )
            }
            for r in 0..<rows {
                let dst = (topRow + r) * width
                let src = r * width * 4
                for x in 0..<width { plane[dst + x] = strip[src + x * 4] }
            }
            topRow += rows
        }
        return plane
    }
}
