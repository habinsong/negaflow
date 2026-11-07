import XCTest
@testable import negaflowApp

final class AppUpdateCheckTests: XCTestCase {
    private func payload(tag: String, prerelease: Bool = false, assets: [String]) -> Data {
        let list = assets.map {
            "{\"name\":\"\($0)\",\"browser_download_url\":\"https://example.invalid/\($0)\"}"
        }.joined(separator: ",")
        return Data("""
        {"tag_name":"\(tag)","html_url":"https://github.com/habinsong/negaflow/releases/tag/\(tag)",
         "draft":false,"prerelease":\(prerelease),"assets":[\(list)]}
        """.utf8)
    }

    private let macAssets = [
        "negaflow-1.10.0-mac-arm64.pkg", "negaflow-1.10.0-mac-universal.pkg",
        "negaflow-1.10.0-mac-arm64.dmg", "negaflow-1.10.0-win-x64.exe", "SHA256SUMS.txt",
    ]

    func testNewerReleaseIsComparedNumericallyNotAsText() throws {
        // 글자로 비교하면 "1.10.0" < "1.9.9" 가 된다.
        let result = AppUpdateCheck.result(
            latestReleaseJSON: payload(tag: "v1.10.0", assets: macAssets),
            currentVersion: "1.9.9",
            isAppleSilicon: true
        )
        guard case .available(let release) = result else { return XCTFail("\(String(describing: result))") }
        XCTAssertEqual(release.version, "1.10.0")
        XCTAssertEqual(release.installer?.name, "negaflow-1.10.0-mac-arm64.pkg")
        XCTAssertEqual(release.checksums?.name, "SHA256SUMS.txt")
        XCTAssertEqual(release.pageURL.absoluteString,
                       "https://github.com/habinsong/negaflow/releases/tag/v1.10.0")
    }

    func testSameOrOlderReleaseIsUpToDate() {
        XCTAssertEqual(AppUpdateCheck.result(
            latestReleaseJSON: payload(tag: "v1.2.6", assets: macAssets),
            currentVersion: "1.2.6", isAppleSilicon: true), .upToDate)
        XCTAssertEqual(AppUpdateCheck.result(
            latestReleaseJSON: payload(tag: "v1.2", assets: macAssets),
            currentVersion: "1.2.0", isAppleSilicon: true), .upToDate)
        XCTAssertEqual(AppUpdateCheck.result(
            latestReleaseJSON: payload(tag: "v1.2.5", assets: macAssets),
            currentVersion: "1.2.6", isAppleSilicon: false), .upToDate)
    }

    func testIntelMacGetsUniversalAndMissingInstallerStillOffersThePage() throws {
        let intel = AppUpdateCheck.result(
            latestReleaseJSON: payload(tag: "v2.0.0", assets: macAssets),
            currentVersion: "1.2.6", isAppleSilicon: false)
        guard case .available(let release) = intel else { return XCTFail() }
        XCTAssertEqual(release.installer?.name, "negaflow-1.10.0-mac-universal.pkg")

        let windowsOnly = AppUpdateCheck.result(
            latestReleaseJSON: payload(tag: "v2.0.0", assets: ["negaflow-2.0.0-win-x64.exe"]),
            currentVersion: "1.2.6", isAppleSilicon: true)
        guard case .available(let page) = windowsOnly else { return XCTFail() }
        XCTAssertNil(page.installer)
    }

    func testUnreadableOrUnstableReleasesAreIgnored() {
        XCTAssertNil(AppUpdateCheck.result(latestReleaseJSON: Data("{}".utf8),
                                           currentVersion: "1.2.6", isAppleSilicon: true))
        XCTAssertNil(AppUpdateCheck.result(
            latestReleaseJSON: payload(tag: "nightly", assets: macAssets),
            currentVersion: "1.2.6", isAppleSilicon: true))
        XCTAssertNil(AppUpdateCheck.result(
            latestReleaseJSON: payload(tag: "v9.0.0", prerelease: true, assets: macAssets),
            currentVersion: "1.2.6", isAppleSilicon: true))
        // 앱 버전을 모르면(unknown) 새 버전이라고 말하지 않는다.
        XCTAssertNil(AppUpdateCheck.result(
            latestReleaseJSON: payload(tag: "v9.0.0", assets: macAssets),
            currentVersion: "unknown", isAppleSilicon: true))
    }

    func testChecksumLineFormats() {
        let hash = String(repeating: "ab", count: 32)
        let sums = """
        \(String(repeating: "0", count: 64))  negaflow-1.2.7-win-x64.exe
        \(hash.uppercased()) *negaflow-1.2.7-mac-arm64.pkg
        bad  negaflow-1.2.7-mac-universal.pkg
        """
        XCTAssertEqual(AppUpdateCheck.expectedSHA256(in: sums, fileName: "negaflow-1.2.7-mac-arm64.pkg"), hash)
        XCTAssertNil(AppUpdateCheck.expectedSHA256(in: sums, fileName: "negaflow-1.2.7-mac-universal.pkg"))
        XCTAssertNil(AppUpdateCheck.expectedSHA256(in: sums, fileName: "missing.pkg"))
    }

    func testDownloadNeverOverwritesAnExistingFile() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let name = "negaflow-1.2.7-mac-arm64.pkg"
        XCTAssertEqual(AppUpdateCheck.availableDestination(in: folder, fileName: name).lastPathComponent, name)
        try Data("a".utf8).write(to: folder.appendingPathComponent(name))
        try Data("b".utf8).write(to: folder.appendingPathComponent("negaflow-1.2.7-mac-arm64 2.pkg"))
        XCTAssertEqual(AppUpdateCheck.availableDestination(in: folder, fileName: name).lastPathComponent,
                       "negaflow-1.2.7-mac-arm64 3.pkg")
    }

    func testSHA256OfAFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("negaflow-sha-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try AppUpdateCheck.sha256Hex(of: url),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    /// 실제 GitHub 응답(네트워크 필요). NEGAFLOW_UPDATE_LIVE=1 일 때만 돈다.
    func testLiveGitHubLatestReleaseParses() async throws {
        guard ProcessInfo.processInfo.environment["NEGAFLOW_UPDATE_LIVE"] == "1" else { return }
        let older = await AppModel.fetchAppUpdate(currentVersion: "0.0.1")
        guard case .available(let release) = older else { return XCTFail("\(String(describing: older))") }
        XCTAssertNotNil(release.installer)
        XCTAssertNotNil(release.checksums)
        let newer = await AppModel.fetchAppUpdate(currentVersion: "999.0.0")
        XCTAssertEqual(newer, .upToDate)
        let saved = await AppModel.downloadVerifiedInstaller(
            try XCTUnwrap(release.installer), checksums: release.checksums,
            into: FileManager.default.temporaryDirectory)
        let file = try XCTUnwrap(saved)
        print("LIVE-DOWNLOAD \(file.path)")
        try? FileManager.default.removeItem(at: file)
    }
}
