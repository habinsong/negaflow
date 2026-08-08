import Foundation
import CoreGraphics
import ImageIO
import Chromabase

extension ExternalScannerBackend {
    func scan(
        _ options: ScanOptions,
        preview: Bool,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        try validatePluginCompatibility()
        let protocolVersion = plugin.manifest.resolvedProtocolVersion
        let requestID = protocolVersion == ScannerPluginManifest.streamProtocolVersion
            ? (options.requestID ?? UUID())
            : nil
        let outputURL = options.temporaryOutputURL
            ?? ScanTempFile.makeURL(prefix: "negaflow_plugin", suffix: ".tiff")
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw failure(.ioFailure, "plugin scan 최종 경로가 이미 존재함: \(outputURL.path)")
        }
        let stagingDirectory = outputURL.deletingLastPathComponent().appendingPathComponent(
            ".negaflow-scan-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
        } catch {
            throw failure(.ioFailure, "plugin scan staging 생성 실패: \(error.localizedDescription)")
        }
        let stagingOutputURL = stagingDirectory.appendingPathComponent(outputURL.lastPathComponent)
        var committedInfraredURL: URL?
        var didCommitRaw = false
        defer {
            try? FileManager.default.removeItem(at: stagingDirectory)
            if !didCommitRaw, let committedInfraredURL {
                try? FileManager.default.removeItem(at: committedInfraredURL)
            }
        }
        let wire = PluginScanOptions(
            protocolVersion: requestID == nil ? nil : protocolVersion,
            requestID: requestID,
            deviceID: internalID(options.scannerID),
            resolutionDPI: options.resolution.dpi,
            bitDepth: options.bitDepth.rawValue,
            colorMode: options.colorMode.rawValue,
            filmType: options.filmType.rawValue,
            preview: preview,
            multiExposure: options.multiExposureEnabled,
            infrared: options.infraredEnabled,
            brightnessAdjustment: options.brightnessAdjustment,
            contrastAdjustment: options.contrastAdjustment,
            scanArea: options.scanArea,
            hardwareExposureTime: options.hardwareExposureTime,
            outputRawTIFF: options.outputRawTIFF,
            capabilityToken: requestID == nil ? nil : capabilityToken(for: options.scannerID),
            outputPath: stagingOutputURL.path
        )
        let stdinData = try JSONEncoder().encode(wire)

        let sink = ScanEventSink(protocolVersion: protocolVersion, requestID: requestID)
        let start = Date()

        let out = try await run(args: ["scan"], stdin: stdinData) { line in
            if case let .progress(value) = sink.consume(line: line) {
                progress(value)
            }
            return sink.protocolError
        }

        if let protocolError = sink.protocolError {
            throw failure(.ioFailure, protocolError)
        }
        if let errorMessage = sink.error {
            throw failure(.ioFailure, errorMessage)
        }
        guard out.status == 0 else {
            throw failure(.ioFailure, "plugin scan 실패: \(out.stderrText)")
        }
        guard let resultEvent = sink.result else {
            throw failure(.ioFailure, "plugin scan 결과 누락")
        }
        let verifiedAppliedOptions: ScanOptions?
        if protocolVersion == ScannerPluginManifest.streamProtocolVersion {
            guard let requestID else {
                throw failure(.ioFailure, "plugin protocol v2 host requestID 누락")
            }
            verifiedAppliedOptions = try validatedAppliedOptions(
                resultEvent,
                requestedWire: wire,
                hostScannerID: options.scannerID,
                requestID: requestID,
                finalOutputURL: outputURL,
                preview: preview
            )
        } else {
            verifiedAppliedOptions = nil
        }
        let rawArtifact = try validatedRawResult(
            resultEvent,
            expectedURL: stagingOutputURL,
            verifiedAppliedOptions: verifiedAppliedOptions
        )
        let infraredURL = try validatedInfraredResult(
            resultEvent,
            requested: verifiedAppliedOptions?.infraredEnabled ?? options.infraredEnabled,
            matching: rawArtifact,
            stagingDirectory: stagingDirectory,
            requiresStagedPath: protocolVersion == ScannerPluginManifest.streamProtocolVersion
        )
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw failure(.ioFailure, "plugin scan 최종 경로가 이미 존재함: \(outputURL.path)")
        }

        let finalInfraredURL: URL?
        if let infraredURL, isInsideStagingDirectory(infraredURL, stagingDirectory: stagingDirectory) {
            let destination = URL(fileURLWithPath: outputURL.path + ".ir.tiff")
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw failure(.ioFailure, "plugin IR 최종 경로가 이미 존재함: \(destination.path)")
            }
            do {
                try FileManager.default.moveItem(at: infraredURL, to: destination)
                committedInfraredURL = destination
                finalInfraredURL = destination
            } catch {
                throw failure(.ioFailure, "plugin IR 결과 commit 실패: \(error.localizedDescription)")
            }
        } else {
            // 구버전 플러그인이 outputPath 밖에 IR을 쓰는 계약은 그대로 허용한다.
            finalInfraredURL = infraredURL
        }

        do {
            // staging과 최종 파일을 같은 디렉터리 트리에 두므로 이 move는 같은 볼륨의 rename이다.
            try FileManager.default.moveItem(at: rawArtifact.url, to: outputURL)
            didCommitRaw = true
        } catch {
            throw failure(.ioFailure, "plugin scan 결과 commit 실패: \(error.localizedDescription)")
        }
        let reportedResolution = verifiedAppliedOptions?.resolution
            ?? validLegacyReportedResolution(resultEvent.resolutionDPI, preview: preview)
        let reportedBitDepth = verifiedAppliedOptions?.bitDepth
            ?? resultEvent.bitDepth.flatMap(BitDepth.init(rawValue:))
        return ScanResult(
            rawFileURL: outputURL,
            width: rawArtifact.width,
            height: rawArtifact.height,
            resolution: reportedResolution ?? options.resolution,
            bitDepth: reportedBitDepth ?? options.bitDepth,
            reportedResolution: reportedResolution,
            reportedBitDepth: reportedBitDepth,
            hasInfraredChannel: finalInfraredURL != nil,
            infraredFileURL: finalInfraredURL,
            scanDuration: Date().timeIntervalSince(start),
            backendUsed: .plugin,
            warnings: resultEvent.warnings ?? [],
            appliedOptionsEvidence: verifiedAppliedOptions.map(AppliedScanOptionsEvidence.verified)
                ?? .unknownLegacy(protocolVersion: ScannerPluginManifest.legacyProtocolVersion)
        )
    }


}
