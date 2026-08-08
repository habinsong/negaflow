import XCTest
import CoreGraphics
import Chromabase
@testable import negaflowApp

@MainActor
final class PixelSamplerRuntimeTests: XCTestCase {
    func testAppReadoutSeparatesOriginalWorkingAndProofAtSourceCoordinate() throws {
        let model = AppModel()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: FileManager.default.temporaryDirectory.appendingPathComponent("pixel-sampler.tif"),
            filmType: .colorPositive,
            sourcePixelWidth: 4,
            sourcePixelHeight: 2
        )
        model.frames = [frame]
        model.pixelSamplerStore.setEnabled(true)
        frame.cachedRawBase = try solidImage(red: 255, green: 0, blue: 0)
        model.pixelSamplerStore.setWorkingBase(
            try solidImage(red: 128, green: 128, blue: 128),
            for: frame.id
        )
        frame.cachedDevelopedBase = try solidImage(red: 0, green: 0, blue: 255)
        model.softProofEnabled = true

        model.updatePixelSampler(for: frame, displayUnitPoint: CGPoint(x: 0.75, y: 0.25))

        let readout = try XCTUnwrap(model.pixelSamplerStore.readout)
        XCTAssertEqual(readout.sourceCoordinate, PixelCoordinate(x: 3, y: 0))
        XCTAssertGreaterThan(try XCTUnwrap(readout.original).rgb.x, 0.99)
        XCTAssertEqual(try XCTUnwrap(readout.working).rgb.x, 0.216, accuracy: 0.01)
        XCTAssertGreaterThan(try XCTUnwrap(readout.proof).rgb.z, 0.99)
        XCTAssertNotEqual(readout.original?.lab, readout.proof?.lab)

        frame.updateTransform { $0.rotation = .deg90 }
        model.updatePixelSampler(for: frame, displayUnitPoint: CGPoint(x: 0.25, y: 0.75))
        XCTAssertEqual(
            model.pixelSamplerStore.readout?.sourceCoordinate,
            PixelCoordinate(x: 3, y: 1)
        )
    }

    func testDisablingAndEvictionClearSamplerOnlyCaches() throws {
        let model = AppModel()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: FileManager.default.temporaryDirectory.appendingPathComponent("pixel-sampler-evict.tif"),
            filmType: .colorPositive
        )
        let image = try solidImage(red: 20, green: 30, blue: 40)
        model.pixelSamplerStore.setEnabled(true)
        model.pixelSamplerStore.setWorkingBase(image, for: frame.id)
        XCTAssertNotNil(model.pixelSamplerStore.workingBase(for: frame.id))

        model.pixelSamplerStore.removeFrame(frame.id)
        XCTAssertNil(model.pixelSamplerStore.workingBase(for: frame.id))
        model.pixelSamplerStore.setWorkingBase(image, for: frame.id)
        model.pixelSamplerStore.setEnabled(false)
        XCTAssertNil(model.pixelSamplerStore.workingBase(for: frame.id))
        XCTAssertNil(model.pixelSamplerStore.readout)
    }

    private func solidImage(red: UInt8, green: UInt8, blue: UInt8) throws -> CGImage {
        var pixels = [red, green, blue, UInt8(255)]
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }
}
