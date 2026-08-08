import AppKit
import Chromabase
import CoreGraphics
import CoreImage
import XCTest
@testable import negaflowApp

// Region/IR 패치의 좌표 규약 회귀 테스트.
//
// 마스크 바이트는 비트맵 행 순서(y-down)이고 패치 rect 는 CIImage(y-up) 좌표다. 이 변환이
// 빠지면 rect 가 ROI 수직 중앙 기준으로 반사돼, 중앙에서 벗어난 결함은 "제거"를 눌러도
// 복원 픽셀이 패치 밖으로 떨어져 화면에 그대로 남는다(재시도해도 동일 — 실사용 보고 버그).
// 합성 픽스처 + 수치 측정만 사용한다.
@MainActor
final class RegionPatchOrientationTests: XCTestCase {
    private let width = 96
    private let height = 72
    // 결함: 비트맵 행 8..11(위쪽), 열 20..23 — 수직 중앙(36)에서 크게 벗어난 위치.
    private let defectX = 20..<24
    private let defectYDown = 8..<12

    func testOffCenterDefectPatchRectIsYUpAndRepairsPixels() throws {
        let base = try makeBase()
        let edit = DefectEdit.region(
            mask: DefectCompressedData.raw(makeMaskData()).compressed(),
            roi: CGRect(x: 0, y: 0, width: width, height: height),
            width: width,
            height: height
        )
        let patches = try XCTUnwrap(computeDefectPatches(edit, base: base, shouldCancel: { false }))
        let patch = try XCTUnwrap(patches.first)

        // rect 는 y-up: 행 8..11 → y = 72 - 12 = 60.
        let expected = CGRect(x: 20, y: 60, width: 4, height: 4)
        XCTAssertTrue(patch.rect.contains(expected),
                      "patch rect \(patch.rect) 가 결함 y-up 위치 \(expected) 를 덮지 않음(수직 반사 의심)")

        // 합성 후 결함 영역이 배경 톤으로 복원됐는지 수치로 확인한다.
        let composited = patch.composited(
            over: CIImage(cgImage: base, options: [.colorSpace: linearColorSpace]),
            strength: 1.0,
            colorSpace: linearColorSpace
        )
        let pixels = render(composited)
        let defectMean = meanLuma(pixels, xRange: defectX, yDownRange: defectYDown)
        let backgroundMean = meanLuma(pixels, xRange: 60..<70, yDownRange: 50..<60)
        XCTAssertEqual(defectMean, backgroundMean, accuracy: 0.05,
                       "결함 영역이 복원되지 않음(전 0.9 근처면 흰 결함이 그대로 남은 것)")
    }

    func testCroppedRegionMaskProducesIdenticalPatch() throws {
        // 넓은 필드 안 국소 결함: 문맥 여백(repairContextRadius) 이상을 유지한 crop 은
        // 전체 ROI 와 같은 패치(rect·픽셀)를 만들어야 한다 — 저장/재빌드 창 축소의 안전 근거.
        let fieldW = 640, fieldH = 620
        let dx = 300..<306, dyDown = 200..<205
        var mask = [UInt8](repeating: 0, count: fieldW * fieldH * 4)
        for y in dyDown {
            for x in dx {
                let o = (y * fieldW + x) * 4
                mask[o] = 255; mask[o + 1] = 255; mask[o + 2] = 255; mask[o + 3] = 255
            }
        }
        let roi = CGRect(x: 0, y: 0, width: fieldW, height: fieldH)
        let cropped = try XCTUnwrap(croppedRegionMaskBytes(
            mask, width: fieldW, height: fieldH, roiYup: roi,
            margin: Chromabase.SoftwareDefectRemoval.repairContextRadius
        ))
        XCTAssertLessThan(cropped.width, fieldW)
        XCTAssertLessThan(cropped.height, fieldH)

        let base = try makeBase(width: fieldW, height: fieldH,
                                defectX: dx, defectYDown: dyDown)
        let fullEdit = DefectEdit.region(
            mask: DefectCompressedData.raw(Data(mask)).compressed(),
            roi: roi, width: fieldW, height: fieldH
        )
        let croppedEdit = DefectEdit.region(
            mask: DefectCompressedData.raw(Data(cropped.mask)).compressed(),
            roi: cropped.roi, width: cropped.width, height: cropped.height
        )
        let fullPatch = try XCTUnwrap(
            try XCTUnwrap(computeDefectPatches(fullEdit, base: base, shouldCancel: { false })).first
        )
        let croppedPatch = try XCTUnwrap(
            try XCTUnwrap(computeDefectPatches(croppedEdit, base: base, shouldCancel: { false })).first
        )
        XCTAssertEqual(fullPatch.rect, croppedPatch.rect)
        let fullPixels = render(CIImage(cgImage: fullPatch.image,
                                        options: [.colorSpace: linearColorSpace]))
        let croppedPixels = render(CIImage(cgImage: croppedPatch.image,
                                           options: [.colorSpace: linearColorSpace]))
        XCTAssertEqual(fullPixels.count, croppedPixels.count)
        var maxDiff: Float = 0
        for i in 0..<fullPixels.count {
            maxDiff = max(maxDiff, abs(fullPixels[i] - croppedPixels[i]))
        }
        // 16bit 양자화 1스텝(≈1.6e-5)까지 허용 — 그 이상이면 문맥 여백 계약 위반.
        XCTAssertLessThanOrEqual(maxDiff, 2.0 / 65535.0)
    }

