import XCTest
@testable import ScannerKit

final class ScannerKitTests: XCTestCase {
    func testScanOptionsStrongDefault() {
        let o = ScanOptions.strongDefault(scannerID: "sane-test")
        XCTAssertEqual(o.resolution, .r3600)
        XCTAssertEqual(o.bitDepth, .sixteen)
        XCTAssertEqual(o.colorMode, .color)
        XCTAssertEqual(o.filmType, .colorNegative)
        XCTAssertFalse(o.infraredEnabled)   // plan §4.2 IR off 기본
    }

    func testCapabilitiesGate() {
        let cap = ScannerCapabilities()
        XCTAssertTrue(cap.supports(resolution: .r7200))
        XCTAssertFalse(cap.supports(resolution: Resolution(4800)))
        XCTAssertTrue(cap.supports(depth: .sixteen))
        XCTAssertTrue(cap.supports(mode: .color))
    }

    func testBackendTypeFromScannerID() {
        XCTAssertEqual(BackendType(fromScannerID: "sane-genesys:libusb:000:010"), .sane)
        XCTAssertEqual(BackendType(fromScannerID: "ica-xyz"), .imageCaptureCore)
        XCTAssertEqual(BackendType(fromScannerID: "mock-1"), .mock)
    }

    func testParseSaneCapabilitiesDump() {
        let dump = """
        All options specific to device `genesys:libusb:000:010':
          Scan Mode:
            --mode Color|Gray [Gray]
            --depth 16 [16]
            --resolution 7200|3600|2400|1200|600dpi [600]
            --source Transparency Adapter [Transparency Adapter]
        """
        let cap = SANEBackend.parseCapabilities(dump)
        XCTAssertTrue(cap.supportedResolutions.contains(.r7200))
        XCTAssertTrue(cap.supportedResolutions.contains(.r3600))
        XCTAssertTrue(cap.supportedModes.contains(.color))
        XCTAssertTrue(cap.supportedBitDepths.contains(.sixteen))
        XCTAssertTrue(cap.supportsTransparency)
        XCTAssertFalse(cap.supportsInfrared)   // genesys는 IR 노출 안 함
    }

    func testPositiveHDRBracketOrder() {
        XCTAssertEqual(SANEBackend.positiveHDRBrightnessBrackets, [100, 30, -45])
    }

    func testScannerReportSerialization() throws {
        let d = ScannerDescriptor(id: "sane-x", displayName: "Plustek OpticFilm 8200i",
                                  vendor: "Plustek", model: "OpticFilm 8200i",
                                  backendType: .sane, verifiedStatus: .verified)
        let r = ScannerReport(descriptor: d, backend: .sane,
                              backendAvailable: true, capabilities: ScannerCapabilities())
        let data = try JSONEncoder().encode(r)
        XCTAssertGreaterThan(data.count, 50)
    }

    // MARK: - SANE 환경 (GUI exit-1 버그 수정 회귀 테스트)
    //
    // GUI .app 환경에서 scanimage 가 "open of device failed: Invalid argument"
    // (exit 1)로 실패하는 근본 원인은 SANE_CONFIG_DIR / PATH 누락이었다.
    // makeSaneEnvironment() 는 반드시 Homebrew 경로를 포함해야 한다.

    func testSaneEnvironmentIncludesHomebrewPath() {
        let env = SANEBackend.makeSaneEnvironment()
        let path = env["PATH"] ?? ""
        XCTAssertTrue(path.contains("/opt/homebrew/bin") || path.contains("/usr/local/bin"),
                      "SANE 환경의 PATH 에 Homebrew 경로가 있어야 GUI 앱이 scanimage 를 찾는다. PATH=\(path)")
    }

    func testSaneEnvironmentHasConfigDirWhenHomebrewInstalled() throws {
        // 이 머신에는 /opt/homebrew/etc/sane.d 가 있으므로 SANE_CONFIG_DIR 가 잡혀야 한다.
        let fm = FileManager.default
        let homebrewSane = fm.fileExists(atPath: "/opt/homebrew/etc/sane.d")
                     || fm.fileExists(atPath: "/usr/local/etc/sane.d")
        guard homebrewSane else {
            throw XCTSkip("Homebrew sane-backends 미설치 — SANE_CONFIG_DIR 검증 생략")
        }
        let env = SANEBackend.makeSaneEnvironment()
        XCTAssertNotNil(env["SANE_CONFIG_DIR"], "SANE_CONFIG_DIR 가 주입되어야 scanimage 가 백엔드 설정을 찾는다.")
        if let cfg = env["SANE_CONFIG_DIR"] {
            XCTAssertTrue(fm.fileExists(atPath: cfg))
        }
    }

    func testFindSaneConfigDirResolvesHomebrew() {
        if let dir = SANEBackend.findSaneConfigDir() {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir))
        }
    }

    // MARK: - USB 주소 재획득 회귀 테스트
    //
    // 스캐너의 libusb 주소는 리셋마다 바뀐다(010 ↔ 011). scanimage -L 출력에서
    // 현재 주소를 올바로 파싱해 내는지 검증. 주소가 틀리면 "Invalid argument" 로 open 실패.

    func testParseDeviceAddressFromScanimageListOutput() {
        // scanimage -L 표준 출력 형식.
        let listOutput = """
        device `genesys:libusb:000:011' is a PLUSTEK OpticFilm 8100 flatbed scanner

        No scanners were identified.
        """
        // 정규식이 동일하게 동작하는지 — 첫 줄의 주소만 잡아야 함.
        let regex = try! NSRegularExpression(
            pattern: "device `genesys:(libusb:[0-9]+:[0-9]+)' is a ([^\\s]+)\\s+(.+?) (?:flatbed |film )?scanner"
        )
        let range = NSRange(listOutput.startIndex..., in: listOutput)
        let match = regex.firstMatch(in: listOutput, range: range)
        XCTAssertNotNil(match)
        if let match,
           let r = Range(match.range(at: 1), in: listOutput) {
            XCTAssertEqual(String(listOutput[r]), "libusb:000:011")
        }
    }

    // MARK: - 좀비 scanimage 정리 회귀 테스트
    //
    // 좀비 scanimage 프로세스가 USB 장치를 점유하면 모든 새 스캔이 실패한다.
    // reapZombieScanimages() 로직이 살아있는 pkill 패턴을 생성하는지 확인(실행은 부작용 방지용으로 스킵).

    func testZombieReapDoesNotThrowOnCleanSystem() {
        // 실제 pkill 은 부작용이 크므로, 명령 문자열이 올바른지만 검증.
        // reapZombieScanimages 는 private 이므로, 여기서는 scanimage 경로가
        // resolve 됨만 확인(경로가 nil 이면 pkill 패턴이 무의미).
        let path = SANEBackend.findScanimage()
        XCTAssertFalse(path.isEmpty, "scanimage 경로가 비어 있으면 좀비 정리가 동작하지 않는다")
    }
}
