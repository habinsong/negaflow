import XCTest
import Foundation
import Darwin
@testable import ScannerKit

final class ExternalScannerProcessTests: XCTestCase {
    func testTimeoutPolicyIsOperationSpecific() {
        let detect = ExternalScannerBackend.ProcessTimeoutPolicy.policy(for: ["detect"])
        let capabilities = ExternalScannerBackend.ProcessTimeoutPolicy.policy(for: ["capabilities"])
        let scan = ExternalScannerBackend.ProcessTimeoutPolicy.policy(for: ["scan"])

        XCTAssertLessThan(detect.wallTimeout, capabilities.wallTimeout)
        XCTAssertLessThan(capabilities.wallTimeout, scan.wallTimeout)
        XCTAssertGreaterThan(scan.terminationGracePeriod, detect.terminationGracePeriod)
    }

    func testTimeoutForceKillsTermIgnoringPluginAndClearsProcess() async throws {
        let fixture = try makeBackend(script: Self.termIgnoringScript)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let marker = fixture.directory.appendingPathComponent("started")
        let policy = ExternalScannerBackend.ProcessTimeoutPolicy(
            // 전체 병렬 suite에서도 자식이 한 번은 스케줄될 여유를 주고, 그 뒤 timeout/강제 종료를 검증한다.
            wallTimeout: 1.0,
            terminationGracePeriod: 0.05
        )
        let startedAt = Date()

        do {
            _ = try await fixture.backend.run(
                args: ["detect", marker.path],
                stdin: nil,
                onLine: nil,
                timeoutPolicy: policy
            )
            XCTFail("timeout 오류가 필요합니다")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .timeout)
        } catch {
            XCTFail("예상하지 못한 오류: \(error)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 3)
        XCTAssertNil(fixture.backend.snapshotCurrentProcess())
    }

    func testTaskCancellationForceKillsTermIgnoringPluginAndClearsProcess() async throws {
        let fixture = try makeBackend(script: Self.termIgnoringScript)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let marker = fixture.directory.appendingPathComponent("started")
        let policy = ExternalScannerBackend.ProcessTimeoutPolicy(
            wallTimeout: 5,
            terminationGracePeriod: 0.05
        )
        let task = Task {
            try await fixture.backend.run(
                args: ["scan", marker.path],
                stdin: nil,
                onLine: nil,
                timeoutPolicy: policy
            )
        }
        defer { task.cancel() }

        try await waitForFile(marker)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("cancelled 오류가 필요합니다")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .cancelled)
        } catch {
            XCTFail("예상하지 못한 오류: \(error)")
        }

