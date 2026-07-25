import Foundation
@testable import Chromabase

enum ICCOutputProfileTestFixture {
    static let expectedSHA256 = "552012eab86c3d0649343198f750050aba33004da20e0ae37d65770d9a0f600b"

    static func data(filePath: StaticString = #filePath) throws -> Data {
        let testsDirectory = URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let encoded = try Data(contentsOf: testsDirectory.appendingPathComponent(
            "Fixtures/SyntheticRGBPrinter.icc.base64"
        ))
        guard let text = String(data: encoded, encoding: .utf8),
              let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return data
    }

    static func snapshot(filePath: StaticString = #filePath) throws -> ICCOutputProfileSnapshot {
        guard let snapshot = ICCOutputProfileSnapshot(
            profileName: "Synthetic RGB Printer",
            iccProfileData: try data(filePath: filePath),
            expectedSHA256: expectedSHA256
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return snapshot
    }
}
