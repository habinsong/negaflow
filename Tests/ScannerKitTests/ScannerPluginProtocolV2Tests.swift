import XCTest
import Foundation
import CoreGraphics
import ImageIO
@testable import ScannerKit

final class ScannerPluginProtocolV2Tests: XCTestCase {
    private let fixedRequestID = UUID(uuidString: "7A91B43D-90F8-41E2-B71D-04D17CD9E03B")!

    func testDiscoveryAcceptsOnlyExactManifestSchemaAndProtocolVersions() throws {
        XCTAssertEqual(ScannerPluginManifest.supportedSchemaVersion, 1)
        XCTAssertEqual(ScannerPluginManifest.supportedProtocolVersions, 1...2)

        let root = try makeTemporaryDirectory(prefix: "manifest-versions")
        defer { try? FileManager.default.removeItem(at: root) }
        try installDiscoverablePlugin(id: "legacy", schemaVersion: 1, protocolVersion: nil, in: root)
        try installDiscoverablePlugin(id: "explicit-v1", schemaVersion: 1, protocolVersion: 1, in: root)
        try installDiscoverablePlugin(id: "stream-v2", schemaVersion: 1, protocolVersion: 2, in: root)
        try installDiscoverablePlugin(id: "old-schema", schemaVersion: 0, protocolVersion: 1, in: root)
        try installDiscoverablePlugin(id: "future-schema", schemaVersion: 2, protocolVersion: 2, in: root)
        try installDiscoverablePlugin(id: "future-protocol", schemaVersion: 1, protocolVersion: 3, in: root)
        try installDiscoverablePlugin(id: "ambiguous:id", schemaVersion: 1, protocolVersion: 2, in: root)

        let previousOverride = ProcessInfo.processInfo.environment["NEGAFLOW_PLUGINS_DIR"]
        setenv("NEGAFLOW_PLUGINS_DIR", root.path, 1)
        defer {
            if let previousOverride {
                setenv("NEGAFLOW_PLUGINS_DIR", previousOverride, 1)
            } else {
                unsetenv("NEGAFLOW_PLUGINS_DIR")
            }
        }

        let plugins = ScannerPluginHost.discover()
        XCTAssertEqual(Set(plugins.map(\.id)), ["legacy", "explicit-v1", "stream-v2"])
        XCTAssertEqual(
            plugins.first(where: { $0.id == "legacy" })?.manifest.resolvedProtocolVersion,
            ScannerPluginManifest.legacyProtocolVersion
        )
    }

    func testPluginIdentifierGrammarRejectsAmbiguousRoutingDelimiters() {
        XCTAssertTrue(ScannerPluginManifest.isValidPluginID("negaflow-scanner_fixture.v2"))
        XCTAssertFalse(ScannerPluginManifest.isValidPluginID("bad:id"))
        XCTAssertFalse(ScannerPluginManifest.isValidPluginID("-leading"))
        XCTAssertFalse(ScannerPluginManifest.isValidPluginID("white space"))
        XCTAssertFalse(ScannerPluginManifest.isValidPluginID("스캐너"))
        XCTAssertFalse(ScannerPluginManifest.isValidPluginID(String(repeating: "a", count: 65)))

        let manifest = ScannerPluginManifest(
            schemaVersion: 1,
            protocolVersion: 2,
            id: "bad:id",
            name: "Ambiguous",
            executable: "scanner"
        )
        XCTAssertFalse(manifest.isSupportedByHost)
    }

