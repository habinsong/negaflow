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

        XCTAssertGreaterThan(luma(simulated, x: 0), luma(baseline, x: 0) + 0.03)
        XCTAssertLessThan(luma(simulated, x: 7), luma(baseline, x: 7) - 0.03)
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
