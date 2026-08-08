import CoreGraphics
import XCTest
@testable import Chromabase

final class ICCOutputProfileSnapshotTests: XCTestCase {
    func testAcceptsExactRGBPrinterClassProfileAndSHA() throws {
        let data = try ICCOutputProfileTestFixture.data()

        let snapshot = try XCTUnwrap(ICCOutputProfileSnapshot(
            profileName: "  Synthetic RGB Printer  ",
            iccProfileData: data,
            expectedSHA256: "sha256:\(ICCOutputProfileTestFixture.expectedSHA256)"
        ))

        XCTAssertEqual(snapshot.profileName, "Synthetic RGB Printer")
        XCTAssertEqual(snapshot.iccProfileData, data)
        XCTAssertEqual(snapshot.profileSHA256, ICCOutputProfileTestFixture.expectedSHA256)
        XCTAssertEqual(snapshot.validatedColorSpace()?.model, .rgb)
        XCTAssertTrue(snapshot.validatedColorSpace()?.supportsOutput ?? false)
    }

    func testRejectsWrongHashAndEmptyName() throws {
        let data = try ICCOutputProfileTestFixture.data()

        XCTAssertNil(ICCOutputProfileSnapshot(
            profileName: "Synthetic",
            iccProfileData: data,
            expectedSHA256: String(repeating: "0", count: 64)
        ))
        XCTAssertNil(ICCOutputProfileSnapshot(profileName: "  ", iccProfileData: data))
    }

    func testRejectsDisplayScannerCMYKAndDeclaredSizeMismatch() throws {
        let original = try ICCOutputProfileTestFixture.data()
        for (offset, signature) in [
            (12, "mntr"),
            (12, "scnr"),
            (16, "CMYK"),
        ] {
            var mutated = original
            mutated.replaceSubrange(offset..<(offset + 4), with: Data(signature.utf8))
            XCTAssertNil(ICCOutputProfileSnapshot(profileName: "Invalid", iccProfileData: mutated))
        }

        var trailing = original
        trailing.append(0)
        XCTAssertNil(ICCOutputProfileSnapshot(profileName: "Trailing", iccProfileData: trailing))
    }

    func testRejectsPrinterProfileWithoutReverseTransform() throws {
        var data = try ICCOutputProfileTestFixture.data()
        data.replaceSubrange(180..<184, with: Data("none".utf8))

        XCTAssertNil(ICCOutputProfileSnapshot(profileName: "One Way", iccProfileData: data))
    }
}
