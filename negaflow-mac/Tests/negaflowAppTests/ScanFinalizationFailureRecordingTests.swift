import Foundation
import ScannerKit
import XCTest
@testable import negaflowApp

/// 마무리 단계에서 한 프레임이 실패하면 그 뒤 프레임은 발행되지 않는다. 예전에는 그 프레임들을
/// 아무 기록 없이 건너뛰어서, 작업이 finalizing 상태로 남고 사용자는 어느 컷이 왜 사라졌는지
/// 알 수 없었다. 지금은 남은 프레임을 중단 원인으로 실패 처리하고, 그 기록마저 거절당하면
/// 세어서 드러낸다.
///
/// 이 테스트는 그 처리가 딛고 선 계약을 고정한다: 기록이 언제 성공하고 언제 거절되는지,
/// 그리고 기록해도 촬영본이 보존되는지.
@MainActor
final class ScanFinalizationFailureRecordingTests: XCTestCase {

    private let scannerID = "plugin:test-plugin:device-1"

    /// 발행은 카탈로그가 건강할 때만 성공한다. 세션에는 롤 배정이 따라붙어야 하므로
    /// 모델 상태를 한 번에 갖춰 심는다.
    private func install(sessionID: UUID, jobs: [ScanJob], into model: AppModel) throws {
        let rollID = UUID()
        let published = model.publishScanGeneration(
            frames: [],
            rolls: [
                LibraryRoll(
                    id: rollID,
                    kind: .physical,
                    name: "Test Roll",
                    createdAt: Date(timeIntervalSince1970: 900),
                    filmType: .colorNegative,
                    frameIDs: []
                )
            ],
            activeRollID: rollID,
            sessions: [try makeSession(id: sessionID, jobs: jobs)],
            assignments: [
                LibraryScanRollAssignment(
                    sessionID: sessionID,
                    rollID: rollID,
                    draftName: "Test Roll",
                    filmType: .colorNegative,
                    createdAt: Date(timeIntervalSince1970: 900)
                )
            ]
        )
        XCTAssertTrue(published, "픽스처 자체가 발행되지 않으면 이후 단언은 의미가 없다")
    }

    /// 마무리 중인 작업은 실패로 기록되고, 다시 마무리를 시도할 수 있도록 촬영본이 남아야 한다.
    func testRecordingAFinalizingJobKeepsItsCaptureForRetry() throws {
        let sessionID = UUID()
        let jobID = UUID()
        let model = AppModel()
        try install(
            sessionID: sessionID,
            jobs: [try makeFinalizingJob(sessionID: sessionID, jobID: jobID, ordinal: 1)],
            into: model
        )

        let reason = ScannerError(.ioFailure, "finalization stopped")
        XCTAssertTrue(model.failFinalization(sessionID: sessionID, jobID: jobID, error: reason))

        let job = try XCTUnwrap(model.scanSessions.first?.jobs.first)
        XCTAssertEqual(job.state, .failed, "남은 프레임은 실패로 남아야 사라지지 않는다")
        XCTAssertNotNil(
            job.pendingCapture,
            "실패로 기록해도 촬영본은 보존돼야 한다. 그래야 다시 마무리할 수 있다"
        )
    }

    /// 이미 마무리 상태가 아닌 작업은 기록이 거절된다. 이 거절을 감지할 수 있어야
    /// 프레임이 조용히 사라지는 상황을 사용자에게 알릴 수 있다.
    func testRecordingIsRefusedWhenTheJobIsNoLongerFinalizing() throws {
        let sessionID = UUID()
        let jobID = UUID()
        let model = AppModel()
        try install(
            sessionID: sessionID,
            jobs: [try makeFinalizingJob(sessionID: sessionID, jobID: jobID, ordinal: 1)],
            into: model
        )
        let reason = ScannerError(.ioFailure, "finalization stopped")

        XCTAssertTrue(model.failFinalization(sessionID: sessionID, jobID: jobID, error: reason))
        XCTAssertFalse(
            model.failFinalization(sessionID: sessionID, jobID: jobID, error: reason),
            "이미 실패한 작업의 재기록은 거절돼야 하고, 호출자는 그것을 알 수 있어야 한다"
        )
    }

    /// 세션에 없는 작업도 마찬가지로 거절된다(스캔 도중 세션이 교체된 경우).
    func testRecordingIsRefusedWhenTheJobIsNotInTheSession() throws {
        let sessionID = UUID()
        let model = AppModel()
        try install(
            sessionID: sessionID,
            jobs: [try makeFinalizingJob(sessionID: sessionID, jobID: UUID(), ordinal: 1)],
            into: model
        )

        XCTAssertFalse(
            model.failFinalization(
                sessionID: sessionID,
                jobID: UUID(),
                error: ScannerError(.ioFailure, "finalization stopped")
            )
        )
    }

