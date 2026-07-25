import SwiftUI
import Chromabase
import CoreImage
import AppKit

// 결함 제거(브러시 결함 제거 + 가이드 영역 결함 제거)를 원본 raw 스캔에 직접 적용하고, 결함 제거된 raw(cleaned raw)를
// 현상·export 입력으로 쓴다. 그래서 Target/Profile/Film/Mode·인스펙터 전 항목을 바꿔도 결함 제거가
// 유지되고 재계산되지 않는다.
//
// 통합 편집 모델(핵심): cleaned raw = 원본 raw + frame.defectEdits(켜진 항목) 순차 적용. 브러시와
// 가이드가 같은 [DefectEditItem] 리스트에 순서대로 쌓이므로, 한쪽을 rebuild 해도 다른 쪽이 재적용돼
// 보존된다 — 서로 되살아나지 않는다.
//
// 성능 구조(2026-07-04):
//  • 레이어 결과는 "강도 1.0 패치"(변경 rect 만, DefectPatch)로 캐시된다 — 강도/켜기 변경은
//    heal/검출 재계산 없이 패치 합성(상수 알파 블렌드)만 한다. 캐시는 그 레이어가 계산될 때의
//    베이스 기준이므로 "앞선" 레이어가 바뀌면 뒤 레이어들의 캐시를 무효화한다.
//  • 빌드는 CIImage 체인으로 쌓고 마지막에 1회만 풀해상도 flatten 한다(레이어당 flatten 제거).
//  • 마지막 레이어 직전까지의 cleaned raw(cleanedRawPreviousImage)를 메모리에 유지 — 마지막
//    레이어의 강도/켜기/삭제는 원본 디코드·전체 재적용 없이 "베이스 + 캐시 패치"로 즉시 끝난다.
//  • 디스크 백킹(TIFF) 저장은 커밋 후 비동기로 수행해 화면 반영 지연에서 제거했고, 슬라이더
//    드래그 중(live)에는 저장을 건너뛴다(드래그 끝에 1회 저장).
//
// 캐시 정책(메모리 폭주 방지):
//  • cleanedRawImage/cleanedRawPreviousImage(메모리, 16bit linear CGImage) = 활성 프레임 소수만
//    FIFO로 적재. 다른 프레임으로 이동하면 내려놓되, cleanedRawDiskURL(LZW TIFF)에 백킹해 두어
//    재진입 시 결함 제거 재계산 없이 즉시 복원한다.
//  • 디스크 백킹은 앱 시작 시 청소되어 공간을 남기지 않는다(negaflowApp.init).

private let defectRemovalParameters = SoftwareDefectParameters(
    strength: 1, dustSensitivity: 0.6, scratchSensitivity: 0.7, protectDetail: 0.6
)

/// 세션 안 원본 파일 검증 결과(stat 관찰값 비교 — 콘텐츠 해시 없음).
enum CaptureFileVerificationResult: Equatable {
    case match
    case mismatch
    case unavailable
}

let defectRecipeLiveCoalescingNanoseconds: UInt64 = 40_000_000

let linearColorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)!

// raw 도메인(16bit linear)에서 cleaned raw를 평탄화/디코딩하는 컨텍스트.
let cleanedRawContext = CIContext(options: [
    .useSoftwareRenderer: false,
    .workingColorSpace: linearColorSpace,
    .outputColorSpace: linearColorSpace,
])

func decodeCleanedRaw(_ url: URL) -> CGImage? {
    autoreleasepool {
        guard let ci = ImageLoader.loadScannerTIFF(url) else { return nil }
        return cleanedRawContext.createCGImage(ci, from: ci.extent, format: .RGBA16, colorSpace: linearColorSpace)
    }
}

