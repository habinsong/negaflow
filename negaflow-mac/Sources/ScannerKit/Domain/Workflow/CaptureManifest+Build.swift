import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

extension CaptureManifest {
    /// 백엔드 성공 receipt의 RGB/IR 파일을 스트리밍 해시하여 manifest를 만든다.
    public static func build(
        id: UUID = UUID(),
        sessionID: UUID,
        jobID: UUID,
        attempt: Int,
        kind: ScanJobKind,
        requestedOptions: ScanOptions,
        pendingCapture: PendingCaptureSnapshot,
        chunkSize: Int = 1_048_576
    ) throws -> CaptureManifest {
        try pendingCapture.verifyCurrentFiles()
        let rgbFile = try CaptureFileIdentity.build(
            for: pendingCapture.rawFileURL,
            expectedObservation: pendingCapture.rawObservation,
            chunkSize: chunkSize
        )
        let infraredFile: CaptureFileIdentity?
        if let infraredFileURL = pendingCapture.infraredFileURL,
           let infraredObservation = pendingCapture.infraredObservation {
            infraredFile = try CaptureFileIdentity.build(
                for: infraredFileURL,
                expectedObservation: infraredObservation,
                chunkSize: chunkSize
            )
        } else {
            infraredFile = nil
        }
        try pendingCapture.verifyCurrentFiles()
        return try CaptureManifest(
            id: id,
            sessionID: sessionID,
            jobID: jobID,
            attempt: attempt,
            kind: kind,
            requestedOptions: requestedOptions,
            appliedOptionsEvidence: pendingCapture.appliedOptionsEvidence,
            result: pendingCapture.result,
            captureStartedAt: pendingCapture.captureStartedAt,
            captureCompletedAt: pendingCapture.captureCompletedAt,
            rgbFile: rgbFile,
            infraredFile: infraredFile,
            rgbObservation: pendingCapture.rawObservation,
            infraredObservation: pendingCapture.infraredObservation
        )
    }

    /// 캡처 직후 호출하는 편의 API. 영속 workflow에서는 먼저 PendingCaptureSnapshot을
    /// 저장한 뒤 위 overload로 fixity를 계산한다.
    public static func build(
        id: UUID = UUID(),
        sessionID: UUID,
        jobID: UUID,
        attempt: Int,
        kind: ScanJobKind,
        requestedOptions: ScanOptions,
        scanResult: ScanResult,
        captureStartedAt: Date,
        captureCompletedAt: Date,
        chunkSize: Int = 1_048_576
    ) throws -> CaptureManifest {
        let pendingCapture = try PendingCaptureSnapshot(
            scanResult: scanResult,
            captureStartedAt: captureStartedAt,
            captureCompletedAt: captureCompletedAt
        )
        return try build(
            id: id,
            sessionID: sessionID,
            jobID: jobID,
            attempt: attempt,
            kind: kind,
            requestedOptions: requestedOptions,
            pendingCapture: pendingCapture,
            chunkSize: chunkSize
        )
    }

}