    /// 여러 프레임이 남았을 때 각각 독립적으로 기록돼야 한다. 하나가 거절돼도 나머지는 기록된다.
    func testEveryRemainingFrameIsRecordedIndependently() throws {
        let sessionID = UUID()
        let jobIDs = [UUID(), UUID(), UUID()]
        let model = AppModel()
        try install(
            sessionID: sessionID,
            jobs: try jobIDs.enumerated().map { offset, jobID in
                try makeFinalizingJob(sessionID: sessionID, jobID: jobID, ordinal: offset + 1)
            },
            into: model
        )
        let reason = ScannerError(.ioFailure, "finalization stopped")

        // 가운데 프레임을 먼저 기록해 두면 그 프레임만 거절되고 나머지는 기록돼야 한다.
        XCTAssertTrue(model.failFinalization(sessionID: sessionID, jobID: jobIDs[1], error: reason))

        let outcomes = jobIDs.map {
            model.failFinalization(sessionID: sessionID, jobID: $0, error: reason)
        }
        XCTAssertEqual(outcomes, [true, false, true])

        let states = try XCTUnwrap(model.scanSessions.first).jobs
            .sorted { $0.ordinal < $1.ordinal }
            .map(\.state)
        XCTAssertEqual(states, [.failed, .failed, .failed], "남은 프레임이 finalizing으로 남으면 안 된다")
    }

    /// 프레임 번호를 되찾을 수 있어야 어느 컷이 사라졌는지 사용자에게 말할 수 있다.
    func testOrdinalIsRecoverableForReporting() throws {
        let sessionID = UUID()
        let jobID = UUID()
        let model = AppModel()
        let earlierIDs = [UUID(), UUID(), UUID()]
        try install(
            sessionID: sessionID,
            jobs: try (earlierIDs + [jobID]).enumerated().map { offset, id in
                try makeFinalizingJob(sessionID: sessionID, jobID: id, ordinal: offset + 1)
            },
            into: model
        )

        XCTAssertEqual(model.scanOrdinal(sessionID: sessionID, jobID: jobID), 4)
    }

    // MARK: 픽스처

    private func makeFinalizingJob(sessionID: UUID, jobID: UUID, ordinal: Int) throws -> ScanJob {
        let captureURL = try makeCaptureFile()
        var options = ScanOptions.strongDefault(scannerID: scannerID)
        options.requestID = jobID
        options.temporaryOutputURL = captureURL
        let result = CaptureResultSnapshot(
            width: 10,
            height: 8,
            resolution: options.resolution,
            bitDepth: options.bitDepth,
            colorSpace: "sRGB",
            hasInfraredChannel: false,
            reportedDuration: 1,
            backendUsed: .plugin
        )
        let started = Date(timeIntervalSince1970: 1_000)
        let completed = Date(timeIntervalSince1970: 1_002)
        let pending = try PendingCaptureSnapshot(
            result: result,
            appliedOptionsEvidence: .verified(options),
            captureStartedAt: started,
            captureCompletedAt: completed,
            rawFileURL: captureURL
        )
        let queued = try ScanJob(
            id: jobID,
            sessionID: sessionID,
            ordinal: ordinal,
            kind: .full,
            requestedOptions: options,
            framePublication: try ScanFramePublicationSnapshot(
                frameID: jobID,
                scanIndex: ordinal,
                initialTransform: .identity,
                developTarget: .main,
                storageGroupName: "TestScanner"
            ),
            createdAt: Date(timeIntervalSince1970: 900)
        )
        return try queued.started(at: started).finalizing(with: pending, at: completed)
    }

    private func makeSession(id: UUID, jobs: [ScanJob]) throws -> ScanSession {
        try ScanSession(
            id: id,
            createdAt: Date(timeIntervalSince1970: 900),
            device: ScannerDescriptor(
                id: scannerID,
                displayName: "Test Scanner",
                vendor: "Test Vendor",
                model: "Test Model",
                backendType: .plugin
            ),
            backend: ScanBackendSnapshot(
                type: .plugin,
                identifier: "external-json",
                pluginIdentifier: "test-plugin"
            ),
            environment: ScanEnvironmentSnapshot(
                applicationName: "negaflow",
                applicationVersion: "1.0",
                operatingSystem: "macOS",
                operatingSystemVersion: "15.0",
                architecture: "arm64"
            ),
            jobs: jobs
        )
    }

    private func makeCaptureFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-finalization-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("capture.tiff")
        try Data([1, 2, 3, 4]).write(to: url, options: .atomic)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return url
    }
}
