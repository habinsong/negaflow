import CoreGraphics
import CoreImage
import Foundation

// 결함 제거 계열 테스트 파일마다 사본으로 존재하던 RGBA8 픽스처 헬퍼의 단일 구현.
// 각 파일의 private 헬퍼는 자기 컬러스페이스를 넘기는 포워더만 남긴다.

/// RGBA8 픽셀 배열(y-down 행 순서) → CIImage.
func makeRGBA8CIImage(_ px: [UInt8], _ w: Int, _ h: Int,
                      colorSpace: CGColorSpace) -> CIImage {
    CIImage(bitmapData: Data(px), bytesPerRow: w * 4,
            size: CGSize(width: w, height: h), format: .RGBA8, colorSpace: colorSpace)
}

/// CIImage → RGBA8 렌더(working/출력 컬러스페이스 동일).
func renderRGBA8Pixels(_ img: CIImage, _ w: Int, _ h: Int,
                       colorSpace: CGColorSpace) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: w * h * 4)
    CIContext(options: [.workingColorSpace: colorSpace]).render(
        img, toBitmap: &out, rowBytes: w * 4,
        bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8,
        colorSpace: colorSpace)
    return out
}
