import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class SoftProofTests: XCTestCase {
    func testExportColorSpaceProvidesProofProfileFromICCData() throws {
        let profile = try XCTUnwrap(SoftProof.profile(for: .displayP3))

        XCTAssertEqual(profile.colorSpaceModel, .rgb)
        XCTAssertNotNil(CGColorSpace(iccData: profile.iccData as CFData))
        XCTAssertNotNil(profile.media.white)
        XCTAssertNotNil(SoftProof.rgbOutputColorSpace(fromICCData: profile.iccData))
    }

    func testMalformedICCIsRejectedAsProofDestination() {
        XCTAssertNil(SoftProof.rgbOutputColorSpace(fromICCData: Data([0x00, 0x01, 0x02])))
    }

    func testMediaWhiteAndBlackTagsSimulatePaperAndInkOnGeneratedPixels() throws {
        let media = try XCTUnwrap(SoftProof.mediaTags(fromICCData: syntheticICCData(
            white: (x: 0.80, y: 0.90, z: 0.70),
            black: (x: 0.05, y: 0.06, z: 0.04)
        )))
        let image = generatedRamp(width: 8, height: 1)

        let proofed = SoftProof.apply(
            to: image,
            using: SoftProofSettings(
                isEnabled: true,
                colorSpace: .sRGB,
                simulation: .paperAndBlackInk,
                media: media
            )
        )
        let baseline = render(image, width: 8, height: 1)
        let simulated = render(proofed, width: 8, height: 1)
        let paperWhite = try XCTUnwrap(SoftProof.simulatedPaperWhiteRGB(for: SoftProofSettings(
            isEnabled: true,
            colorSpace: .sRGB,
            simulation: .paperAndBlackInk,
            media: media
        )))

        XCTAssertGreaterThan(luma(simulated, x: 0), luma(baseline, x: 0) + 0.03)
        XCTAssertLessThan(luma(simulated, x: 7), luma(baseline, x: 7) - 0.03)
        XCTAssertLessThan(paperWhite.y, 1)
    }

    /// 용지 흰색은 XYZ(D50) → 선형 sRGB 행렬로 옮긴다. 따뜻한 용지(X·Y 0.97, Z 0.92 배)를 XYZ/D50 비율로
    /// 쓰면 (0.970, 0.970, 0.920) 이라 빨강·초록이 같은 노란 기운이지만, 행렬로는 실제 용지처럼 빨강이
    /// 초록보다 높다(윈도우 `proof_media_uses_the_xyz_to_srgb_matrix` 와 같은 값).
    func testPaperWhiteUsesTheXYZToSRGBMatrix() throws {
        let media = try XCTUnwrap(SoftProof.mediaTags(fromICCData: syntheticICCData(
            white: (x: 0.9642 * 0.97, y: 0.97, z: 0.8249 * 0.92),
            black: (x: 0.0, y: 0.0, z: 0.0)
        )))
        let white = try XCTUnwrap(SoftProof.simulatedPaperWhiteRGB(for: SoftProofSettings(
            isEnabled: true, colorSpace: .sRGB, simulation: .paperAndBlackInk, media: media
        )))
        XCTAssertEqual(white.x, 0.9903, accuracy: 0.002)
        XCTAssertEqual(white.y, 0.9686, accuracy: 0.002)
        XCTAssertEqual(white.z, 0.9116, accuracy: 0.002)
    }

    /// 시스템 sRGB·Adobe RGB 는 v2 행렬/TRC 이고 `wtpt` 가 D65 다. 그 값을 그대로 D50 으로
    /// 나누면 "Paper + Black" 이 화면을 파랗게 물들였다(회색 200 → (199, 200, 218)).
    /// 표시 공간에는 용지가 없으므로 흰색은 정확히 1 이어야 한다.
    func testDisplaySpacesWithoutPaperDoNotTintTheProof() throws {
        for space in [ExportColorSpace.sRGB, .adobeRGB, .displayP3] {
            let settings = SoftProofSettings(
                isEnabled: true,
                colorSpace: space,
                simulation: .paperAndBlackInk
            )
            let white = try XCTUnwrap(SoftProof.simulatedPaperWhiteRGB(for: settings), "\(space)")
            XCTAssertEqual(white, SIMD3<Double>(1, 1, 1), "\(space)")
        }
    }

    /// 행렬/TRC 가 아닌 프로파일(실제 프린터·인화지는 전부 LUT 형)은 측정된 `wtpt` 를
    /// 그대로 용지 흰색으로 쓴다. D65 를 적은 행렬 프로파일은 색소 합(PCS 흰색)을 쓴다.
    func testMatrixProfilesUseColorantSumWhileLutProfilesKeepMeasuredWhite() throws {
        let paper = (x: 0.93 * 0.9642, y: 0.95, z: 0.88 * 0.8249)
        let lut = try XCTUnwrap(SoftProof.mediaTags(fromICCData: syntheticICCData(
            white: paper,
            black: (x: 0, y: 0, z: 0)
        )))
        XCTAssertEqual(lut.white?.y ?? 0, 0.95, accuracy: 1e-4)

        let matrix = try XCTUnwrap(SoftProof.mediaTags(fromICCData: syntheticMatrixICCData(
            wtpt: (x: 0.9505, y: 1.0, z: 1.0891)
        )))
        let white = try XCTUnwrap(matrix.white)
        XCTAssertEqual(white.x, 0.9642, accuracy: 2e-4)
        XCTAssertEqual(white.y, 1.0, accuracy: 2e-4)
        XCTAssertEqual(white.z, 0.8249, accuracy: 2e-4)
    }

    func testDisabledSoftProofLeavesGeneratedPixelsUnchanged() {
        let image = generatedRamp(width: 8, height: 1)

        let proofed = SoftProof.apply(
            to: image,
            using: SoftProofSettings(isEnabled: false, colorSpace: .adobeRGB, simulation: .paperAndBlackInk)
        )
        let baseline = render(image, width: 8, height: 1)
        let disabled = render(proofed, width: 8, height: 1)

        XCTAssertEqual(disabled, baseline)
    }

    func testMalformedCustomICCDataIsSafeNoopForMediaSimulation() {
        let image = generatedRamp(width: 8, height: 1)
        let malformed = Data([0x00, 0x01, 0x02, 0x03])

        let proofed = SoftProof.apply(
            to: image,
            using: SoftProofSettings(
                isEnabled: true,
                colorSpace: .sRGB,
                simulation: .paperAndBlackInk,
                iccProfileData: malformed
            )
        )
        let baseline = render(image, width: 8, height: 1)
        let simulated = render(proofed, width: 8, height: 1)

        XCTAssertEqual(simulated, baseline)
        XCTAssertEqual(SoftProof.mediaTags(fromICCData: malformed), nil)
    }

    private func generatedRamp(width: Int, height: Int) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = Float(x) / Float(width - 1)
                let i = (y * width + x) * 4
                pixels[i] = value
                pixels[i + 1] = value
                pixels[i + 2] = value
                pixels[i + 3] = 1
            }
        }
        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
    }

    private func render(_ image: CIImage, width: Int, height: Int) -> [UInt8] {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let context = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        var output = [UInt8](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &output,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: linear
        )
        return output
    }

    private func luma(_ pixels: [UInt8], x: Int) -> Double {
        let i = x * 4
        return (Double(pixels[i]) * 0.2126 + Double(pixels[i + 1]) * 0.7152 + Double(pixels[i + 2]) * 0.0722) / 255.0
    }

    private func syntheticICCData(
        white: (x: Double, y: Double, z: Double),
        black: (x: Double, y: Double, z: Double)
    ) -> Data {
        var data = Data(repeating: 0, count: 128 + 4 + 24 + 40)
        writeUInt32(2, to: &data, at: 128)
        writeTag("wtpt", offset: 156, size: 20, to: &data, entry: 0)
        writeTag("bkpt", offset: 176, size: 20, to: &data, entry: 1)
        writeXYZType(white, to: &data, at: 156)
        writeXYZType(black, to: &data, at: 176)
        return data
    }

    /// sRGB D50 색소와 TRC 태그를 가진 v2 행렬 프로파일. `wtpt` 만 따로 적는다.
    private func syntheticMatrixICCData(wtpt: (x: Double, y: Double, z: Double)) -> Data {
        let colorants: [(String, (x: Double, y: Double, z: Double))] = [
            ("rXYZ", (x: 0.4361, y: 0.2225, z: 0.0139)),
            ("gXYZ", (x: 0.3851, y: 0.7169, z: 0.0971)),
            ("bXYZ", (x: 0.1431, y: 0.0606, z: 0.7139)),
        ]
        let tagCount = 1 + colorants.count + 3
        let tableEnd = 132 + tagCount * 12
        var data = Data(repeating: 0, count: tableEnd + 20 * (1 + colorants.count) + 12)
        data.replaceSubrange(16..<20, with: "RGB ".data(using: .ascii)!)
        writeUInt32(UInt32(tagCount), to: &data, at: 128)
        var offset = tableEnd
        writeTag("wtpt", offset: offset, size: 20, to: &data, entry: 0)
        writeXYZType(wtpt, to: &data, at: offset)
        offset += 20
        for (index, colorant) in colorants.enumerated() {
            writeTag(colorant.0, offset: offset, size: 20, to: &data, entry: 1 + index)
            writeXYZType(colorant.1, to: &data, at: offset)
            offset += 20
        }
        // 세 TRC 는 같은 `curv` 원소(감마 1, 항목 0개)를 가리킨다.
        data.replaceSubrange(offset..<(offset + 4), with: "curv".data(using: .ascii)!)
        for (index, name) in ["rTRC", "gTRC", "bTRC"].enumerated() {
            writeTag(name, offset: offset, size: 12, to: &data, entry: 1 + colorants.count + index)
        }
        return data
    }

    private func writeTag(_ signature: String, offset: Int, size: Int, to data: inout Data, entry: Int) {
        let base = 132 + entry * 12
        data.replaceSubrange(base..<(base + 4), with: signature.data(using: .ascii)!)
        writeUInt32(UInt32(offset), to: &data, at: base + 4)
        writeUInt32(UInt32(size), to: &data, at: base + 8)
    }

    private func writeXYZType(_ xyz: (x: Double, y: Double, z: Double), to data: inout Data, at offset: Int) {
        data.replaceSubrange(offset..<(offset + 4), with: "XYZ ".data(using: .ascii)!)
        writeS15Fixed16(xyz.x, to: &data, at: offset + 8)
        writeS15Fixed16(xyz.y, to: &data, at: offset + 12)
        writeS15Fixed16(xyz.z, to: &data, at: offset + 16)
    }

    private func writeUInt32(_ value: UInt32, to data: inout Data, at offset: Int) {
        data[offset] = UInt8((value >> 24) & 0xff)
        data[offset + 1] = UInt8((value >> 16) & 0xff)
        data[offset + 2] = UInt8((value >> 8) & 0xff)
        data[offset + 3] = UInt8(value & 0xff)
    }

    private func writeS15Fixed16(_ value: Double, to data: inout Data, at offset: Int) {
        let fixed = Int32((value * 65536.0).rounded())
        writeUInt32(UInt32(bitPattern: fixed), to: &data, at: offset)
    }
}