    func testCroppedRegionMaskROIMapping() throws {
        // y-down 창 → y-up ROI 매핑의 수치 검증(마스크 좌표와 ROI 가 함께 이동해야 한다).
        let fieldW = 400, fieldH = 300
        var mask = [UInt8](repeating: 0, count: fieldW * fieldH * 4)
        for y in 40..<45 {
            for x in 250..<260 {
                let o = (y * fieldW + x) * 4
                mask[o] = 255; mask[o + 3] = 255
            }
        }
        let roi = CGRect(x: 100, y: 50, width: fieldW, height: fieldH)
        let margin = 16
        let cropped = try XCTUnwrap(croppedRegionMaskBytes(
            mask, width: fieldW, height: fieldH, roiYup: roi, margin: margin
        ))
        // 창(y-down): x [234, 276), y [24, 61)
        XCTAssertEqual(cropped.width, 42)
        XCTAssertEqual(cropped.height, 37)
        XCTAssertEqual(cropped.roi, CGRect(x: 334, y: 289, width: 42, height: 37))
        // 마스크 내용이 창-로컬 좌표로 이동했는지 표본 확인.
        let localOffset = ((40 - 24) * cropped.width + (250 - 234)) * 4
        XCTAssertEqual(cropped.mask[localOffset], 255)
        let localOutside = ((39 - 24) * cropped.width + (250 - 234)) * 4
        XCTAssertEqual(cropped.mask[localOutside], 0)
    }

    // MARK: fixtures

    private func makeBase() throws -> CGImage {
        try makeBase(width: width, height: height, defectX: defectX, defectYDown: defectYDown)
    }

    /// 균일 회색(0.5) 배경 + 밝은(0.9) 결함 사각형. 비트맵 y-down 좌표로 심는다.
    private func makeBase(width: Int, height: Int,
                          defectX: Range<Int>, defectYDown: Range<Int>) throws -> CGImage {
        var bytes = [UInt8](repeating: 128, count: width * height * 4)
        for i in 0..<(width * height) { bytes[i * 4 + 3] = 255 }
        for y in defectYDown {
            for x in defectX {
                let o = (y * width + x) * 4
                bytes[o] = 230; bytes[o + 1] = 230; bytes[o + 2] = 230
            }
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    private func makeMaskData() -> Data {
        var mask = Data(repeating: 0, count: width * height * 4)
        for y in defectYDown {
            for x in defectX {
                let o = (y * width + x) * 4
                mask[o] = 255; mask[o + 1] = 255; mask[o + 2] = 255; mask[o + 3] = 255
            }
        }
        return mask
    }

    /// RGBAf(linear) 로 렌더한 픽셀 버퍼(행 순서 y-down).
    private func render(_ image: CIImage) -> [Float] {
        let extent = image.extent.integral
        let w = Int(extent.width), h = Int(extent.height)
        var out = [Float](repeating: 0, count: w * h * 4)
        cleanedRawContext.render(
            image, toBitmap: &out, rowBytes: w * 4 * MemoryLayout<Float>.size,
            bounds: extent, format: .RGBAf, colorSpace: linearColorSpace
        )
        return out
    }

    private func meanLuma(_ pixels: [Float], xRange: Range<Int>, yDownRange: Range<Int>) -> Float {
        var sum: Float = 0
        var count: Float = 0
        for y in yDownRange {
            for x in xRange {
                let o = (y * width + x) * 4
                sum += (pixels[o] + pixels[o + 1] + pixels[o + 2]) / 3
                count += 1
            }
        }
        return count > 0 ? sum / count : 0
    }
}
