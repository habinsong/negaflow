import XCTest
import CoreGraphics
@testable import Chromabase

// 스캐너의 Gray 스캔은 Samples/Pixel 1 인 TIFF 로 와서 monochrome CGImage 가 된다.
// 여기에 linearSRGB 를 붙이면 채널 수가 맞지 않는 색공간을 지정하는 셈이라 linear 해석이
// 통째로 빠지고, 같은 필름을 Color 로 스캔했을 때와 밝기가 어긋난다.
final class ImageLoaderLinearRawColorSpaceTests: XCTestCase {
    func testMonochromeSourcePicksLinearGray() throws {
        let gray = try makeSynthetic16BitCGImage(monochrome: true)
        XCTAssertEqual(ImageLoader.linearRawColorSpaceName(gray), CGColorSpace.linearGray)
    }

    func testColorSourceKeepsLinearSRGB() throws {
        let rgb = try makeSynthetic16BitCGImage(monochrome: false)
        XCTAssertEqual(ImageLoader.linearRawColorSpaceName(rgb), CGColorSpace.linearSRGB)
    }

    // 이름 선택만이 아니라 실제 수집 경로가 그 색공간을 붙이는지 본다.
    func testUntaggedGrayRawIsTaggedLinearGray() throws {
        let gray = try makeSynthetic16BitCGImage(monochrome: true)
        let image = ImageLoader.profileAwareImage(
            gray,
            properties: untaggedTIFFProperties,
            untaggedTIFFRole: .linearScannerRaw
        )
        XCTAssertEqual(image.colorSpace?.name, CGColorSpace.linearGray)
    }

    func testUntaggedColorRawIsTaggedLinearSRGB() throws {
        let rgb = try makeSynthetic16BitCGImage(monochrome: false)
        let image = ImageLoader.profileAwareImage(
            rgb,
            properties: untaggedTIFFProperties,
            untaggedTIFFRole: .linearScannerRaw
        )
        XCTAssertEqual(image.colorSpace?.name, CGColorSpace.linearSRGB)
    }

    // 가져오기(standardImage)는 linear raw 해석 대상이 아니므로 색공간을 덮어쓰지 않는다.
    func testStandardImageRoleIsNotReinterpreted() throws {
        let gray = try makeSynthetic16BitCGImage(monochrome: true)
        let image = ImageLoader.profileAwareImage(
            gray,
            properties: untaggedTIFFProperties,
            untaggedTIFFRole: .standardImage
        )
        XCTAssertNotEqual(image.colorSpace?.name, CGColorSpace.linearGray)
    }

    private var untaggedTIFFProperties: [CFString: Any] {
        [kCGImagePropertyTIFFDictionary: [CFString: Any]() as CFDictionary]
    }

    private func makeSynthetic16BitCGImage(monochrome: Bool) throws -> CGImage {
        let width = 8
        let height = 4
        let componentCount = monochrome ? 1 : 4
        var samples = [UInt16](repeating: 0, count: width * height * componentCount)
        for i in 0..<(width * height) {
            let value = UInt16(i * 65535 / max(width * height - 1, 1))
            if monochrome {
                samples[i] = value
            } else {
                samples[i * 4] = value
                samples[i * 4 + 1] = value / 2
                samples[i * 4 + 2] = 20000
                samples[i * 4 + 3] = 65535
            }
        }
        let bitmapInfo = monochrome
            ? CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
            : CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
        let ctx = CGContext(
            data: &samples,
            width: width,
            height: height,
            bitsPerComponent: 16,
            bytesPerRow: width * componentCount * 2,
            space: monochrome ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
        return try XCTUnwrap(ctx?.makeImage())
    }
}
