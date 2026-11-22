import AppKit
import Chromabase
import CoreImage
import XCTest
@testable import negaflowApp

final class PrintFramedPreviewTests: XCTestCase {
    func testPresentationStylePreservesProofColorSpace() throws {
        let proofData = try ICCOutputProfileTestFixture.data()
        let proofSpace = try XCTUnwrap(SoftProof.rgbOutputColorSpace(fromICCData: proofData))

        let context = ChromabaseEngine.sharedLinearRenderContext
        let base = CIImage(color: CIColor(red: 0.45, green: 0.55, blue: 0.65, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let source = try XCTUnwrap(context.createCGImage(
            base,
            from: base.extent,
            format: .RGBA8,
            colorSpace: proofSpace
        ))

        let token = NSObject()
        let request = PrintFramedPreviewRequest(
            frameID: ObjectIdentifier(token),
            imageID: ObjectIdentifier(source),
            referenceID: nil,
            content: .presentation(.cyanotype)
        )
        let preview = try XCTUnwrap(PrintFramedPreview.render(request, image: source, reference: nil))
        let rendered = try XCTUnwrap(preview.image.cgImage(forProposedRect: nil, context: nil, hints: nil))

        XCTAssertEqual(rendered.colorSpace?.copyICCData() as Data?, proofSpace.copyICCData() as Data?)
    }

    func testPresentationStyleFallsBackToSRGBForGrayscaleSource() throws {
        let graySpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.genericGrayGamma2_2))
        guard let bitmap = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: graySpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            XCTFail("Failed to build grayscale CGContext")
            return
        }
        bitmap.setFillColor(gray: 0.5, alpha: 1)
        bitmap.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let source = try XCTUnwrap(bitmap.makeImage())

        let token = NSObject()
        let request = PrintFramedPreviewRequest(
            frameID: ObjectIdentifier(token),
            imageID: ObjectIdentifier(source),
            referenceID: nil,
            content: .presentation(.glassPlate)
        )
        let preview = try XCTUnwrap(PrintFramedPreview.render(request, image: source, reference: nil))
        let rendered = try XCTUnwrap(preview.image.cgImage(forProposedRect: nil, context: nil, hints: nil))

        XCTAssertEqual(rendered.colorSpace?.name, CGColorSpace.sRGB)
    }
}