    func testProtocolV1KeepsLegacyRequestAndEventWireFormat() async throws {
        let fixture = try makeBackend(
            id: "wire-v1",
            protocolVersion: nil,
            preflight: """
            if printf '%s' "$payload" | grep -q '"protocolVersion"'; then exit 31; fi
            if printf '%s' "$payload" | grep -q '"requestID"'; then exit 32; fi
            """,
            events: """
            printf '{"type":"progress","phase":"scanningRGB","fraction":0.25}\\n'
            printf '{"type":"result","width":10,"height":8,"path":"%s"}\\n' "$out"
            """
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = fixture.root.appendingPathComponent("published.tiff")
        var options = ScanOptions.strongDefault(scannerID: "plugin:wire-v1:dev0")
        options.requestID = fixedRequestID
        options.temporaryOutputURL = output

        let progress = ProgressCollectorV2()
        let result = try await fixture.backend.startFullScan(options) { progress.add($0) }

        XCTAssertEqual(result.rawFileURL, output)
        XCTAssertEqual(result.width, 10)
        XCTAssertEqual(result.height, 8)
        XCTAssertEqual(result.resolution, options.resolution)
        XCTAssertEqual(result.bitDepth, options.bitDepth)
        XCTAssertNil(result.reportedResolution)
        XCTAssertNil(result.reportedBitDepth)
        XCTAssertEqual(progress.values.map(\.fraction), [0.25])
        XCTAssertEqual(result.appliedOptionsEvidence, .unknownLegacy(protocolVersion: 1))
    }

    func testProtocolV1SeparatesValidReportsFromOperationalFallbacks() async throws {
        let validFixture = try makeBackend(
            id: "reported-v1",
            protocolVersion: nil,
            events: """
            printf '{"type":"result","width":10,"height":8,"path":"%s","resolutionDPI":1800,"bitDepth":8}\n' "$out"
            """
        )
        defer { try? FileManager.default.removeItem(at: validFixture.root) }
        let validOutput = validFixture.root.appendingPathComponent("published.tiff")
        var validOptions = ScanOptions.strongDefault(scannerID: "plugin:reported-v1:dev0")
        validOptions.temporaryOutputURL = validOutput

        let valid = try await validFixture.backend.startFullScan(validOptions) { _ in }

        XCTAssertEqual(valid.resolution, .r1800)
        XCTAssertEqual(valid.bitDepth, .eight)
        XCTAssertEqual(valid.reportedResolution, .r1800)
        XCTAssertEqual(valid.reportedBitDepth, .eight)
        XCTAssertEqual(valid.appliedOptionsEvidence, .unknownLegacy(protocolVersion: 1))

        let invalidFixture = try makeBackend(
            id: "invalid-reported-v1",
            protocolVersion: nil,
            events: """
            printf '{"type":"result","width":10,"height":8,"path":"%s","resolutionDPI":-1,"bitDepth":12}\n' "$out"
            """
        )
        defer { try? FileManager.default.removeItem(at: invalidFixture.root) }
        let invalidOutput = invalidFixture.root.appendingPathComponent("published.tiff")
        var invalidOptions = ScanOptions.strongDefault(
            scannerID: "plugin:invalid-reported-v1:dev0"
        )
        invalidOptions.temporaryOutputURL = invalidOutput

        let invalid = try await invalidFixture.backend.startFullScan(invalidOptions) { _ in }

        XCTAssertEqual(invalid.resolution, invalidOptions.resolution)
        XCTAssertEqual(invalid.bitDepth, invalidOptions.bitDepth)
        XCTAssertNil(invalid.reportedResolution)
        XCTAssertNil(invalid.reportedBitDepth)
        XCTAssertEqual(invalid.appliedOptionsEvidence, .unknownLegacy(protocolVersion: 1))
    }

    func testProtocolV2RoundTripsVersionRequestAndSequence() async throws {
        let fixture = try makeBackend(
            id: "wire-v2",
            protocolVersion: 2,
            preflight: """
            [ "$protocol" = "2" ] || exit 41
            [ "$request" = "\(fixedRequestID.uuidString)" ] || exit 42
            """,
            events: validV2Events
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = fixture.root.appendingPathComponent("published.tiff")
        var options = ScanOptions.strongDefault(scannerID: "plugin:wire-v2:dev0")
        options.requestID = fixedRequestID
        options.temporaryOutputURL = output

        let progress = ProgressCollectorV2()
        let result = try await fixture.backend.startFullScan(options) { progress.add($0) }

        XCTAssertEqual(result.rawFileURL, output)
        XCTAssertEqual(result.width, 10)
        XCTAssertEqual(result.height, 8)
        XCTAssertEqual(progress.values.map(\.phase), [.scanningRGB])
        XCTAssertEqual(progress.values.map(\.fraction), [0.5])
        XCTAssertEqual(result.reportedResolution, options.resolution)
        XCTAssertEqual(result.reportedBitDepth, options.bitDepth)
        XCTAssertEqual(result.appliedOptionsEvidence, .verified(options))
    }

    func testProtocolV2ReturnsOpaqueCapabilityTokenToSameDeviceScan() async throws {
        let fixture = try makeBackend(
            id: "capability-token-v2",
            protocolVersion: 2,
            capabilityToken: "opaque-sane-snapshot-v1",
            preflight: """
            token=$(printf '%s' "$payload" | /usr/bin/plutil -extract capabilityToken raw -o - - 2>/dev/null || true)
            [ "$token" = "opaque-sane-snapshot-v1" ] || exit 49
            """,
            events: validV2Events
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let scannerID = "plugin:capability-token-v2:dev0"
        _ = try await fixture.backend.getCapabilities(scannerID: scannerID)

        var options = ScanOptions.strongDefault(scannerID: scannerID)
        options.requestID = fixedRequestID
        options.temporaryOutputURL = fixture.root.appendingPathComponent("published.tiff")

        let result = try await fixture.backend.startFullScan(options) { _ in }

        XCTAssertEqual(result.appliedOptionsEvidence, .verified(options))
    }

    func testProtocolV2GeneratesRequestIDWhenOptionsDoNotProvideOne() async throws {
        let fixture = try makeBackend(
            id: "generated-request-v2",
            protocolVersion: 2,
            preflight: """
            [ "$protocol" = "2" ] || exit 51
            [ -n "$request" ] || exit 52
            """,
            events: validV2Events
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = fixture.root.appendingPathComponent("published.tiff")
        var options = ScanOptions.strongDefault(scannerID: "plugin:generated-request-v2:dev0")
        options.temporaryOutputURL = output

        let result = try await fixture.backend.startFullScan(options) { _ in }

        XCTAssertEqual(result.rawFileURL, output)
        guard case let .verified(appliedOptions) = result.appliedOptionsEvidence else {
            return XCTFail("protocol v2 verified applied options가 필요합니다")
        }
        XCTAssertNotNil(appliedOptions.requestID)
        XCTAssertEqual(appliedOptions.scannerID, options.scannerID)
        XCTAssertEqual(appliedOptions.temporaryOutputURL, output)
    }

    func testProtocolV2PreviewReturnsVerifiedForcedPreviewOptions() async throws {
        let fixture = try makeBackend(
            id: "verified-preview-v2",
            protocolVersion: 2,
            artifactBitDepth: .eight,
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"width":10,"height":8,"path":"%s","resolutionDPI":0,"bitDepth":8,"hasInfrared":false,"appliedOptions":%s}\\n' "$request" "$out" "$applied_preview"
            """
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = fixture.root.appendingPathComponent("preview.tiff")
        var options = ScanOptions.preview(scannerID: "plugin:verified-preview-v2:dev0")
        options.requestID = fixedRequestID
        options.temporaryOutputURL = output

        let result = try await fixture.backend.startPreviewScan(options) { _ in }

        XCTAssertEqual(result.resolution, .preview)
        XCTAssertEqual(result.bitDepth, .eight)
        XCTAssertEqual(result.reportedResolution, .preview)
        XCTAssertEqual(result.reportedBitDepth, .eight)
        XCTAssertEqual(result.appliedOptionsEvidence, .verified(options))
    }

    /// 플러그인은 스캔 크기를 잘못 계산하는 백엔드를 우회하려고 높이를 1mm 미만으로 맞출 수 있다.
    /// 그 조정은 받아들이고, 이후 검증 기준은 요청이 아니라 실제로 적용된 영역이어야 한다.
    /// 이 계약이 깨지면 epson2 평판 스캔이 통째로 거부된다.
    func testProtocolV2AcceptsSubMillimetreScanHeightAlignment() async throws {
        let fixture = try makeBackend(
            id: "applied-scan-area-aligned",
            protocolVersion: 2,
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"width":10,"height":8,"path":"%s","resolutionDPI":3600,"bitDepth":16,"hasInfrared":false,"appliedOptions":%s}\\n' "$request" "$out" "$applied_aligned_height"
            """
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = fixture.root.appendingPathComponent("published.tiff")
        var options = ScanOptions.strongDefault(scannerID: "plugin:applied-scan-area-aligned:dev0")
        options.requestID = fixedRequestID
        options.temporaryOutputURL = output

        let result = try await fixture.backend.startFullScan(options) { _ in }

        guard case .verified(let applied) = result.appliedOptionsEvidence else {
            return XCTFail("정렬된 높이는 검증된 적용 옵션으로 받아들여져야 한다")
        }
        XCTAssertEqual(applied.scanArea.heightMM, 24.4, accuracy: 1e-9)
        XCTAssertNotEqual(
            applied.scanArea.heightMM,
            options.scanArea.heightMM,
            "적용 영역이 요청으로 되돌아가면 결과 검증 기준이 사라진다"
        )
        XCTAssertEqual(applied.scanArea.widthMM, options.scanArea.widthMM, accuracy: 1e-9)
        XCTAssertEqual(applied.scanArea.originYMM, options.scanArea.originYMM, accuracy: 1e-9)
    }

    func testProtocolV2RejectsUnrequestedAppliedOptionChanges() async throws {
        try await assertV2Rejected(
            id: "applied-color-mode-change",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"width":10,"height":8,"path":"%s","resolutionDPI":3600,"bitDepth":16,"hasInfrared":false,"appliedOptions":%s}\\n' "$request" "$out" "$applied_wrong_color_mode"
            """,
            expectedMessage: "requested/appliedOptions colorMode 불일치"
        )
        try await assertV2Rejected(
            id: "applied-film-type-change",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"width":10,"height":8,"path":"%s","resolutionDPI":3600,"bitDepth":16,"hasInfrared":false,"appliedOptions":%s}\\n' "$request" "$out" "$applied_wrong_film_type"
            """,
            expectedMessage: "requested/appliedOptions filmType 불일치"
        )
        try await assertV2Rejected(
            id: "applied-scan-area-change",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"width":10,"height":8,"path":"%s","resolutionDPI":3600,"bitDepth":16,"hasInfrared":false,"appliedOptions":%s}\\n' "$request" "$out" "$applied_wrong_scan_area"
            """,
            expectedMessage: "requested/appliedOptions scanArea 불일치"
        )
        try await assertV2Rejected(
            id: "applied-scan-area-origin-shift",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"width":10,"height":8,"path":"%s","resolutionDPI":3600,"bitDepth":16,"hasInfrared":false,"appliedOptions":%s}\\n' "$request" "$out" "$applied_shifted_origin"
            """,
            expectedMessage: "requested/appliedOptions scanArea 불일치"
        )
        try await assertV2Rejected(
            id: "applied-scan-area-width-change",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"width":10,"height":8,"path":"%s","resolutionDPI":3600,"bitDepth":16,"hasInfrared":false,"appliedOptions":%s}\\n' "$request" "$out" "$applied_widened"
            """,
            expectedMessage: "requested/appliedOptions scanArea 불일치"
        )
        try await assertV2Rejected(
            id: "applied-scan-area-height-over-budget",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"width":10,"height":8,"path":"%s","resolutionDPI":3600,"bitDepth":16,"hasInfrared":false,"appliedOptions":%s}\\n' "$request" "$out" "$applied_height_over_budget"
            """,
            expectedMessage: "requested/appliedOptions scanArea 불일치"
        )
        try await assertV2Rejected(
            id: "applied-resolution-change",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"width":10,"height":8,"path":"%s","resolutionDPI":1800,"bitDepth":8,"hasInfrared":false,"appliedOptions":%s}\\n' "$request" "$out" "$applied_adjusted"
            """,
            expectedMessage: "requested/appliedOptions resolution 불일치"
        )
    }

    func testProtocolV2RejectsArtifactMetadataContradictions() async throws {
        try await assertV2Rejected(
            id: "artifact-bit-depth-mismatch",
            events: validV2Events,
            expectedMessage: "result/artifact bitDepth 불일치",
            artifactBitDepth: .eight
        )
        try await assertV2Rejected(
            id: "artifact-color-model-mismatch",
            events: validV2Events,
            expectedMessage: "appliedOptions/artifact colorMode 불일치",
            artifactColorMode: .gray
        )
        try await assertV2Rejected(
            id: "artifact-dimensions-mismatch",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"width":11,"height":8,"path":"%s","resolutionDPI":3600,"bitDepth":16,"hasInfrared":false,"appliedOptions":%s}\\n' "$request" "$out" "$applied_default"
            """,
            expectedMessage: "result/artifact 픽셀 크기 불일치"
        )
        try await assertV2Rejected(
            id: "artifact-format-mismatch",
            events: validV2Events,
            expectedMessage: "artifact 형식이 TIFF가 아님",
            artifactTypeIdentifier: "public.png" as CFString
        )
    }

