import Foundation
import XCTest
@testable import ScannerKit

final class ScanWorkflowTests: XCTestCase {
    private let sessionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let firstJobID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let secondJobID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let manifestID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testFramePublicationSnapshotRoundTripPreservesRestartRecipe() throws {
        let snapshot = try ScanFramePublicationSnapshot(
            frameID: firstJobID,
            scanIndex: 27,
            initialTransform: .init(
                rotation: .deg270,
                flipHorizontal: true,
                straightenAngle: 1.25
            ),
            developTarget: .rescue,
            scannerProfileID: "profile.test",
            presetID: "neutral",
            storageGroupName: "TestScanner",
            regionDefectDisplayROI: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            regionDefectSensitivity: 4.5
        )

        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(
            try JSONDecoder().decode(ScanFramePublicationSnapshot.self, from: data),
            snapshot
        )
        let missingOptionalKey = try mutatedJSON(data) { root in
            root.removeValue(forKey: "scannerProfileID")
        }
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ScanFramePublicationSnapshot.self,
                from: missingOptionalKey
            )
        )
    }

    func testInterruptedScannerErrorSnapshotRoundTrip() throws {
        let snapshot = ScannerErrorSnapshot(
            ScannerError(.interrupted, "application terminated"),
            recordedAt: baseDate
        )
        let data = try JSONEncoder().encode(snapshot)

        XCTAssertEqual(
            try JSONDecoder().decode(ScannerErrorSnapshot.self, from: data),
            snapshot
        )
    }

    func testLegalTransitionsPreserveStableIdentityAndIncrementAttemptOnRetry() throws {
        let queued = try makeJob()
        let running = try queued.started(at: date(1))
        let failed = try running.failed(
            with: ScannerError(.timeout, "lamp warmup timeout"),
            at: date(2)
        )

        XCTAssertEqual(failed.id, queued.id)
        XCTAssertEqual(failed.ordinal, queued.ordinal)
        XCTAssertEqual(failed.attempt, 1)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.failure?.code, .timeout)
        XCTAssertEqual(failed.failure?.message, "lamp warmup timeout")
        XCTAssertNil(failed.captureManifest)

        let retried = try failed.retried(at: date(3))
        XCTAssertEqual(retried.id, queued.id)
        XCTAssertEqual(retried.ordinal, queued.ordinal)
        XCTAssertEqual(retried.attempt, 2)
        XCTAssertEqual(retried.state, .queued)
        XCTAssertNil(retried.startedAt)
        XCTAssertNil(retried.finishedAt)
        XCTAssertNil(retried.failure)
        XCTAssertNil(retried.captureManifest)

        let secondAttempt = try retried.started(at: date(4))
        XCTAssertEqual(secondAttempt.attempt, 2)
        XCTAssertEqual(secondAttempt.state, .running)
        XCTAssertEqual(secondAttempt.startedAt, date(4))
    }

    func testIllegalTransitionsAndMissingTerminalPayloadAreRejected() throws {
        let queued = try makeJob()
        XCTAssertThrowsError(try queued.transitioned(to: .succeeded, at: date(1))) { error in
            XCTAssertEqual(
                error as? ScanWorkflowValidationError,
                .illegalTransition(from: .queued, to: .succeeded)
            )
        }

        let running = try queued.started(at: date(1))
        XCTAssertThrowsError(try running.transitioned(to: .succeeded, at: date(2))) { error in
            XCTAssertEqual(
                error as? ScanWorkflowValidationError,
                .illegalTransition(from: .running, to: .succeeded)
            )
        }
        XCTAssertThrowsError(try running.transitioned(to: .finalizing, at: date(2))) { error in
            guard case .invariantViolation = error as? ScanWorkflowValidationError else {
                return XCTFail("예상하지 못한 오류: \(error)")
            }
        }

        let cancelled = try running.cancelled(at: date(2))
        XCTAssertThrowsError(try cancelled.started(at: date(3))) { error in
            XCTAssertEqual(
                error as? ScanWorkflowValidationError,
                .illegalTransition(from: .cancelled, to: .running)
            )
        }
    }

    func testCaptureFileIdentityStreamsKnownSHA256WithoutChangingRaw() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rawURL = directory.appendingPathComponent("source scan.tiff")
        let bytes = Data("abc".utf8)
        try bytes.write(to: rawURL)

        let identity = try CaptureFileIdentity.build(for: rawURL, chunkSize: 1)

        XCTAssertEqual(identity.originalURL, rawURL)
        XCTAssertEqual(identity.byteCount, 3)
        XCTAssertEqual(
            identity.sha256,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(try Data(contentsOf: rawURL), bytes)
    }

    func testCaptureFileIdentityRejectsSameSizeInPlaceMutationDuringHashing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rawURL = directory.appendingPathComponent("changing.tiff")
        try Data(repeating: 0x11, count: 32).write(to: rawURL)
        var didMutate = false

        XCTAssertThrowsError(
            try CaptureFileIdentity.build(
                for: rawURL,
                chunkSize: 8,
                didReadChunk: { _ in
                    guard !didMutate else { return }
                    didMutate = true
                    let handle = try FileHandle(forWritingTo: rawURL)
                    try handle.seek(toOffset: 16)
                    try handle.write(contentsOf: Data(repeating: 0x22, count: 8))
                    try handle.close()
                }
            )
        )
        XCTAssertTrue(didMutate)
    }

    func testCaptureFileIdentityRejectsSameSizePathReplacementDuringHashing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rawURL = directory.appendingPathComponent("replaced.tiff")
        let replacementURL = directory.appendingPathComponent("replacement.tiff")
        try Data(repeating: 0x31, count: 32).write(to: rawURL)
        try Data(repeating: 0x42, count: 32).write(to: replacementURL)
        var didReplace = false

        XCTAssertThrowsError(
            try CaptureFileIdentity.build(
                for: rawURL,
                chunkSize: 8,
                didReadChunk: { _ in
                    guard !didReplace else { return }
                    didReplace = true
                    try FileManager.default.removeItem(at: rawURL)
                    try FileManager.default.moveItem(at: replacementURL, to: rawURL)
                }
            )
        )
        XCTAssertTrue(didReplace)
    }

    func testCaptureManifestBuildsRGBAndIRFixityAndResultProvenance() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let completed = try makeCompletedSession(in: directory)
        let manifest = try XCTUnwrap(completed.jobs.first?.captureManifest)

        XCTAssertEqual(manifest.id, manifestID)
        XCTAssertEqual(manifest.sessionID, sessionID)
        XCTAssertEqual(manifest.jobID, firstJobID)
        XCTAssertEqual(manifest.attempt, 1)
        XCTAssertEqual(manifest.kind, .full)
        XCTAssertEqual(manifest.result.width, 12)
        XCTAssertEqual(manifest.result.height, 8)
        XCTAssertEqual(manifest.result.resolution, .r3600)
        XCTAssertEqual(manifest.result.bitDepth, .sixteen)
        XCTAssertEqual(manifest.result.reportedResolution, .r3600)
        XCTAssertEqual(manifest.result.reportedBitDepth, .sixteen)
        XCTAssertEqual(manifest.result.colorSpace, "Display P3")
        XCTAssertEqual(manifest.result.backendUsed, .plugin)
        XCTAssertEqual(manifest.result.warnings, ["calibration due soon"])
        XCTAssertEqual(manifest.rgbFile.byteCount, 5)
        XCTAssertEqual(manifest.infraredFile?.byteCount, 4)
        XCTAssertTrue(manifest.result.hasInfraredChannel)
        guard case .verified(let appliedOptions) = manifest.appliedOptionsEvidence else {
            return XCTFail("검증된 적용 옵션이 필요합니다")
        }
        XCTAssertTrue(appliedOptions.infraredEnabled)
    }

    func testSessionRoundTripPreservesStableUUIDsAndProvenanceSnapshots() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try makeCompletedSession(in: directory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(ScanSession.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.schemaVersion, ScanSession.currentSchemaVersion)
        XCTAssertEqual(decoded.id, sessionID)
        XCTAssertEqual(decoded.jobs.first?.id, firstJobID)
        XCTAssertEqual(decoded.jobs.first?.captureManifest?.id, manifestID)
        XCTAssertEqual(decoded.backend.identifier, "external-json")
        XCTAssertEqual(decoded.backend.version, "1.2.0")
        XCTAssertEqual(decoded.backend.pluginIdentifier, "test-plugin")
        XCTAssertEqual(decoded.backend.pluginVersion, "2.4.1")
        XCTAssertEqual(decoded.environment.applicationName, "negaflow")
        XCTAssertEqual(decoded.environment.operatingSystem, "macOS")
    }

    func testFinalizingReceiptRoundTripResumesWithoutHardwareCapture() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rawURL = directory.appendingPathComponent("pending.tiff")
        try Data([1, 2, 3]).write(to: rawURL)
        var options = ScanOptions.strongDefault(scannerID: makeDevice().id)
        options.requestID = firstJobID
        options.temporaryOutputURL = rawURL
        let queued = try makeJob(requestedOptions: options)
        let running = try queued.started(at: date(1))
        let result = ScanResult(
            rawFileURL: rawURL,
            width: 10,
            height: 8,
            resolution: options.resolution,
            bitDepth: options.bitDepth,
            hasInfraredChannel: false,
            scanDuration: 1,
            backendUsed: .plugin,
            appliedOptionsEvidence: .verified(options)
        )
        let receipt = try PendingCaptureSnapshot(
            scanResult: result,
            captureStartedAt: date(1),
            captureCompletedAt: date(2)
        )
        let finalizing = try running.finalizing(with: receipt, at: date(2))
        let session = try ScanSession(
            id: sessionID,
            createdAt: baseDate,
            device: makeDevice(),
            backend: makeBackend(),
            environment: makeEnvironment(),
            jobs: [finalizing]
        )

        let decoded = try JSONDecoder().decode(
            ScanSession.self,
            from: JSONEncoder().encode(session)
        )
        let restoredJob = try XCTUnwrap(decoded.jobs.first)
        XCTAssertEqual(restoredJob.state, .finalizing)
        XCTAssertEqual(restoredJob.pendingCapture, receipt)
        XCTAssertNil(restoredJob.finishedAt)
        XCTAssertNil(restoredJob.captureManifest)

        let manifest = try CaptureManifest.build(
            id: manifestID,
            sessionID: sessionID,
            jobID: firstJobID,
            attempt: restoredJob.attempt,
            kind: .full,
            requestedOptions: options,
            pendingCapture: try XCTUnwrap(restoredJob.pendingCapture),
            chunkSize: 1
        )
        let succeeded = try restoredJob.succeeded(with: manifest, at: date(3))
        XCTAssertEqual(succeeded.state, .succeeded)
        XCTAssertNil(succeeded.pendingCapture)
        XCTAssertEqual(succeeded.captureManifest, manifest)
    }

    func testClosedSessionRejectsPendingFinalization() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rawURL = directory.appendingPathComponent("pending-close.tiff")
        try Data([1]).write(to: rawURL)
        var options = ScanOptions.strongDefault(scannerID: makeDevice().id)
        options.requestID = firstJobID
        options.temporaryOutputURL = rawURL
        let running = try makeJob(requestedOptions: options).started(at: date(1))
        let result = ScanResult(
            rawFileURL: rawURL,
            width: 1,
            height: 1,
            resolution: options.resolution,
            bitDepth: options.bitDepth,
            backendUsed: .plugin,
            appliedOptionsEvidence: .verified(options)
        )
        let receipt = try PendingCaptureSnapshot(
            scanResult: result,
            captureStartedAt: date(1),
            captureCompletedAt: date(2)
        )
        let finalizing = try running.finalizing(with: receipt, at: date(2))
        let session = try ScanSession(
            id: sessionID,
            createdAt: baseDate,
            device: makeDevice(),
            backend: makeBackend(),
            environment: makeEnvironment(),
            jobs: [finalizing]
        )

        XCTAssertThrowsError(try session.closed(at: date(3)))
    }

    func testFinalizationFailurePreservesReceiptAndRetriesWithoutHardwareAttempt() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rawURL = directory.appendingPathComponent("finalization-retry.tiff")
        try Data([1, 2, 3]).write(to: rawURL)
        let finalizing = try makeFinalizingJob(
            id: firstJobID,
            ordinal: 1,
            rawURL: rawURL
        )
        let receipt = try XCTUnwrap(finalizing.pendingCapture)

        let failed = try finalizing.failed(
            with: ScannerError(.ioFailure, "fixity read failed"),
            at: date(3)
        )

        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.pendingCapture, receipt)
        XCTAssertEqual(failed.attempt, 1)
        XCTAssertThrowsError(try failed.retried(at: date(4)))
        let failedSession = try ScanSession(
            id: sessionID,
            createdAt: baseDate,
            device: makeDevice(),
            backend: makeBackend(),
            environment: makeEnvironment(),
            jobs: [failed]
        )
        XCTAssertThrowsError(try failedSession.closed(at: date(4)))

        let resumed = try failed.retryFinalization(at: date(4))
        XCTAssertEqual(resumed.state, .finalizing)
        XCTAssertEqual(resumed.pendingCapture, receipt)
        XCTAssertEqual(resumed.attempt, 1)
        XCTAssertNil(resumed.finishedAt)
        XCTAssertNil(resumed.failure)
    }

    func testPendingReceiptRejectsPathReplacementBeforeRestartFinalization() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rawURL = directory.appendingPathComponent("restart-replaced.tiff")
        try Data([1, 2, 3, 4]).write(to: rawURL)
        let finalizing = try makeFinalizingJob(
            id: firstJobID,
            ordinal: 1,
            rawURL: rawURL
        )
        let receipt = try XCTUnwrap(finalizing.pendingCapture)

        try FileManager.default.removeItem(at: rawURL)
        try Data([9, 8, 7, 6]).write(to: rawURL)

        XCTAssertThrowsError(
            try CaptureManifest.build(
                sessionID: sessionID,
                jobID: firstJobID,
                attempt: 1,
                kind: .full,
                requestedOptions: finalizing.requestedOptions,
                pendingCapture: receipt,
                chunkSize: 1
            )
        )
    }

    func testSucceededTransitionRejectsMutationAfterManifestHashing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rawURL = directory.appendingPathComponent("mutated-after-hash.tiff")
        try Data([1, 2, 3, 4]).write(to: rawURL)
        let finalizing = try makeFinalizingJob(
            id: firstJobID,
            ordinal: 1,
            rawURL: rawURL
        )
        let manifest = try CaptureManifest.build(
            sessionID: sessionID,
            jobID: firstJobID,
            attempt: 1,
            kind: .full,
            requestedOptions: finalizing.requestedOptions,
            pendingCapture: try XCTUnwrap(finalizing.pendingCapture),
            chunkSize: 1
        )
        let handle = try FileHandle(forWritingTo: rawURL)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data([4, 3, 2, 1]))
        try handle.close()

        XCTAssertThrowsError(try finalizing.succeeded(with: manifest, at: date(3)))
    }

    func testEveryJobRequiresDedicatedTemporaryOutputURL() throws {
        var options = ScanOptions.strongDefault(scannerID: makeDevice().id)
        options.requestID = firstJobID

        XCTAssertThrowsError(
            try ScanJob(
                id: firstJobID,
                sessionID: sessionID,
                ordinal: 1,
                kind: .full,
                requestedOptions: options,
                createdAt: baseDate
            )
        )
    }

    func testSessionRejectsOutputPathAndFileObjectSharedAcrossJobs() throws {
        let sharedURL = URL(fileURLWithPath: "/tmp/shared-job-output.tiff")
        var firstOptions = ScanOptions.strongDefault(scannerID: makeDevice().id)
        firstOptions.requestID = firstJobID
        firstOptions.temporaryOutputURL = sharedURL
        var secondOptions = firstOptions
        secondOptions.requestID = secondJobID
        let first = try makeJob(id: firstJobID, ordinal: 1, requestedOptions: firstOptions)
        let second = try makeJob(id: secondJobID, ordinal: 2, requestedOptions: secondOptions)

        XCTAssertThrowsError(
            try ScanSession(
                id: sessionID,
                createdAt: baseDate,
                device: makeDevice(),
                backend: makeBackend(),
                environment: makeEnvironment(),
                jobs: [first, second]
            )
        )

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("first.tiff")
        let hardLinkURL = directory.appendingPathComponent("second.tiff")
        try Data([5, 6, 7]).write(to: firstURL)
        try FileManager.default.linkItem(at: firstURL, to: hardLinkURL)
        let firstFinalizing = try makeFinalizingJob(
            id: firstJobID,
            ordinal: 1,
            rawURL: firstURL
        )
        let secondFinalizing = try makeFinalizingJob(
            id: secondJobID,
            ordinal: 2,
            rawURL: hardLinkURL
        )

        XCTAssertThrowsError(
            try ScanSession(
                id: sessionID,
                createdAt: baseDate,
                device: makeDevice(),
                backend: makeBackend(),
                environment: makeEnvironment(),
                jobs: [firstFinalizing, secondFinalizing]
            )
        )
    }

    func testLegacyV1ManifestPreservesUnknownAppliedOptionsWithoutRequestFallback() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rawURL = directory.appendingPathComponent("legacy.tiff")
        try Data([9, 8, 7]).write(to: rawURL)
        var requested = ScanOptions.strongDefault(scannerID: makeDevice().id)
        requested.requestID = firstJobID
        requested.temporaryOutputURL = rawURL
        let result = ScanResult(
            rawFileURL: rawURL,
            width: 2,
            height: 2,
            resolution: .r1800,
            bitDepth: .eight,
            backendUsed: .plugin,
            appliedOptionsEvidence: .unknownLegacy(protocolVersion: 1)
        )
        let receipt = try PendingCaptureSnapshot(
            scanResult: result,
            captureStartedAt: date(1),
            captureCompletedAt: date(2)
        )
        let manifest = try CaptureManifest.build(
            id: manifestID,
            sessionID: sessionID,
            jobID: firstJobID,
            attempt: 1,
            kind: .full,
            requestedOptions: requested,
            pendingCapture: receipt,
            chunkSize: 1
        )

        XCTAssertEqual(manifest.requestedOptions.resolution, .r3600)
        XCTAssertEqual(manifest.result.resolution, .r1800)
        XCTAssertEqual(manifest.result.bitDepth, .eight)
        XCTAssertNil(manifest.result.reportedResolution)
        XCTAssertNil(manifest.result.reportedBitDepth)
        XCTAssertEqual(
            manifest.appliedOptionsEvidence,
            .unknownLegacy(protocolVersion: 1)
        )
    }

    func testLegacyExplicitReportsPersistSeparatelyInCaptureSnapshot() throws {
        let rawURL = URL(fileURLWithPath: "/tmp/legacy-reported-result.tiff")
        let result = ScanResult(
            rawFileURL: rawURL,
            width: 2,
            height: 2,
            resolution: .r1800,
            bitDepth: .eight,
            reportedResolution: .r1800,
            reportedBitDepth: .eight,
            backendUsed: .plugin,
            appliedOptionsEvidence: .unknownLegacy(protocolVersion: 1)
        )

        let snapshot = CaptureResultSnapshot(result)

        XCTAssertEqual(snapshot.resolution, .r1800)
        XCTAssertEqual(snapshot.bitDepth, .eight)
        XCTAssertEqual(snapshot.reportedResolution, .r1800)
        XCTAssertEqual(snapshot.reportedBitDepth, .eight)
        XCTAssertEqual(
            try JSONDecoder().decode(
                CaptureResultSnapshot.self,
                from: JSONEncoder().encode(snapshot)
            ),
            snapshot
        )
    }

    func testFinalizingRejectsAppliedOptionsOwnedByDifferentJob() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rawURL = directory.appendingPathComponent("wrong-owner.tiff")
        try Data([1]).write(to: rawURL)
        var requested = ScanOptions.strongDefault(scannerID: makeDevice().id)
        requested.requestID = firstJobID
        requested.temporaryOutputURL = rawURL
        var applied = requested
        applied.requestID = secondJobID
        let result = ScanResult(
            rawFileURL: rawURL,
            width: 1,
            height: 1,
            resolution: applied.resolution,
            bitDepth: applied.bitDepth,
            backendUsed: .plugin,
            appliedOptionsEvidence: .verified(applied)
        )
        let receipt = try PendingCaptureSnapshot(
            scanResult: result,
            captureStartedAt: date(1),
            captureCompletedAt: date(2)
        )
        let running = try makeJob(requestedOptions: requested).started(at: date(1))

        XCTAssertThrowsError(try running.finalizing(with: receipt, at: date(2)))
    }

    func testFutureSchemaVersionsFailClosedAtEveryPersistedLayer() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try JSONEncoder().encode(makeCompletedSession(in: directory))

        let futureSession = try mutatedJSON(data) { root in
            root["schemaVersion"] = ScanSession.currentSchemaVersion + 1
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ScanSession.self, from: futureSession))

        let futureJob = try mutatedJSON(data) { root in
            var jobs = root["jobs"] as! [[String: Any]]
            jobs[0]["schemaVersion"] = ScanJob.currentSchemaVersion + 1
            root["jobs"] = jobs
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ScanSession.self, from: futureJob))

        let futureManifest = try mutatedJSON(data) { root in
            var jobs = root["jobs"] as! [[String: Any]]
            var manifest = jobs[0]["captureManifest"] as! [String: Any]
            manifest["schemaVersion"] = CaptureManifest.currentSchemaVersion + 1
            jobs[0]["captureManifest"] = manifest
            root["jobs"] = jobs
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ScanSession.self, from: futureManifest))

        let finalizingData = try JSONEncoder().encode(makeFinalizingSession(in: directory))
        let futureReceipt = try mutatedJSON(finalizingData) { root in
            var jobs = root["jobs"] as! [[String: Any]]
            var receipt = jobs[0]["pendingCapture"] as! [String: Any]
            receipt["schemaVersion"] = PendingCaptureSnapshot.currentSchemaVersion + 1
            jobs[0]["pendingCapture"] = receipt
            root["jobs"] = jobs
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ScanSession.self, from: futureReceipt))

        let futureObservation = try mutatedJSON(finalizingData) { root in
            var jobs = root["jobs"] as! [[String: Any]]
            var receipt = jobs[0]["pendingCapture"] as! [String: Any]
            var observation = receipt["rawObservation"] as! [String: Any]
            observation["schemaVersion"] = CaptureFileObservation.currentSchemaVersion + 1
            receipt["rawObservation"] = observation
            jobs[0]["pendingCapture"] = receipt
            root["jobs"] = jobs
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ScanSession.self, from: futureObservation))
    }

    func testBoolAsNumberIsRejectedByCodableContract() throws {
        let session = try ScanSession(
            id: sessionID,
            createdAt: baseDate,
            device: makeDevice(),
            backend: makeBackend(),
            environment: makeEnvironment(),
            jobs: [try makeJob()]
        )
        let data = try JSONEncoder().encode(session)
        let malformed = try mutatedJSON(data) { root in
            var jobs = root["jobs"] as! [[String: Any]]
            var options = jobs[0]["requestedOptions"] as! [String: Any]
            options["infraredEnabled"] = 1
            jobs[0]["requestedOptions"] = options
            root["jobs"] = jobs
        }

        XCTAssertThrowsError(try JSONDecoder().decode(ScanSession.self, from: malformed))
    }

    func testLeafWorkflowValuesFailClosedWhenDecodedDirectly() throws {
        let invalidIdentity = Data(
            """
            {"originalURL":"file:///tmp/raw.tiff","byteCount":0,"sha256":"bad"}
            """.utf8
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(CaptureFileIdentity.self, from: invalidIdentity)
        )

        let invalidBackend = Data(
            """
            {"type":"plugin","identifier":" ","pluginIdentifier":"plugin"}
            """.utf8
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(ScanBackendSnapshot.self, from: invalidBackend)
        )

        let invalidEnvironment = Data(
            """
            {"applicationName":"negaflow","applicationVersion":"","operatingSystem":"macOS","operatingSystemVersion":"15"}
            """.utf8
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(ScanEnvironmentSnapshot.self, from: invalidEnvironment)
        )

        let validResult = CaptureResultSnapshot(
            width: 1,
            height: 1,
            resolution: .r3600,
            bitDepth: .sixteen,
            colorSpace: "sRGB",
            hasInfraredChannel: false,
            reportedDuration: 0,
            backendUsed: .plugin
        )
        let invalidResult = try mutatedJSON(try JSONEncoder().encode(validResult)) { root in
            root["width"] = 0
        }
        XCTAssertThrowsError(
            try JSONDecoder().decode(CaptureResultSnapshot.self, from: invalidResult)
        )

        let missingReportedKey = try mutatedJSON(try JSONEncoder().encode(validResult)) { root in
            root.removeValue(forKey: "reportedResolution")
        }
        XCTAssertThrowsError(
            try JSONDecoder().decode(CaptureResultSnapshot.self, from: missingReportedKey)
        )

        let legacyResult = CaptureResultSnapshot(
            width: 1,
            height: 1,
            resolution: .r3600,
            bitDepth: .sixteen,
            reportedResolution: nil,
            reportedBitDepth: nil,
            colorSpace: "sRGB",
            hasInfraredChannel: false,
            reportedDuration: 0,
            backendUsed: .plugin
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                CaptureResultSnapshot.self,
                from: JSONEncoder().encode(legacyResult)
            ),
            legacyResult
        )

        let invalidObservation = Data(
            """
            {"schemaVersion":1,"originalURL":"file:///tmp/raw.tiff","device":1,"inode":2,"byteCount":0,"modifiedSeconds":1,"modifiedNanoseconds":0,"changedSeconds":1,"changedNanoseconds":0}
            """.utf8
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(CaptureFileObservation.self, from: invalidObservation)
        )
    }

    func testSessionRejectsDuplicateJobUUIDAndOrdinal() throws {
        let first = try makeJob(id: firstJobID, ordinal: 1)
        let second = try makeJob(id: secondJobID, ordinal: 2)
        let session = try ScanSession(
            id: sessionID,
            createdAt: baseDate,
            device: makeDevice(),
            backend: makeBackend(),
            environment: makeEnvironment(),
            jobs: [first, second]
        )
        let data = try JSONEncoder().encode(session)

        let duplicateID = try mutatedJSON(data) { root in
            var jobs = root["jobs"] as! [[String: Any]]
            jobs[1]["id"] = jobs[0]["id"]
            root["jobs"] = jobs
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ScanSession.self, from: duplicateID))

        let duplicateOrdinal = try mutatedJSON(data) { root in
            var jobs = root["jobs"] as! [[String: Any]]
            jobs[1]["ordinal"] = jobs[0]["ordinal"]
            root["jobs"] = jobs
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ScanSession.self, from: duplicateOrdinal))
    }

    func testSessionRejectsOutOfOrderAndGappedOrdinals() throws {
        let first = try makeJob(id: firstJobID, ordinal: 1)
        let second = try makeJob(id: secondJobID, ordinal: 2)

        XCTAssertThrowsError(
            try ScanSession(
                id: sessionID,
                createdAt: baseDate,
                device: makeDevice(),
                backend: makeBackend(),
                environment: makeEnvironment(),
                jobs: [second, first]
            )
        )

        let third = try makeJob(id: secondJobID, ordinal: 3)
        XCTAssertThrowsError(
            try ScanSession(
                id: sessionID,
                createdAt: baseDate,
                device: makeDevice(),
                backend: makeBackend(),
                environment: makeEnvironment(),
                jobs: [first, third]
            )
        )

        let empty = try ScanSession(
            id: sessionID,
            createdAt: baseDate,
            device: makeDevice(),
            backend: makeBackend(),
            environment: makeEnvironment()
        )
        XCTAssertThrowsError(try empty.appending(third))

        let running = try first.started(at: date(1))
        XCTAssertThrowsError(try empty.appending(running))
    }

    func testSessionRejectsSessionMismatchAndStatePayloadMismatch() throws {
        let session = try ScanSession(
            id: sessionID,
            createdAt: baseDate,
            device: makeDevice(),
            backend: makeBackend(),
            environment: makeEnvironment(),
            jobs: [try makeJob()]
        )
        let data = try JSONEncoder().encode(session)

        let wrongSession = try mutatedJSON(data) { root in
            var jobs = root["jobs"] as! [[String: Any]]
            jobs[0]["sessionID"] = UUID().uuidString
            root["jobs"] = jobs
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ScanSession.self, from: wrongSession))

        let missingSuccessPayload = try mutatedJSON(data) { root in
            var jobs = root["jobs"] as! [[String: Any]]
            jobs[0]["state"] = ScanJobState.succeeded.rawValue
            root["jobs"] = jobs
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ScanSession.self, from: missingSuccessPayload))
    }

    func testSessionRejectsPreviewFullKindMismatch() throws {
        var previewOptions = ScanOptions.preview(scannerID: makeDevice().id)
        previewOptions.requestID = firstJobID
        previewOptions.temporaryOutputURL = URL(fileURLWithPath: "/tmp/preview-\(firstJobID).tiff")
        let previewJob = try ScanJob(
            id: firstJobID,
            sessionID: sessionID,
            ordinal: 1,
            kind: .preview,
            requestedOptions: previewOptions,
            createdAt: baseDate
        )
        let session = try ScanSession(
            id: sessionID,
            createdAt: baseDate,
            device: makeDevice(),
            backend: makeBackend(),
            environment: makeEnvironment(),
            jobs: [previewJob]
        )
        let data = try JSONEncoder().encode(session)
        let malformed = try mutatedJSON(data) { root in
            var jobs = root["jobs"] as! [[String: Any]]
            jobs[0]["kind"] = ScanJobKind.full.rawValue
            root["jobs"] = jobs
        }

        XCTAssertThrowsError(try JSONDecoder().decode(ScanSession.self, from: malformed))
    }

    func testSessionEnforcesHardwareAndFinalizationFrontiers() throws {
        let firstQueued = try makeJob(id: firstJobID, ordinal: 1)
        let secondRunning = try makeJob(id: secondJobID, ordinal: 2).started(at: date(1))
        XCTAssertThrowsError(
            try ScanSession(
                id: sessionID,
                createdAt: baseDate,
                device: makeDevice(),
                backend: makeBackend(),
                environment: makeEnvironment(),
                jobs: [firstQueued, secondRunning]
            )
        )

        let firstRunning = try firstQueued.started(at: date(1))
        XCTAssertThrowsError(
            try ScanSession(
                id: sessionID,
                createdAt: baseDate,
                device: makeDevice(),
                backend: makeBackend(),
                environment: makeEnvironment(),
                jobs: [firstRunning, secondRunning]
            )
        )

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("frontier-1.tiff")
        let secondURL = directory.appendingPathComponent("frontier-2.tiff")
        try Data([1]).write(to: firstURL)
        try Data([2]).write(to: secondURL)
        let firstFinalizing = try makeFinalizingJob(
            id: firstJobID,
            ordinal: 1,
            rawURL: firstURL
        )
        let secondFinalizing = try makeFinalizingJob(
            id: secondJobID,
            ordinal: 2,
            rawURL: secondURL
        )
        let thirdID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let thirdRunning = try makeJob(id: thirdID, ordinal: 3).started(at: date(2))
        XCTAssertNoThrow(
            try ScanSession(
                id: sessionID,
                createdAt: baseDate,
                device: makeDevice(),
                backend: makeBackend(),
                environment: makeEnvironment(),
                jobs: [firstFinalizing, secondFinalizing, thirdRunning]
            )
        )

        let secondManifest = try CaptureManifest.build(
            sessionID: sessionID,
            jobID: secondJobID,
            attempt: 1,
            kind: .full,
            requestedOptions: secondFinalizing.requestedOptions,
            pendingCapture: try XCTUnwrap(secondFinalizing.pendingCapture),
            chunkSize: 1
        )
        let secondSucceeded = try secondFinalizing.succeeded(
            with: secondManifest,
            at: date(3)
        )
        XCTAssertThrowsError(
            try ScanSession(
                id: sessionID,
                createdAt: baseDate,
                device: makeDevice(),
                backend: makeBackend(),
                environment: makeEnvironment(),
                jobs: [firstFinalizing, secondSucceeded]
            )
        )
    }

    func testSessionRejectsPendingBackendMismatch() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rawURL = directory.appendingPathComponent("wrong-backend.tiff")
        try Data([1]).write(to: rawURL)
        let finalizing = try makeFinalizingJob(
            id: firstJobID,
            ordinal: 1,
            rawURL: rawURL,
            resultBackend: .mock
        )

        XCTAssertThrowsError(
            try ScanSession(
                id: sessionID,
                createdAt: baseDate,
                device: makeDevice(),
                backend: makeBackend(),
                environment: makeEnvironment(),
                jobs: [finalizing]
            )
        )
    }

    func testUnknownLegacyRequiresPluginAndResultResolutionMustMatchKind() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rawURL = directory.appendingPathComponent("legacy-kind.tiff")
        try Data([1]).write(to: rawURL)
        var options = ScanOptions.strongDefault(scannerID: makeDevice().id)
        options.requestID = firstJobID
        options.temporaryOutputURL = rawURL
        let mockResult = CaptureResultSnapshot(
            width: 1,
            height: 1,
            resolution: .r3600,
            bitDepth: .sixteen,
            colorSpace: "sRGB",
            hasInfraredChannel: false,
            reportedDuration: 1,
            backendUsed: .mock
        )
        XCTAssertThrowsError(
            try PendingCaptureSnapshot(
                result: mockResult,
                appliedOptionsEvidence: .unknownLegacy(protocolVersion: 1),
                captureStartedAt: date(1),
                captureCompletedAt: date(2),
                rawFileURL: rawURL
            )
        )

        let previewResult = CaptureResultSnapshot(
            width: 1,
            height: 1,
            resolution: .preview,
            bitDepth: .eight,
            colorSpace: "sRGB",
            hasInfraredChannel: false,
            reportedDuration: 1,
            backendUsed: .plugin
        )
        let receipt = try PendingCaptureSnapshot(
            result: previewResult,
            appliedOptionsEvidence: .unknownLegacy(protocolVersion: 1),
            captureStartedAt: date(1),
            captureCompletedAt: date(2),
            rawFileURL: rawURL
        )
        let running = try makeJob(requestedOptions: options).started(at: date(1))
        XCTAssertThrowsError(try running.finalizing(with: receipt, at: date(2)))
    }

    func testManifestDecodeRejectsRGBAndIRAliasing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try JSONEncoder().encode(makeCompletedSession(in: directory))
        let malformed = try mutatedJSON(data) { root in
            var jobs = root["jobs"] as! [[String: Any]]
            var manifest = jobs[0]["captureManifest"] as! [String: Any]
            let rgbFile = manifest["rgbFile"] as! [String: Any]
            var infraredFile = manifest["infraredFile"] as! [String: Any]
            infraredFile["originalURL"] = rgbFile["originalURL"]
            manifest["infraredFile"] = infraredFile
            jobs[0]["captureManifest"] = manifest
            root["jobs"] = jobs
        }

        XCTAssertThrowsError(try JSONDecoder().decode(ScanSession.self, from: malformed))
    }

    func testPluginSnapshotRequiresSafeIdentifierAndMatchingDeviceNamespace() throws {
        let unsafeBackend = ScanBackendSnapshot(
            type: .plugin,
            identifier: "external-json",
            pluginIdentifier: "unsafe:id"
        )
        XCTAssertThrowsError(
            try ScanSession(
                id: sessionID,
                createdAt: baseDate,
                device: makeDevice(),
                backend: unsafeBackend,
                environment: makeEnvironment()
            )
        )

        let mismatchedBackend = ScanBackendSnapshot(
            type: .plugin,
            identifier: "external-json",
            pluginIdentifier: "other-plugin"
        )
        XCTAssertThrowsError(
            try ScanSession(
                id: sessionID,
                createdAt: baseDate,
                device: makeDevice(),
                backend: mismatchedBackend,
                environment: makeEnvironment()
            )
        )
    }

    func testSessionReplacementPreservesJobIdentityFields() throws {
        let original = try makeJob()
        let session = try ScanSession(
            id: sessionID,
            createdAt: baseDate,
            device: makeDevice(),
            backend: makeBackend(),
            environment: makeEnvironment(),
            jobs: [original]
        )
        let started = try original.started(at: date(1))
        XCTAssertEqual(try session.replacing(started).jobs.first, started)

        let changedOrdinal = try ScanJob(
            id: original.id,
            sessionID: original.sessionID,
            ordinal: 2,
            kind: original.kind,
            requestedOptions: original.requestedOptions,
            framePublication: original.framePublication,
            createdAt: original.createdAt
        )
        XCTAssertThrowsError(try session.replacing(changedOrdinal))

        var changedKindOptions = ScanOptions.preview(
            scannerID: original.requestedOptions.scannerID
        )
        changedKindOptions.requestID = original.id
        changedKindOptions.temporaryOutputURL = original.requestedOptions.temporaryOutputURL
        let changedKind = try ScanJob(
            id: original.id,
            sessionID: original.sessionID,
            ordinal: original.ordinal,
            kind: .preview,
            requestedOptions: changedKindOptions,
            createdAt: original.createdAt
        )
        XCTAssertThrowsError(try session.replacing(changedKind))

        let changedCreatedAt = try ScanJob(
            id: original.id,
            sessionID: original.sessionID,
            ordinal: original.ordinal,
            kind: original.kind,
            requestedOptions: original.requestedOptions,
            framePublication: original.framePublication,
            createdAt: date(1)
        )
        XCTAssertThrowsError(try session.replacing(changedCreatedAt))
    }

    func testSessionReplacementRejectsForgedTransitionTimestamps() throws {
        let queued = try makeJob()
        let running = try queued.started(at: date(1))
        let session = try ScanSession(
            id: sessionID,
            createdAt: baseDate,
            device: makeDevice(),
            backend: makeBackend(),
            environment: makeEnvironment(),
            jobs: [running]
        )
        let forged = try ScanJob(
            id: running.id,
            sessionID: running.sessionID,
            ordinal: running.ordinal,
            attempt: running.attempt,
            kind: running.kind,
            state: .cancelled,
            requestedOptions: running.requestedOptions,
            framePublication: running.framePublication,
            createdAt: running.createdAt,
            updatedAt: date(2),
            startedAt: nil,
            finishedAt: date(2)
        )

        XCTAssertThrowsError(try session.replacing(forged))
    }

    func testJobAndManifestRequireJobUUIDAsRequestID() throws {
        var options = ScanOptions.strongDefault(scannerID: makeDevice().id)
        options.temporaryOutputURL = URL(fileURLWithPath: "/tmp/request-id.tiff")
        XCTAssertThrowsError(
            try ScanJob(
                id: firstJobID,
                sessionID: sessionID,
                ordinal: 1,
                kind: .full,
                requestedOptions: options,
                createdAt: baseDate
            )
        )

        options.requestID = UUID()
        XCTAssertThrowsError(
            try ScanJob(
                id: firstJobID,
                sessionID: sessionID,
                ordinal: 1,
                kind: .full,
                requestedOptions: options,
                createdAt: baseDate
            )
        )
    }

    func testSessionRejectsMissingDeviceVendorAndModel() throws {
        let emptyVendor = ScannerDescriptor(
            id: makeDevice().id,
            displayName: makeDevice().displayName,
            vendor: " ",
            model: makeDevice().model,
            backendType: .plugin
        )
        XCTAssertThrowsError(
            try ScanSession(
                id: sessionID,
                createdAt: baseDate,
                device: emptyVendor,
                backend: makeBackend(),
                environment: makeEnvironment()
            )
        )

        let emptyModel = ScannerDescriptor(
            id: makeDevice().id,
            displayName: makeDevice().displayName,
            vendor: makeDevice().vendor,
            model: "\n",
            backendType: .plugin
        )
        XCTAssertThrowsError(
            try ScanSession(
                id: sessionID,
                createdAt: baseDate,
                device: emptyModel,
                backend: makeBackend(),
                environment: makeEnvironment()
            )
        )
    }

    private func makeFinalizingJob(
        id: UUID,
        ordinal: Int,
        rawURL: URL,
        resultBackend: BackendType = .plugin
    ) throws -> ScanJob {
        var options = ScanOptions.strongDefault(scannerID: makeDevice().id)
        options.requestID = id
        options.temporaryOutputURL = rawURL
        let result = CaptureResultSnapshot(
            width: 2,
            height: 2,
            resolution: options.resolution,
            bitDepth: options.bitDepth,
            colorSpace: "sRGB",
            hasInfraredChannel: false,
            reportedDuration: 1,
            backendUsed: resultBackend
        )
        let receipt = try PendingCaptureSnapshot(
            result: result,
            appliedOptionsEvidence: .verified(options),
            captureStartedAt: date(1),
            captureCompletedAt: date(2),
            rawFileURL: rawURL
        )
        return try makeJob(
            id: id,
            ordinal: ordinal,
            requestedOptions: options
        )
        .started(at: date(1))
        .finalizing(with: receipt, at: date(2))
    }

    private func makeFinalizingSession(in directory: URL) throws -> ScanSession {
        let rawURL = directory.appendingPathComponent("pending-schema.tiff")
        try Data([4, 5, 6]).write(to: rawURL)
        var options = ScanOptions.strongDefault(scannerID: makeDevice().id)
        options.requestID = firstJobID
        options.temporaryOutputURL = rawURL
        let running = try makeJob(requestedOptions: options).started(at: date(1))
        let result = ScanResult(
            rawFileURL: rawURL,
            width: 2,
            height: 2,
            resolution: options.resolution,
            bitDepth: options.bitDepth,
            backendUsed: .plugin,
            appliedOptionsEvidence: .verified(options)
        )
        let receipt = try PendingCaptureSnapshot(
            scanResult: result,
            captureStartedAt: date(1),
            captureCompletedAt: date(2)
        )
        let finalizing = try running.finalizing(with: receipt, at: date(2))
        return try ScanSession(
            id: sessionID,
            createdAt: baseDate,
            device: makeDevice(),
            backend: makeBackend(),
            environment: makeEnvironment(),
            jobs: [finalizing]
        )
    }

    private func makeCompletedSession(in directory: URL) throws -> ScanSession {
        let rgbURL = directory.appendingPathComponent("raw.tiff")
        let infraredURL = directory.appendingPathComponent("raw.ir.tiff")
        try Data([1, 2, 3, 4, 5]).write(to: rgbURL)
        try Data([9, 8, 7, 6]).write(to: infraredURL)

        var options = ScanOptions.strongDefault(scannerID: makeDevice().id)
        options.requestID = firstJobID
        options.infraredEnabled = true
        options.temporaryOutputURL = rgbURL
        let queued = try makeJob(requestedOptions: options)
        let running = try queued.started(at: date(1))
        let result = ScanResult(
            rawFileURL: rgbURL,
            width: 12,
            height: 8,
            resolution: .r3600,
            bitDepth: .sixteen,
            colorSpace: "Display P3",
            hasInfraredChannel: true,
            infraredFileURL: infraredURL,
            scanDuration: 1.5,
            backendUsed: .plugin,
            warnings: ["calibration due soon"],
            appliedOptionsEvidence: .verified(options)
        )
        let pending = try PendingCaptureSnapshot(
            scanResult: result,
            captureStartedAt: date(1),
            captureCompletedAt: date(2)
        )
        let finalizing = try running.finalizing(with: pending, at: date(2))
        let manifest = try CaptureManifest.build(
            id: manifestID,
            sessionID: sessionID,
            jobID: firstJobID,
            attempt: 1,
            kind: .full,
            requestedOptions: options,
            pendingCapture: pending,
            chunkSize: 2
        )
        let succeeded = try finalizing.succeeded(with: manifest, at: date(3))
        return try ScanSession(
            id: sessionID,
            createdAt: baseDate,
            device: makeDevice(),
            backend: makeBackend(),
            environment: makeEnvironment(),
            jobs: [succeeded]
        )
    }

    private func makeJob(
        id: UUID? = nil,
        ordinal: Int = 1,
        requestedOptions: ScanOptions? = nil
    ) throws -> ScanJob {
        let resolvedID = id ?? firstJobID
        var options = requestedOptions ?? .strongDefault(scannerID: makeDevice().id)
        options.requestID = resolvedID
        if options.temporaryOutputURL == nil {
            options.temporaryOutputURL = URL(
                fileURLWithPath: "/tmp/negaflow-scan-job-\(resolvedID.uuidString).tiff"
            )
        }
        return try ScanJob(
            id: resolvedID,
            sessionID: sessionID,
            ordinal: ordinal,
            kind: .full,
            requestedOptions: options,
            framePublication: try ScanFramePublicationSnapshot(
                frameID: resolvedID,
                scanIndex: ordinal,
                initialTransform: .identity,
                developTarget: .main,
                storageGroupName: "TestScanner"
            ),
            createdAt: baseDate
        )
    }

    private func makeDevice() -> ScannerDescriptor {
        ScannerDescriptor(
            id: "plugin:test-plugin:scanner-1",
            displayName: "Test Film Scanner",
            vendor: "Test",
            model: "FS-1",
            backendType: .plugin,
            serialNumber: "SERIAL-1",
            verifiedStatus: .verified,
            firmwareVersion: "3.0",
            driverVersion: "4.0"
        )
    }

    private func makeBackend() -> ScanBackendSnapshot {
        ScanBackendSnapshot(
            type: .plugin,
            identifier: "external-json",
            version: "1.2.0",
            pluginIdentifier: "test-plugin",
            pluginVersion: "2.4.1"
        )
    }

    private func makeEnvironment() -> ScanEnvironmentSnapshot {
        ScanEnvironmentSnapshot(
            applicationName: "negaflow",
            applicationVersion: "1.0",
            operatingSystem: "macOS",
            operatingSystemVersion: "15.5",
            architecture: "arm64"
        )
    }

    private func date(_ offset: TimeInterval) -> Date {
        baseDate.addingTimeInterval(offset)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-scan-workflow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func mutatedJSON(
        _ data: Data,
        mutation: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        try mutation(&root)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
}