        XCTAssertNil(fixture.backend.snapshotCurrentProcess())
    }

    func testManualCancelForceKillsTermIgnoringPluginAndClearsProcess() async throws {
        let fixture = try makeBackend(script: Self.termIgnoringScript)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let marker = fixture.directory.appendingPathComponent("started")
        let policy = ExternalScannerBackend.ProcessTimeoutPolicy(
            wallTimeout: 5,
            terminationGracePeriod: 0.05
        )
        let task = Task {
            try await fixture.backend.run(
                args: ["scan", marker.path],
                stdin: nil,
                onLine: nil,
                timeoutPolicy: policy
            )
        }
        defer { task.cancel() }

        try await waitForFile(marker)
        do {
            _ = try await fixture.backend.run(
                args: ["quick"],
                stdin: nil,
                onLine: nil,
                timeoutPolicy: policy
            )
            XCTFail("실행 중인 plugin process와 겹친 두 번째 실행을 수용했습니다")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .busy)
        }
        await fixture.backend.cancelScan()

        do {
            _ = try await task.value
            XCTFail("cancelled 오류가 필요합니다")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .cancelled)
        } catch {
            XCTFail("예상하지 못한 오류: \(error)")
        }

        XCTAssertNil(fixture.backend.snapshotCurrentProcess())
    }

    func testNormalExitDoesNotWaitForDescendantHoldingInheritedPipes() async throws {
        let fixture = try makeBackend(script: Self.inheritedPipeScript)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let childPIDURL = fixture.directory.appendingPathComponent("child-pid")
        var childPID: Int32?
        defer {
            if let childPID { _ = Darwin.kill(childPID, SIGKILL) }
        }
        let startedAt = Date()

        let output = try await fixture.backend.run(
            args: ["detect", childPIDURL.path],
            stdin: nil,
            onLine: nil,
            timeoutPolicy: .init(wallTimeout: 5, terminationGracePeriod: 0.05)
        )

        XCTAssertEqual(String(data: output.stdout, encoding: .utf8), "done\n")
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
        childPID = try XCTUnwrap(
            Int32(String(contentsOf: childPIDURL, encoding: .utf8))
        )
        XCTAssertEqual(Darwin.kill(try XCTUnwrap(childPID), 0), 0)
        XCTAssertNil(fixture.backend.snapshotCurrentProcess())
    }

    func testCancelScanWaitsForCleanupBeforeAnotherProcessStarts() async throws {
        let fixture = try makeBackend(script: Self.cancelThenReuseScript)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let marker = fixture.directory.appendingPathComponent("started")
        let policy = ExternalScannerBackend.ProcessTimeoutPolicy(
            wallTimeout: 5,
            terminationGracePeriod: 0.05
        )
        let first = Task {
            try await fixture.backend.run(
                args: ["scan", marker.path],
                stdin: nil,
                onLine: nil,
                timeoutPolicy: policy
            )
        }
        defer { first.cancel() }

        try await waitForFile(marker)
        await fixture.backend.cancelScan()

        XCTAssertNil(fixture.backend.snapshotCurrentProcess())
        let second = try await fixture.backend.run(
            args: ["quick"],
            stdin: nil,
            onLine: nil,
            timeoutPolicy: policy
        )
        XCTAssertEqual(String(data: second.stdout, encoding: .utf8), "ready\n")
        do {
            _ = try await first.value
            XCTFail("cancelled 오류가 필요합니다")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .cancelled)
        }
    }

    func testStdoutAndStderrAccumulationLimitsFailClosed() async throws {
        let fixture = try makeBackend(script: Self.excessiveOutputScript)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let policy = ExternalScannerBackend.ProcessTimeoutPolicy(
            wallTimeout: 5,
            terminationGracePeriod: 0.05
        )
        let limits = ExternalScannerBackend.ProcessOutputLimits(stdoutBytes: 128, stderrBytes: 128)

        for (stream, expectedMessage) in [
            ("stdout", "stdout 허용량 초과"),
            ("stderr", "stderr 허용량 초과")
        ] {
            do {
                _ = try await fixture.backend.run(
                    args: [stream],
                    stdin: nil,
                    onLine: nil,
                    timeoutPolicy: policy,
                    outputLimits: limits
                )
                XCTFail("\(stream) 제한 초과를 수용했습니다")
            } catch let error as ScannerError {
                XCTAssertEqual(error.code, .ioFailure)
                XCTAssertTrue(error.message.contains(expectedMessage), error.message)
            }
            XCTAssertNil(fixture.backend.snapshotCurrentProcess())
        }
    }

    func testPluginProcessUsesSanitizedEnvironmentAndPluginWorkingDirectory() async throws {
        let fixture = try makeBackend(script: Self.environmentScript)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        setenv("NEGAFLOW_TEST_SECRET", "must-not-leak", 1)
        setenv("DYLD_INSERT_LIBRARIES", "/tmp/must-not-load.dylib", 1)
        defer {
            unsetenv("NEGAFLOW_TEST_SECRET")
            unsetenv("DYLD_INSERT_LIBRARIES")
        }

        let output = try await fixture.backend.run(
            args: ["environment"],
            stdin: nil,
            onLine: nil,
            timeoutPolicy: .init(wallTimeout: 5, terminationGracePeriod: 0.05)
        )
        let lines = try XCTUnwrap(String(data: output.stdout, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        XCTAssertEqual(lines[0], "unset")
        XCTAssertEqual(lines[1], "unset")
        XCTAssertEqual(
            URL(fileURLWithPath: lines[2]).resolvingSymlinksInPath(),
            fixture.directory.resolvingSymlinksInPath()
        )
        XCTAssertEqual(
            lines[3],
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        )
    }

    private func makeBackend(script: String) throws -> (
        backend: ExternalScannerBackend,
        directory: URL
    ) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-process-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executableURL = directory.appendingPathComponent("fake-scanner")
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        let manifest = ScannerPluginManifest(
            schemaVersion: 1,
            id: "process-test",
            name: "Process Test Plugin",
            executable: executableURL.lastPathComponent
        )
        let plugin = InstalledScannerPlugin(
            manifest: manifest,
            manifestURL: directory.appendingPathComponent("manifest.json"),
            executableURL: executableURL
        )
        return (ExternalScannerBackend(plugin: plugin), directory)
    }

    private func waitForFile(_ url: URL) async throws {
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: url.path) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw FixtureError.processDidNotStart
    }

    private enum FixtureError: Error {
        case processDidNotStart
    }

    private static let termIgnoringScript = """
    #!/bin/bash
    trap '' TERM
    printf '%s' "$$" > "$2"
    while :; do
      sleep 0.05
    done
    """

    private static let environmentScript = """
    #!/bin/bash
    printf '%s\n' "${NEGAFLOW_TEST_SECRET-unset}"
    printf '%s\n' "${DYLD_INSERT_LIBRARIES-unset}"
    printf '%s\n' "$PWD"
    printf '%s\n' "$PATH"
    """

    private static let inheritedPipeScript = """
    #!/bin/bash
    /bin/sh -c 'trap "" HUP TERM; sleep 30' &
    printf '%s' "$!" > "$2"
    printf 'done\n'
    exit 0
    """

    private static let cancelThenReuseScript = """
    #!/bin/bash
    if [ "$1" = "quick" ]; then
      printf 'ready\n'
      exit 0
    fi
    trap '' TERM
    printf '%s' "$$" > "$2"
    while :; do :; done
    """

    private static let excessiveOutputScript = """
    #!/bin/bash
    if [ "$1" = "stdout" ]; then
      for _ in {1..1000}; do printf '1234567890\n'; done
    else
      for _ in {1..1000}; do printf '1234567890\n' >&2; done
    fi
    """
}