/// 레이어의 강도 1.0 패치를 계산한다(brush=heal/검출 패치, region=마스크 복원 roi 패치).
/// base 는 앞선 레이어들이 적용된 16bit linear CGImage. 실패/취소면 nil.
func computeDefectPatches(_ edit: DefectEdit, base: CGImage,
                                  shouldCancel: @escaping @Sendable () -> Bool) -> [DefectPatch]? {
    computeDefectPatches(edit,
                         base: CIImage(cgImage: base, options: [.colorSpace: linearColorSpace]),
                         pixelWidth: base.width, pixelHeight: base.height,
                         shouldCancel: shouldCancel)
}

/// CIImage 체인 버전. 빌드 경로가 캐시 미스 레이어마다 풀해상도 RGBA16 flatten 을 만들지 않고,
/// 각 레이어가 실제로 읽는 국소 창만 체인에서 렌더한다 — 체인의 패치 합성은 전부 픽셀 단위
/// 연산이라 창 렌더 결과는 같은 체인을 통째로 flatten 한 값과 동일하다.
func computeDefectPatches(_ edit: DefectEdit, base: CIImage,
                          pixelWidth: Int, pixelHeight: Int,
                          shouldCancel: @escaping @Sendable () -> Bool) -> [DefectPatch]? {
    switch edit {
    case .brush(let strokes):
        guard !strokes.isEmpty else { return [] }
        return DefectBrush.removeDefectsPatches(over: base,
                                                pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                                                strokes: strokes,
                                                parameters: defectRemovalParameters,
                                                linear16: true, shouldCancel: shouldCancel)
    case .region(let mask, let roi, let w, let h):
        guard w > 0, h > 0 else { return [] }
        let (pixels, pixelOverflow) = w.multipliedReportingOverflow(by: h)
        let (expectedBytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        guard !pixelOverflow, !byteOverflow,
              let rawMask = try? mask.validatedRawBytes(maximumOutputBytes: expectedBytes),
              rawMask.count == expectedBytes else { return nil }
        guard let patch = regionPatch(img: base, mask: rawMask, roi: roi, width: w, height: h) else {
            return nil
        }
        return [patch]
    case .infrared(let clusters):
        guard !clusters.isEmpty else { return [] }
        // 클러스터별 독립 복원(서로 겹치지 않는 결함 bbox 타일) — region 과 동일한 복원 코어.
        var patches: [DefectPatch] = []
        patches.reserveCapacity(clusters.count)
        for cluster in clusters {
            if shouldCancel() { return nil }
            guard let patch = regionPatch(img: base, mask: cluster.maskRGBA8, roi: cluster.roiYup,
                                          width: cluster.width, height: cluster.height) else {
                return nil
            }
            patches.append(patch)
        }
        return patches
    case .clone(let strokes):
        guard !strokes.isEmpty else { return [] }
        return CloneStampBrush.patches(over: base, pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                                       strokes: strokes, shouldCancel: shouldCancel)
    }
}

/// 마스크(RGBA8, 흰=제거) 하나를 roi 에 정렬해 복원하고 강도 1.0 패치로 만든다.
/// region / infrared 클러스터가 공유하는 복원 단위.
private func regionPatch(img: CIImage, mask: Data, roi: CGRect,
                         width: Int, height: Int) -> DefectPatch? {
    guard !mask.isEmpty, width > 0, height > 0,
          let bitmapMaskBounds = nonzeroMaskBounds(mask, width: width, height: height) else { return nil }
    // 마스크 바이트는 비트맵 행 순서(y-down, 첫 행 = 위)다. CIImage(bitmapData:)는 첫 행을 이미지
    // 위쪽(y-up 최댓값 쪽)에 놓으므로, 패치 rect 는 y-up 로컬 좌표로 뒤집은 뒤 roi 로 평행이동해야
    // 한다. y-down 값을 그대로 쓰면 rect 가 ROI 수직 중앙 기준으로 반사돼, 중앙에서 벗어난 결함의
    // 복원 픽셀이 패치 밖으로 떨어진다 — "제거를 눌렀는데 그 자리만 그대로"의 원인.
    let localMaskBounds = CGRect(
        x: bitmapMaskBounds.origin.x,
        y: CGFloat(height) - bitmapMaskBounds.origin.y - bitmapMaskBounds.height,
        width: bitmapMaskBounds.width,
        height: bitmapMaskBounds.height
    )
    guard let repaired = SoftwareDefectRemoval.repair(image: img, roi: roi, maskRGBA8: mask,
                                            width: width, height: height) else { return nil }
    // 복원 계산은 기존 ROI 전체 문맥을 그대로 사용하되, 캐시에는 실제 마스크가 바꾼 사각형만
    // 렌더한다. 품질/픽셀은 같고, 넓은 ROI 안의 희소 결함이 RGBA16 ROI 전체를 붙잡지 않는다.
    let rect = localMaskBounds
        .offsetBy(dx: roi.minX, dy: roi.minY)
        .integral
        .intersection(roi.integral)
        .intersection(img.extent)
    guard rect.width >= 1, rect.height >= 1,
          let patch = cleanedRawContext.createCGImage(repaired, from: rect,
                                                      format: .RGBA16, colorSpace: linearColorSpace)
    else { return nil }
    return DefectPatch(rect: rect, image: patch)
}

/// 렌더된 결함 마스크(RGBA8, y-down)를 "결함 경계 + 복원 문맥 여백" 창으로 잘라 저장용
/// (마스크, y-up ROI)를 만든다. 복원 샘플링 도달 거리(SoftwareDefectRemoval.repairContextRadius)보다 넓은
/// 여백을 유지하므로, 잘린 ROI 로 복원해도 결과 픽셀은 전체 ROI 복원과 동일하다. 반환 마스크는
/// 창 크기 그대로의 비트맵(y-down)이며 roi 는 원본 roiYup 안의 창 위치(y-up)다.
/// 큰 검출 ROI 에서 zlib/디컴프레스/스캔 비용과 상주 메모리를 결함 크기 비례로 줄인다.
func croppedRegionMaskBytes(
    _ bytes: [UInt8], width: Int, height: Int, roiYup: CGRect, margin: Int
) -> (mask: [UInt8], roi: CGRect, width: Int, height: Int)? {
    guard width > 0, height > 0, bytes.count == width * height * 4 else { return nil }
    var minX = width, minY = height, maxX = -1, maxY = -1
    bytes.withUnsafeBufferPointer { buffer in
        let raw = buffer.baseAddress!
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where raw[(row + x) * 4] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    let x0 = max(0, minX - margin), x1 = min(width, maxX + 1 + margin)
    let y0 = max(0, minY - margin), y1 = min(height, maxY + 1 + margin)   // y-down 창 [y0, y1)
    let cw = x1 - x0, ch = y1 - y0
    guard cw > 0, ch > 0 else { return nil }
    if cw == width, ch == height {
        return (bytes, roiYup, width, height)
    }
    var cropped = [UInt8](repeating: 0, count: cw * ch * 4)
    cropped.withUnsafeMutableBufferPointer { dst in
        bytes.withUnsafeBufferPointer { src in
            for y in 0..<ch {
                let srcOffset = ((y + y0) * width + x0) * 4
                let dstOffset = y * cw * 4
                dst.baseAddress!.advanced(by: dstOffset)
                    .update(from: src.baseAddress!.advanced(by: srcOffset), count: cw * 4)
            }
        }
    }
    // y-down 창 [y0, y1) → y-up 오프셋: 창의 아래쪽 여백(height - y1)만큼 roi 바닥에서 올라간다.
    let roi = CGRect(x: roiYup.minX + CGFloat(x0),
                     y: roiYup.minY + CGFloat(height - y1),
                     width: CGFloat(cw), height: CGFloat(ch))
    return (cropped, roi, cw, ch)
}

private func nonzeroMaskBounds(_ mask: Data, width: Int, height: Int) -> CGRect? {
    let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
    let (expected, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
    guard width > 0, height > 0, !pixelOverflow, !byteOverflow,
          mask.count == expected else { return nil }
    var minX = width, minY = height, maxX = -1, maxY = -1
    mask.withUnsafeBytes { raw in
        let bytes = raw.bindMemory(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width where bytes[(y * width + x) * 4] > 8 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}