    func testProtocolV2RejectsMissingOrMismatchedEventVersion() async throws {
        try await assertV2Rejected(
            id: "missing-event-version",
            events: """
            printf '{"type":"result","requestID":"%s","sequence":0,"path":"%s"}\\n' "$request" "$out"
            """,
            expectedMessage: "이벤트 버전 불일치"
        )
        try await assertV2Rejected(
            id: "future-event-version",
            events: """
            printf '{"type":"result","protocolVersion":3,"requestID":"%s","sequence":0,"path":"%s"}\\n' "$request" "$out"
            """,
            expectedMessage: "이벤트 버전 불일치"
        )
    }

    func testProtocolV2RejectsMissingOrMismatchedRequestID() async throws {
        try await assertV2Rejected(
            id: "missing-event-request",
            events: """
            printf '{"type":"result","protocolVersion":2,"sequence":0,"path":"%s"}\\n' "$out"
            """,
            expectedMessage: "requestID 불일치"
        )
        try await assertV2Rejected(
            id: "wrong-event-request",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"00000000-0000-0000-0000-000000000001","sequence":0,"path":"%s"}\\n' "$out"
            """,
            expectedMessage: "requestID 불일치"
        )
    }

    func testProtocolV2RejectsMissingDuplicateAndOutOfOrderSequence() async throws {
        try await assertV2Rejected(
            id: "missing-sequence",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","path":"%s"}\\n' "$request" "$out"
            """,
            expectedMessage: "sequence 누락"
        )
        try await assertV2Rejected(
            id: "duplicate-sequence",
            events: """
            printf '{"type":"progress","protocolVersion":2,"requestID":"%s","sequence":7}\\n' "$request"
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":7,"path":"%s"}\\n' "$request" "$out"
            """,
            expectedMessage: "엄격히 증가하지 않음"
        )
        try await assertV2Rejected(
            id: "out-of-order-sequence",
            events: """
            printf '{"type":"progress","protocolVersion":2,"requestID":"%s","sequence":9}\\n' "$request"
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":8,"path":"%s"}\\n' "$request" "$out"
            """,
            expectedMessage: "엄격히 증가하지 않음"
        )
    }

    func testProtocolV2RejectsDuplicateResult() async throws {
        try await assertV2Rejected(
            id: "duplicate-result",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"path":"%s"}\\n' "$request" "$out"
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":1,"path":"%s"}\\n' "$request" "$out"
            """,
            expectedMessage: "result 중복"
        )
    }

    func testProtocolV1AlsoRequiresExactlyOneResult() async throws {
        let fixture = try makeBackend(
            id: "duplicate-result-v1",
            protocolVersion: nil,
            events: """
            printf '{"type":"result","path":"%s"}\\n' "$out"
            printf '{"type":"result","path":"%s"}\\n' "$out"
            """
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = fixture.root.appendingPathComponent("published.tiff")
        var options = ScanOptions.strongDefault(scannerID: "plugin:duplicate-result-v1:dev0")
        options.temporaryOutputURL = output

        do {
            _ = try await fixture.backend.startFullScan(options) { _ in }
            XCTFail("protocol v1의 중복 result를 수용했습니다")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .ioFailure)
            XCTAssertTrue(error.message.contains("result 중복"), error.message)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testProtocolV2RejectsEventAfterResultAndUnknownEventType() async throws {
        try await assertV2Rejected(
            id: "after-result",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"path":"%s"}\\n' "$request" "$out"
            printf '{"type":"progress","protocolVersion":2,"requestID":"%s","sequence":1}\\n' "$request"
            """,
            expectedMessage: "result 이후 이벤트"
        )
        try await assertV2Rejected(
            id: "unknown-event",
            events: """
            printf '{"type":"heartbeat","protocolVersion":2,"requestID":"%s","sequence":0}\\n' "$request"
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":1,"path":"%s"}\\n' "$request" "$out"
            """,
            expectedMessage: "알 수 없는 이벤트 유형"
        )
    }

    func testProtocolV2ViolationStopsNonExitingPluginImmediately() async throws {
        let fixture = try makeBackend(
            id: "immediate-protocol-stop",
            protocolVersion: 2,
            events: """
            trap '' TERM
            printf '{"type":"heartbeat","protocolVersion":2,"requestID":"%s","sequence":0}\\n' "$request"
            while :; do :; done
            """
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = fixture.root.appendingPathComponent("published.tiff")
        var options = ScanOptions.strongDefault(scannerID: "plugin:immediate-protocol-stop:dev0")
        options.requestID = fixedRequestID
        options.temporaryOutputURL = output
        let startedAt = Date()

        do {
            _ = try await fixture.backend.startFullScan(options) { _ in }
            XCTFail("protocol 위반 후 종료하지 않는 플러그인을 수용했습니다")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .ioFailure)
            XCTAssertTrue(error.message.contains("알 수 없는 이벤트 유형"), error.message)
        }
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
        XCTAssertNil(fixture.backend.snapshotCurrentProcess())
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testScanRejectsInvalidUTF8NDJSONForLegacyAndV2Protocols() async throws {
        for protocolVersion in [nil, 2] as [Int?] {
            let id = protocolVersion == nil ? "invalid-utf8-v1" : "invalid-utf8-v2"
            let resultEvent = protocolVersion == nil
                ? "printf '{\"type\":\"result\",\"path\":\"%s\"}\\n' \"$out\""
                : "printf '{\"type\":\"result\",\"protocolVersion\":2,\"requestID\":\"%s\",\"sequence\":0,\"path\":\"%s\"}\\n' \"$request\" \"$out\""
            let fixture = try makeBackend(
                id: id,
                protocolVersion: protocolVersion,
                events: """
                printf '\\377\\n'
                \(resultEvent)
                """
            )
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let output = fixture.root.appendingPathComponent("published.tiff")
            var options = ScanOptions.strongDefault(scannerID: "plugin:\(id):dev0")
            options.requestID = fixedRequestID
            options.temporaryOutputURL = output

            do {
                _ = try await fixture.backend.startFullScan(options) { _ in }
                XCTFail("protocol \(protocolVersion ?? 1)이 invalid UTF-8을 수용했습니다")
            } catch let error as ScannerError {
                XCTAssertEqual(error.code, .ioFailure)
                XCTAssertTrue(error.message.contains("유효한 UTF-8이 아님"), error.message)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    func testProtocolV2TreatsErrorAsTerminalAndPreservesEmptyErrorAsFailure() async throws {
        try await assertV2Rejected(
            id: "after-error",
            events: """
            printf '{"type":"error","protocolVersion":2,"requestID":"%s","sequence":0,"message":"scanner fault"}\\n' "$request"
            printf '{"type":"progress","protocolVersion":2,"requestID":"%s","sequence":1}\\n' "$request"
            """,
            expectedMessage: "error 이후 이벤트"
        )
        try await assertV2Rejected(
            id: "empty-error",
            events: """
            printf '{"type":"error","protocolVersion":2,"requestID":"%s","sequence":0,"message":""}\\n' "$request"
            """,
            expectedMessage: "scan error 이벤트"
        )
    }

    func testProtocolV1KeepsExternalInfraredPathCompatibility() async throws {
        let fixture = try makeBackend(
            id: "external-ir-v1",
            protocolVersion: nil,
            events: """
            outside="$(dirname "$0")/legacy-external-ir.tiff"
            cp "$(dirname "$0")/valid-scan.tiff" "$outside"
            printf '{"type":"result","path":"%s","irPath":"%s","hasInfrared":true}\\n' "$out" "$outside"
            """
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = fixture.root.appendingPathComponent("published.tiff")
        var options = ScanOptions.strongDefault(scannerID: "plugin:external-ir-v1:dev0")
        options.infraredEnabled = true
        options.temporaryOutputURL = output

        let result = try await fixture.backend.startFullScan(options) { _ in }

        XCTAssertEqual(result.rawFileURL, output)
        XCTAssertEqual(result.infraredFileURL, fixture.root.appendingPathComponent("legacy-external-ir.tiff"))
    }

    func testProtocolV2RejectsInfraredPathOutsideHostStagingDirectory() async throws {
        let fixture = try makeBackend(
            id: "external-ir-v2",
            protocolVersion: 2,
            events: """
            outside="$(dirname "$0")/external-ir.tiff"
            cp "$(dirname "$0")/valid-scan.tiff" "$outside"
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"width":10,"height":8,"path":"%s","resolutionDPI":3600,"bitDepth":16,"irPath":"%s","hasInfrared":true,"appliedOptions":%s}\\n' "$request" "$out" "$outside" "$applied_ir"
            """
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = fixture.root.appendingPathComponent("published.tiff")
        var options = ScanOptions.strongDefault(scannerID: "plugin:external-ir-v2:dev0")
        options.requestID = fixedRequestID
        options.infraredEnabled = true
        options.temporaryOutputURL = output

        do {
            _ = try await fixture.backend.startFullScan(options) { _ in }
            XCTFail("protocol v2가 staging 밖 IR 결과를 수용했습니다")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .ioFailure)
            XCTAssertTrue(error.message.contains("staging 경로 밖"), error.message)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testProtocolV2RejectsMissingAndInvalidAppliedOptions() async throws {
        try await assertV2Rejected(
            id: "missing-applied-options",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"path":"%s","resolutionDPI":3600,"bitDepth":16,"hasInfrared":false}\\n' "$request" "$out"
            """,
            expectedMessage: "appliedOptions 누락"
        )
        try await assertV2Rejected(
            id: "missing-applied-optional-key",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"path":"%s","resolutionDPI":3600,"bitDepth":16,"hasInfrared":false,"appliedOptions":%s}\\n' "$request" "$out" "$applied_missing_optional"
            """,
            expectedMessage: "이벤트 파싱 실패"
        )
        try await assertV2Rejected(
            id: "invalid-applied-bit-depth",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"path":"%s","resolutionDPI":3600,"bitDepth":12,"hasInfrared":false,"appliedOptions":%s}\\n' "$request" "$out" "$applied_invalid_bit_depth"
            """,
            expectedMessage: "bitDepth가 유효하지 않음"
        )
    }

    func testProtocolV2RejectsAppliedDeviceAndPreviewMismatch() async throws {
        try await assertV2Rejected(
            id: "applied-device-mismatch",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"path":"%s","resolutionDPI":3600,"bitDepth":16,"hasInfrared":false,"appliedOptions":%s}\\n' "$request" "$out" "$applied_wrong_device"
            """,
            expectedMessage: "deviceID 불일치"
        )
        try await assertV2Rejected(
            id: "applied-preview-mismatch",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"path":"%s","resolutionDPI":3600,"bitDepth":16,"hasInfrared":false,"appliedOptions":%s}\\n' "$request" "$out" "$applied_default"
            """,
            expectedMessage: "preview/resolution 불일치",
            preview: true
        )
    }

    func testProtocolV2RejectsResultAndAppliedOptionMismatches() async throws {
        try await assertV2Rejected(
            id: "result-resolution-mismatch",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"path":"%s","resolutionDPI":7200,"bitDepth":16,"hasInfrared":false,"appliedOptions":%s}\\n' "$request" "$out" "$applied_default"
            """,
            expectedMessage: "result/appliedOptions resolution 불일치"
        )
        try await assertV2Rejected(
            id: "result-bit-depth-mismatch",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"path":"%s","resolutionDPI":3600,"bitDepth":8,"hasInfrared":false,"appliedOptions":%s}\\n' "$request" "$out" "$applied_default"
            """,
            expectedMessage: "result/appliedOptions bitDepth 불일치"
        )
        try await assertV2Rejected(
            id: "result-ir-mismatch",
            events: """
            printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":0,"path":"%s","resolutionDPI":3600,"bitDepth":16,"hasInfrared":true,"appliedOptions":%s}\\n' "$request" "$out" "$applied_default"
            """,
            expectedMessage: "result/appliedOptions IR 불일치"
        )
    }

    func testProtocolV2RequiresOneResult() async throws {
        try await assertV2Rejected(
            id: "missing-result",
            events: """
            printf '{"type":"progress","protocolVersion":2,"requestID":"%s","sequence":0}\\n' "$request"
            """,
            expectedMessage: "scan 결과 누락"
        )
    }

    private var validV2Events: String {
        """
        printf '{"type":"progress","protocolVersion":2,"requestID":"%s","sequence":0,"phase":"scanningRGB","fraction":0.5}\\n' "$request"
        printf '{"type":"result","protocolVersion":2,"requestID":"%s","sequence":1,"width":10,"height":8,"path":"%s","resolutionDPI":3600,"bitDepth":16,"hasInfrared":false,"appliedOptions":%s}\\n' "$request" "$out" "$applied_default"
        """
    }

    private func assertV2Rejected(
        id: String,
        events: String,
        expectedMessage: String,
        preview: Bool = false,
        artifactBitDepth: BitDepth? = nil,
        artifactColorMode: ColorMode = .color,
        artifactTypeIdentifier: CFString = "public.tiff" as CFString
    ) async throws {
        let fixture = try makeBackend(
            id: id,
            protocolVersion: 2,
            artifactBitDepth: artifactBitDepth,
            artifactColorMode: artifactColorMode,
            artifactTypeIdentifier: artifactTypeIdentifier,
            events: events
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = fixture.root.appendingPathComponent("published.tiff")
        var options = preview
            ? ScanOptions.preview(scannerID: "plugin:\(id):dev0")
            : ScanOptions.strongDefault(scannerID: "plugin:\(id):dev0")
        options.requestID = fixedRequestID
        options.temporaryOutputURL = output

        do {
            if preview {
                _ = try await fixture.backend.startPreviewScan(options) { _ in }
            } else {
                _ = try await fixture.backend.startFullScan(options) { _ in }
            }
            XCTFail("유효하지 않은 protocol v2 스트림을 수용했습니다: \(id)")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .ioFailure)
            XCTAssertTrue(error.message.contains(expectedMessage), error.message)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    private func makeBackend(
        id: String,
        protocolVersion: Int?,
        capabilityToken: String? = nil,
        preflight: String = "",
        artifactBitDepth: BitDepth? = nil,
        artifactColorMode: ColorMode = .color,
        artifactTypeIdentifier: CFString = "public.tiff" as CFString,
        events: String
    ) throws -> (backend: ExternalScannerBackend, root: URL) {
        let root = try makeTemporaryDirectory(prefix: id)
        let executableURL = root.appendingPathComponent("fake-scanner")
        let capabilityHandler = capabilityToken.map { token in
            """
            if [ "$1" = "capabilities" ]; then
              printf '%s\\n' '{"resolutionsDPI":[3600],"modes":["color"],"bitDepths":[16],"capabilityToken":"\(token)"}'
              exit 0
            fi
            """
        } ?? ""
        let script = """
        #!/bin/bash
        \(capabilityHandler)
        payload=$(cat)
        out=$(printf '%s' "$payload" | /usr/bin/plutil -extract outputPath raw -o - -)
        protocol=$(printf '%s' "$payload" | /usr/bin/plutil -extract protocolVersion raw -o - - 2>/dev/null || true)
        request=$(printf '%s' "$payload" | /usr/bin/plutil -extract requestID raw -o - - 2>/dev/null || true)
        applied_default='{"deviceID":"dev0","resolutionDPI":3600,"bitDepth":16,"colorMode":"color","filmType":"colorNegative","scanArea":{"widthMM":36,"heightMM":24},"infrared":false,"multiExposure":false,"hardwareExposureTime":null,"brightnessAdjustment":null,"contrastAdjustment":null,"outputRawTIFF":true}'
        applied_ir='{"deviceID":"dev0","resolutionDPI":3600,"bitDepth":16,"colorMode":"color","filmType":"colorNegative","scanArea":{"widthMM":36,"heightMM":24},"infrared":true,"multiExposure":false,"hardwareExposureTime":null,"brightnessAdjustment":null,"contrastAdjustment":null,"outputRawTIFF":true}'
        applied_preview='{"deviceID":"dev0","resolutionDPI":0,"bitDepth":8,"colorMode":"color","filmType":"colorNegative","scanArea":{"widthMM":36,"heightMM":24},"infrared":false,"multiExposure":false,"hardwareExposureTime":null,"brightnessAdjustment":null,"contrastAdjustment":null,"outputRawTIFF":false}'
        applied_adjusted='{"deviceID":"dev0","resolutionDPI":1800,"bitDepth":8,"colorMode":"gray","filmType":"bwPositive","scanArea":{"widthMM":20,"heightMM":10},"infrared":false,"multiExposure":true,"hardwareExposureTime":250,"brightnessAdjustment":-1,"contrastAdjustment":2,"outputRawTIFF":false}'
        applied_missing_optional='{"deviceID":"dev0","resolutionDPI":3600,"bitDepth":16,"colorMode":"color","filmType":"colorNegative","scanArea":{"widthMM":36,"heightMM":24},"infrared":false,"multiExposure":false,"hardwareExposureTime":null,"brightnessAdjustment":null,"outputRawTIFF":true}'
        applied_invalid_bit_depth='{"deviceID":"dev0","resolutionDPI":3600,"bitDepth":12,"colorMode":"color","filmType":"colorNegative","scanArea":{"widthMM":36,"heightMM":24},"infrared":false,"multiExposure":false,"hardwareExposureTime":null,"brightnessAdjustment":null,"contrastAdjustment":null,"outputRawTIFF":true}'
        applied_wrong_device='{"deviceID":"other-device","resolutionDPI":3600,"bitDepth":16,"colorMode":"color","filmType":"colorNegative","scanArea":{"widthMM":36,"heightMM":24},"infrared":false,"multiExposure":false,"hardwareExposureTime":null,"brightnessAdjustment":null,"contrastAdjustment":null,"outputRawTIFF":true}'
        applied_wrong_color_mode='{"deviceID":"dev0","resolutionDPI":3600,"bitDepth":16,"colorMode":"gray","filmType":"colorNegative","scanArea":{"widthMM":36,"heightMM":24},"infrared":false,"multiExposure":false,"hardwareExposureTime":null,"brightnessAdjustment":null,"contrastAdjustment":null,"outputRawTIFF":true}'
        applied_wrong_film_type='{"deviceID":"dev0","resolutionDPI":3600,"bitDepth":16,"colorMode":"color","filmType":"bwPositive","scanArea":{"widthMM":36,"heightMM":24},"infrared":false,"multiExposure":false,"hardwareExposureTime":null,"brightnessAdjustment":null,"contrastAdjustment":null,"outputRawTIFF":true}'
        applied_wrong_scan_area='{"deviceID":"dev0","resolutionDPI":3600,"bitDepth":16,"colorMode":"color","filmType":"colorNegative","scanArea":{"widthMM":20,"heightMM":10},"infrared":false,"multiExposure":false,"hardwareExposureTime":null,"brightnessAdjustment":null,"contrastAdjustment":null,"outputRawTIFF":true}'
        applied_aligned_height='{"deviceID":"dev0","resolutionDPI":3600,"bitDepth":16,"colorMode":"color","filmType":"colorNegative","scanArea":{"widthMM":36,"heightMM":24.4},"infrared":false,"multiExposure":false,"hardwareExposureTime":null,"brightnessAdjustment":null,"contrastAdjustment":null,"outputRawTIFF":true}'
        applied_shifted_origin='{"deviceID":"dev0","resolutionDPI":3600,"bitDepth":16,"colorMode":"color","filmType":"colorNegative","scanArea":{"originYMM":0.4,"widthMM":36,"heightMM":24},"infrared":false,"multiExposure":false,"hardwareExposureTime":null,"brightnessAdjustment":null,"contrastAdjustment":null,"outputRawTIFF":true}'
        applied_widened='{"deviceID":"dev0","resolutionDPI":3600,"bitDepth":16,"colorMode":"color","filmType":"colorNegative","scanArea":{"widthMM":36.4,"heightMM":24},"infrared":false,"multiExposure":false,"hardwareExposureTime":null,"brightnessAdjustment":null,"contrastAdjustment":null,"outputRawTIFF":true}'
        applied_height_over_budget='{"deviceID":"dev0","resolutionDPI":3600,"bitDepth":16,"colorMode":"color","filmType":"colorNegative","scanArea":{"widthMM":36,"heightMM":25.4},"infrared":false,"multiExposure":false,"hardwareExposureTime":null,"brightnessAdjustment":null,"contrastAdjustment":null,"outputRawTIFF":true}'
        \(preflight)
        cp "$(dirname "$0")/valid-scan.tiff" "$out"
        \(events)
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        try writeValidImage(
            to: root.appendingPathComponent("valid-scan.tiff"),
            bitDepth: artifactBitDepth ?? (protocolVersion == 2 ? .sixteen : .eight),
            colorMode: artifactColorMode,
            typeIdentifier: artifactTypeIdentifier
        )
        let manifest = ScannerPluginManifest(
            schemaVersion: ScannerPluginManifest.supportedSchemaVersion,
            protocolVersion: protocolVersion,
            id: id,
            name: "Protocol fixture \(id)",
            executable: executableURL.lastPathComponent
        )
        let manifestURL = root.appendingPathComponent("manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        return (
            ExternalScannerBackend(plugin: InstalledScannerPlugin(
                manifest: manifest,
                manifestURL: manifestURL,
                executableURL: executableURL
            )),
            root
        )
    }

    private func installDiscoverablePlugin(
        id: String,
        schemaVersion: Int,
        protocolVersion: Int?,
        in root: URL
    ) throws {
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executableURL = directory.appendingPathComponent("fake-scanner")
        try "#!/bin/bash\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        let manifest = ScannerPluginManifest(
            schemaVersion: schemaVersion,
            protocolVersion: protocolVersion,
            id: id,
            name: id,
            executable: executableURL.lastPathComponent
        )
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeValidImage(
        to url: URL,
        bitDepth: BitDepth,
        colorMode: ColorMode,
        typeIdentifier: CFString
    ) throws {
        let bitsPerComponent = bitDepth.rawValue
        let componentsPerPixel = colorMode == .color ? 4 : 1
        let bytesPerComponent = bitsPerComponent / 8
        let bitmapInfo: UInt32
        let colorSpace: CGColorSpace
        if colorMode == .color {
            bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
                | (bitsPerComponent == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0)
            colorSpace = CGColorSpaceCreateDeviceRGB()
        } else {
            bitmapInfo = CGImageAlphaInfo.none.rawValue
                | (bitsPerComponent == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0)
            colorSpace = CGColorSpaceCreateDeviceGray()
        }
        guard let context = CGContext(
            data: nil,
            width: 10,
            height: 8,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 10 * componentsPerPixel * bytesPerComponent,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, typeIdentifier, 1, nil)
        else {
            throw ScannerError(.ioFailure, "테스트 이미지 생성 실패")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScannerError(.ioFailure, "테스트 이미지 기록 실패")
        }
    }
}

private final class ProgressCollectorV2: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ScanProgress] = []

    func add(_ progress: ScanProgress) {
        lock.lock()
        storage.append(progress)
        lock.unlock()
    }

    var values: [ScanProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
