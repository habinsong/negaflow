import CryptoKit
import Foundation
import ScannerKit
import XCTest
@testable import negaflowApp

/// 원본 식별값은 내용이 바뀐 원본만 가려내야 한다. iCloud·태그·백업이 확장 속성만 바꿔도
/// ctime 이 바뀌는데, 그때마다 결함 제거를 처음부터 다시 만들고 검토 표시를 지우면 안 된다.
final class DefectSourceIdentityTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "negaflow-source-identity-\(UUID().uuidString)",
        isDirectory: true
    )

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testMetadataOnlyChangeKeepsIdentityAndContentChangeDoesNot() throws {
        let url = root.appendingPathComponent("frame.tiff")
        try Data(repeating: 7, count: 64).write(to: url)
        let original = try AppModel.defectSourceIdentity(for: url)

        let ctimeBefore = try CaptureFileObservation.capture(for: url).changedNanoseconds
        try changeMetadataOnly(url)
        XCTAssertNotEqual(try CaptureFileObservation.capture(for: url).changedNanoseconds, ctimeBefore)
        XCTAssertEqual(try AppModel.defectSourceIdentity(for: url), original)

        let handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Data([1]))
        try handle.close()
        XCTAssertNotEqual(try AppModel.defectSourceIdentity(for: url), original)
    }

    /// 1.1.7 까지는 ctime 까지 넣어 묶었다. 그 뒤로 원본이 그대로면 형식이 바뀌었다는 이유만으로
    /// 다시 만들지 않고, 원본이 달라졌으면 새 형식으로 다시 묶는다.
    func testLegacyBindingIsKeptOnlyWhileTheFileIsUntouched() throws {
        let url = root.appendingPathComponent("legacy.tiff")
        try Data(repeating: 3, count: 64).write(to: url)
        let legacy = try legacyIdentity(for: url)

        XCTAssertEqual(try AppModel.defectSourceIdentity(for: url, bound: legacy), legacy)

        try changeMetadataOnly(url)
        let rebound = try AppModel.defectSourceIdentity(for: url, bound: legacy)
        XCTAssertNotEqual(rebound, legacy)
        XCTAssertEqual(rebound, try AppModel.defectSourceIdentity(for: url))
    }

    private func changeMetadataOnly(_ url: URL) throws {
        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        )
        // 같은 나노초 안에 바뀌면 ctime 이 그대로일 수 있다.
        Thread.sleep(forTimeInterval: 0.01)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: permissions.int16Value ^ 0o040)],
            ofItemAtPath: url.path
        )
    }

    private func legacyIdentity(for url: URL) throws -> DefectSourceIdentity {
        let observation = try CaptureFileObservation.capture(for: url)
        let canonical = [
            "\(observation.device)", "\(observation.inode)", "\(observation.byteCount)",
            "\(observation.modifiedSeconds).\(observation.modifiedNanoseconds)",
            "\(observation.changedSeconds).\(observation.changedNanoseconds)",
        ].joined(separator: "/")
        let digest = SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return try DefectSourceIdentity(byteCount: observation.byteCount, sha256: digest)
    }
}
