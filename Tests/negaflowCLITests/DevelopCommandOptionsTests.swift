import XCTest
import Chromabase
@testable import negaflowCLI

// develop 인자 파서(순수 함수) 검증 — 유효 입력 의미 보존 + silent ignore 제거.
final class DevelopCommandOptionsTests: XCTestCase {

    private func parsed(_ arguments: [String]) throws -> DevelopCommandOptions {
        switch DevelopCommandOptions.parse(arguments) {
        case .success(let options): return options
        case .failure(let message):
            XCTFail("파싱이 성공해야 한다: \(message)")
            throw NSError(domain: "test", code: 1)
        }
    }

    private func failureMessage(_ arguments: [String]) -> String? {
        if case .failure(let error) = DevelopCommandOptions.parse(arguments) {
            return error.message
        }
        return nil
    }

    func testMinimalArguments() throws {
        let options = try parsed(["in.tiff", "out.jpg"])
        XCTAssertEqual(options.inputPath, "in.tiff")
        XCTAssertEqual(options.outputPath, "out.jpg")
        XCTAssertEqual(options.lookName, "neutral")
        XCTAssertEqual(options.developTarget, .main)
        XCTAssertNil(options.filmType)
        XCTAssertFalse(options.scannerRaw)
        XCTAssertEqual(options.defects, 0)
        XCTAssertTrue(options.toneOverrides.isEmpty)
    }

    func testFullValidCommandKeepsLegacySemantics() throws {
        let options = try parsed([
            "in.tiff", "out.tif",
            "--look", "rich-neutral",
            "--scanner-profile", "noritsu-hs1800",
            "--film-type", "colorNegative",
            "--raw",
            "--exposure", "0.5",
            "--shadows", "-0.25",
            "--nr", "0.4",
            "--defects", "0.8",
            "--defect-mask", "mask.png",
        ])
        XCTAssertEqual(options.lookName, "rich-neutral")
        XCTAssertEqual(options.scannerProfileID, "noritsu-hs1800")
        XCTAssertEqual(options.filmType, .colorNegative)
        XCTAssertTrue(options.scannerRaw)
        XCTAssertEqual(options.toneOverrides[.exposure], 0.5)
        XCTAssertEqual(options.toneOverrides[.shadow], -0.25)
        XCTAssertEqual(options.toneOverrides[.noiseReduction], 0.4)
        XCTAssertEqual(options.defects, 0.8)
        XCTAssertEqual(options.defectMaskPath, "mask.png")
    }

    func testDefectsWithoutValueDefaultsToOne() throws {
        let options = try parsed(["in.tiff", "out.jpg", "--defects", "--look", "neutral"])
        XCTAssertEqual(options.defects, 1.0)
        XCTAssertEqual(options.lookName, "neutral")
    }

    func testPositiveShorthand() throws {
        let options = try parsed(["in.tiff", "out.jpg", "--positive"])
        XCTAssertEqual(options.filmType, .colorPositive)
    }

    func testPrintTargetRequiresICCPair() throws {
        XCTAssertNotNil(failureMessage(["in.tiff", "out.jpg", "--target", "print"]))
        let options = try parsed([
            "in.tiff", "out.jpg", "--target", "print",
            "--output-icc", "p.icc", "--output-icc-sha256", "abc",
        ])
        XCTAssertEqual(options.developTarget, .print)
        XCTAssertEqual(options.outputICCPath, "p.icc")
    }

    func testICCOnlyValidForPrintTarget() {
        XCTAssertNotNil(failureMessage(["in.tiff", "out.jpg", "--output-icc", "p.icc"]))
    }

    func testUnknownOptionIsAnErrorNotSilentlyIgnored() {
        let message = failureMessage(["in.tiff", "out.jpg", "--exposur", "1.5"])
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("--exposur") == true)
    }

    func testStrayArgumentIsAnError() {
        XCTAssertNotNil(failureMessage(["in.tiff", "out.jpg", "extra.tiff"]))
    }

    func testNumericParseFailureIsAnErrorNotZero() {
        let message = failureMessage(["in.tiff", "out.jpg", "--exposure", "abc"])
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("--exposure") == true)
    }

    func testInvalidFilmTypeIsAnErrorNotFallback() {
        let message = failureMessage(["in.tiff", "out.jpg", "--film-type", "kodakGold"])
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("kodakGold") == true)
    }

    func testMissingValueForValueOptionIsAnError() {
        XCTAssertNotNil(failureMessage(["in.tiff", "out.jpg", "--look"]))
        XCTAssertNotNil(failureMessage(["in.tiff", "out.jpg", "--exposure"]))
    }

    func testMissingRequiredPathsShowsUsage() {
        XCTAssertNotNil(failureMessage([]))
        XCTAssertNotNil(failureMessage(["only-in.tiff"]))
    }
}
