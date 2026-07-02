import Foundation
import CoreGraphics
import ImageIO

// MARK: - ScanTempFile
//
// 스캔 임시 파일/이미지 크기 조회 같은 범용 헬퍼. 특정 백엔드(SANE 등)와 무관하며,
// 과거 SANEBackend 에 붙어 있던 static 유틸을 SANE 분리 후에도 쓸 수 있게 여기로 옮겼다.
public enum ScanTempFile {
    /// 임시 디렉토리에 겹치지 않는 스크래치 파일 URL을 만든다(스캔 산출 TIFF 등).
    public static func makeURL(prefix: String, suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString)\(suffix)")
    }

    /// 이미지 파일의 픽셀 크기를 디코딩 없이 조회한다. 실패 시 (0,0).
    public static func imageSize(at url: URL) -> (Int, Int) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
              let w = props["PixelWidth"] as? Int,
              let h = props["PixelHeight"] as? Int
        else { return (0, 0) }
        return (w, h)
    }
}
