import XCTest
import CoreGraphics
@testable import Chromabase

final class InputGammaSourceInfoTests: XCTestCase {
    func testAutomaticReadoutDoesNotUseManualFallbackForUnknownCurves() {
        let cases: [(InputGammaSourceInfo.Curve, Double?)] = [
            (.embeddedPower(2.19921875), 2.19921875),
            (.estimatedPower(0.33, evidence: 0.9, edgeCount: 20), 0.33),
            (.embeddedPower(5.0), 5.0),
            (.assumedLinear, 1.0), (.assumedSRGB, 2.2),
            (.embeddedProfile, nil), (.decoder, nil), (.embeddedPower(.nan), nil)
        ]
        for (curve, expected) in cases {
            XCTAssertEqual(InputGammaSourceInfo(curve: curve, manualError: nil).automaticValue, expected)
        }
    }

    func testReplacingSameSizeFileWithPreservedDateInvalidatesInspection() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1]).write(to: url)
        let date = try XCTUnwrap(url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        let first = try InputGammaSourceInfoCache.read(url) { .init(curve: .assumedLinear, manualError: nil) }
        try Data([2]).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        let second = try InputGammaSourceInfoCache.read(url) { .init(curve: .assumedSRGB, manualError: nil) }
        XCTAssertNotEqual(first, second)
    }

    func testFileChangedDuringInspectionIsNotPublishedOrCached() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1]).write(to: url)
        XCTAssertThrowsError(try InputGammaSourceInfoCache.read(url) {
            try Data([2, 3]).write(to: url, options: .atomic)
            return .init(curve: .assumedLinear, manualError: nil)
        })
        XCTAssertEqual(try InputGammaSourceInfoCache.read(url) {
            .init(curve: .assumedSRGB, manualError: nil)
        }.curve, .assumedSRGB)
    }

    func testDifferentSourcesCanBeInspectedWhileAnotherEstimateIsPending() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.tif"), second = directory.appendingPathComponent("second.tif")
        try Data([1]).write(to: first); try Data([2]).write(to: second)
        let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let independent = DispatchSemaphore(value: 0), finished = DispatchGroup()
        finished.enter()
        DispatchQueue.global().async {
            defer { finished.leave() }
            _ = try? InputGammaSourceInfoCache.read(first) {
                started.signal()
                _ = release.wait(timeout: .now() + 5)
                return .init(curve: .assumedLinear, manualError: nil)
            }
        }
        XCTAssertEqual(started.wait(timeout: .now() + 5), .success)
        finished.enter()
        DispatchQueue.global().async {
            defer { finished.leave() }
            _ = try? InputGammaSourceInfoCache.read(second) {
                independent.signal()
                return .init(curve: .assumedSRGB, manualError: nil)
            }
        }
        let result = independent.wait(timeout: .now() + 2)
        release.signal()
        XCTAssertEqual(result, .success)
        XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)
    }
    func testReadsRecordedPowerWithoutRoundingToSliderStep() throws {
        let profile = SyntheticScannerICCProfile.data()
        XCTAssertEqual(try XCTUnwrap(InputGammaProfile.recordedPower(profile)), SyntheticScannerICCProfile.gamma)
        let info = InputGammaSourceInfo(curve: .embeddedPower(SyntheticScannerICCProfile.gamma), manualError: nil)
        XCTAssertEqual(info.manualSeed, SyntheticScannerICCProfile.gamma)
    }

    func testPiecewiseCurveIsNotReportedAsSingleGamma() throws {
        let srgb = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)?.copyICCData() as Data?)
        XCTAssertNil(InputGammaProfile.recordedPower(srgb))
        let linear = try XCTUnwrap(InputGammaProfile.linearizedData(SyntheticScannerICCProfile.data()) as Data?)
        XCTAssertEqual(InputGammaProfile.recordedPower(linear), 1)
    }

    func testMalformedProfilesNeverProduceReadout() {
        let profile = SyntheticScannerICCProfile.data()
        for count in 0..<profile.count { XCTAssertNil(InputGammaProfile.recordedPower(Data(profile.prefix(count)))) }
    }

    func testUnknownDefaultIsExplicitAndDoesNotInventARecordedGamma() {
        let linear = InputGammaSourceInfo(curve: .assumedLinear, manualError: nil)
        XCTAssertEqual(linear.manualSeed, 1)
        let standard = InputGammaSourceInfo(curve: .assumedSRGB, manualError: nil)
        XCTAssertEqual(standard.manualSeed, 2.2)
    }
}
