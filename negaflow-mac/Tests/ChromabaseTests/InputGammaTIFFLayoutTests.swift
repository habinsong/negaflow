import XCTest
import ImageIO
@testable import Chromabase

final class InputGammaTIFFLayoutTests: XCTestCase {
    func testInvalidICCDoesNotDisableLegacyAutomaticDecode() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-icc-\(UUID()).tif")
        defer { try? FileManager.default.removeItem(at: url) }
        try tiff(photometric: 2, channels: 3, invalidICC: true).write(to: url)
        XCTAssertNotNil(ImageLoader.loadImportedDecoded(url))
        XCTAssertEqual(try ImageLoader.inputGammaSourceInfo(url).manualError, .invalidProfile)
        XCTAssertNoThrow(try ImageLoader.loadImportedDecoded(url, inputGamma: .automatic))
        XCTAssertThrowsError(try ImageLoader.loadImportedDecoded(url, inputGamma: .power(1.8)))
    }
    func testConvertedYCbCrAndExtraSamplesAreNotOfferedAsRawRGBGamma() throws {
        for (photometric, channels) in [(6, 3), (2, 4)] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("layout-\(UUID()).tif")
            defer { try? FileManager.default.removeItem(at: url) }
            try tiff(photometric: photometric, channels: channels).write(to: url)
            XCTAssertNotNil(ImageLoader.loadImportedDecoded(url), "valid TIFF fixture")
            let info = try ImageLoader.inputGammaSourceInfo(url)
            XCTAssertEqual(info.manualError, .unsupportedPixels, "\(photometric), \(channels)")
            XCTAssertNil(info.estimatedGamma)
            XCTAssertThrowsError(try ImageLoader.loadImportedDecoded(url, inputGamma: .power(1.8)))
            XCTAssertNoThrow(try ImageLoader.loadImportedDecoded(url, inputGamma: .automatic))
        }
    }

    private func tiff(photometric: Int, channels: Int, invalidICC: Bool = false) -> Data {
        let width = 16, height = 16
        var fields: [(Int, Int, [Int])] = [
            (256, 4, [width]), (257, 4, [height]), (258, 3, Array(repeating: 8, count: channels)),
            (259, 3, [1]), (262, 3, [photometric]), (273, 4, [0]), (277, 3, [channels]),
            (278, 4, [height]), (279, 4, [width * height * channels]), (284, 3, [1])
        ]
        if channels == 4 { fields.append((338, 3, [0])) }
        if photometric == 6 { fields.append((530, 3, [1, 1])) }
        if invalidICC { fields.append((34675, 7, Array(repeating: 0, count: 128))) }
        func fieldWidth(_ type: Int) -> Int { type == 3 ? 2 : (type == 7 ? 1 : 4) }
        fields.sort { $0.0 < $1.0 }
        func number(_ value: Int, _ count: Int) -> Data {
            Data((0..<count).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
        }
        let tableEnd = 8 + 2 + fields.count * 12 + 4
        let payloadSize = fields.reduce(0) { sum, field in
            let size = field.2.count * fieldWidth(field.1)
            return sum + (size > 4 ? size : 0)
        }
        var result = Data([0x49, 0x49, 42, 0, 8, 0, 0, 0])
        result.append(number(fields.count, 2))
        var payload = Data()
        for (tag, type, values) in fields {
            result.append(number(tag, 2)); result.append(number(type, 2)); result.append(number(values.count, 4))
            let values = tag == 273 ? [tableEnd + payloadSize] : values
            var data = values.reduce(into: Data()) { $0.append(number($1, fieldWidth(type))) }
            if data.count > 4 {
                result.append(number(tableEnd + payload.count, 4)); payload.append(data)
            } else {
                while data.count < 4 { data.append(0) }
                result.append(data)
            }
        }
        result.append(number(0, 4)); result.append(payload)
        for _ in 0..<(width * height) {
            result.append(contentsOf: channels == 4 ? [128, 100, 140, 255] : [128, 100, 140])
        }
        return result
    }
}
