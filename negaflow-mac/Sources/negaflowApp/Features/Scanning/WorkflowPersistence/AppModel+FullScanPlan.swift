import AppKit
import Chromabase
import Foundation
import ScannerKit

extension AppModel {
    func makeFullScanPlan(
        count: Int,
        scannerID: String,
        backend: ScannerBackend,
        capabilities: ScannerCapabilities,
        sessionID: UUID,
        previewCarryover: PreviewScanCarryover?,
        flatbedRegions: [FlatbedScanRegion],
        flatbedPreviewScanArea: ScanArea?
    ) async throws -> FullScanPlan {
        guard flatbedRegions.isEmpty || flatbedRegions.count == count else {
            throw ScannerError(.unsupportedOption, text(AppLocalizedPhrase.scanWorkflowInvalidState))
        }
        guard flatbedRegions.isEmpty || flatbedPreviewScanArea != nil else {
            throw ScannerError(.unsupportedOption, text(AppLocalizedPhrase.scanWorkflowInvalidState))
        }
        let device: ScannerDescriptor
        if let selected = devices.first(where: { $0.id == scannerID }) {
            device = selected
        } else {
            let detected = try await backend.detectScanners()
            guard activeScanSessionID == sessionID,
                  let exact = detected.first(where: { $0.id == scannerID }) else {
                throw ScannerError(.notConnected, text(AppLocalizedPhrase.scanDeviceUnavailable))
            }
            device = exact
        }
        guard device.backendType == backend.backendType else {
            throw ScannerError(.ioFailure, text(AppLocalizedPhrase.scanWorkflowInvalidState))
        }

        let createdAt = Date()
        let scannerAbbreviation = FrameStorageNaming.scannerAbbreviation(device.displayName)
        let scanFilmType = self.scanFilmType
        let developFilmType = scanDevelopFilmType
        let requestedFolderName = resolvedScanFolderName
        let filmTypeFolder = scanFolderParentURL(for: createdAt)
        let createdFolderDestination = recentCreatedScanFolder
        let continuingRoll: LibraryRoll?
        if let createdFolderDestination {
            continuingRoll = rolls.reversed().first(where: { roll in
                roll.kind == .physical
                    && roll.filmType == scanFilmType
                    && shouldContinueScan(
                        in: roll,
                        scannerAbbreviation: scannerAbbreviation
                    )
                    && existingScanFolder(for: roll) == createdFolderDestination
                })
        } else {
            continuingRoll = activeRoll.flatMap { roll in
                guard roll.filmType == scanFilmType,
                      roll.name == requestedFolderName,
                      shouldContinueScan(
                          in: roll,
                          scannerAbbreviation: scannerAbbreviation
                      ) else {
                    return nil
                }
                return roll
            }
        }
        let outputFolder: URL
        let assignment: LibraryScanRollAssignment
        if let createdFolderDestination {
            let folderName = FrameStorageNaming.sanitizeComponent(
                createdFolderDestination.lastPathComponent
            )
            let draftName = folderName.isEmpty
                ? text(AppLocalizedPhrase.untitledFilm)
                : folderName
            if let continuingRoll {
                assignment = LibraryScanRollAssignment(
                    sessionID: sessionID,
                    rollID: continuingRoll.id,
                    draftName: continuingRoll.name ?? draftName,
                    filmType: scanFilmType,
                    developFilmType: developFilmType,
                    createdAt: createdAt
                )
            } else {
                assignment = LibraryScanRollAssignment(
                    sessionID: sessionID,
                    rollID: UUID(),
                    draftName: draftName,
                    filmType: scanFilmType,
                    developFilmType: developFilmType,
                    createdAt: createdAt
                )
            }
            outputFolder = createdFolderDestination
        } else if let continuingRoll {
            guard let name = continuingRoll.name,
                  let rollFilmType = continuingRoll.filmType,
                  rollFilmType == scanFilmType else {
                throw ScannerError(.unsupportedOption, text(AppLocalizedPhrase.scanRollFilmMismatch))
            }
            outputFolder = existingScanFolder(for: continuingRoll) ?? filmTypeFolder
                .appendingPathComponent(
                    FrameStorageNaming.sanitizeComponent(name),
                    isDirectory: true
                )
            assignment = LibraryScanRollAssignment(
                sessionID: sessionID,
                rollID: continuingRoll.id,
                draftName: name,
                filmType: rollFilmType,
                developFilmType: developFilmType,
                createdAt: createdAt
            )
        } else {
            let folderName = FrameStorageNaming.availableFilmFolderName(
                requestedFolderName,
                in: filmTypeFolder
            )
            outputFolder = filmTypeFolder.appendingPathComponent(folderName, isDirectory: true)
            assignment = LibraryScanRollAssignment(
                sessionID: sessionID,
                rollID: UUID(),
                draftName: folderName,
                filmType: scanFilmType,
                developFilmType: developFilmType,
                createdAt: createdAt
            )
        }
        do {
            try FileManager.default.createDirectory(
                at: outputFolder,
                withIntermediateDirectories: true
            )
        } catch {
            throw ScannerError(
                .ioFailure,
                text(AppLocalizedPhrase.scanOutputFolderFailedFormat, error.localizedDescription)
            )
        }

        let firstOutputNumber = FrameStorageNaming.nextFrameNumber(
            in: outputFolder,
            prefix: scannerAbbreviation
        )
        let standardizedOutputFolder = outputFolder.standardizedFileURL
        let existingFrameMaximum = frames.lazy
            .filter {
                !$0.isPreviewScan
                    && $0.sourceFrameID == nil
                    && $0.sourceKind == .scannerTIFF
                    && $0.rawScanURL.deletingLastPathComponent().standardizedFileURL
                        == standardizedOutputFolder
            }
            .map(\.scanIndex)
            .max() ?? 0
        let assignedSessionIDs = Set(scanRollAssignments.lazy
            .filter { $0.rollID == assignment.rollID }
            .map(\.sessionID))
        let reservedMaximum = scanSessions.lazy
            .filter { assignedSessionIDs.contains($0.id) }
            .flatMap(\.jobs)
            .filter {
                $0.requestedOptions.temporaryOutputURL?
                    .deletingLastPathComponent()
                    .standardizedFileURL == standardizedOutputFolder
            }
            .compactMap(\.framePublication?.scanIndex)
            .max() ?? 0
        let firstScanIndexResult = max(existingFrameMaximum, reservedMaximum)
            .addingReportingOverflow(1)
        guard !firstScanIndexResult.overflow else {
            throw ScannerError(.ioFailure, text(AppLocalizedPhrase.scanNumberRangeExceeded))
        }

        var jobs: [ScanJob] = []
        jobs.reserveCapacity(count)
        for offset in 0..<count {
            let outputNumber = firstOutputNumber.addingReportingOverflow(offset)
            let scanIndex = firstScanIndexResult.partialValue.addingReportingOverflow(offset)
            guard !outputNumber.overflow, !scanIndex.overflow else {
                throw ScannerError(.ioFailure, text(AppLocalizedPhrase.scanNumberRangeExceeded))
            }
            let jobID = UUID()
            var options = ScanOptions.strongDefault(scannerID: scannerID)
            options.requestID = jobID
            options.resolution = resolutionChoice
            options.bitDepth = bitDepthChoice
            options.colorMode = colorModeChoice
            options.filmType = scanFilmType
            options.multiExposureEnabled = false
            options.infraredEnabled = infraredEnabled
                && capabilities.supportsInfrared
                && InfraredFilmCompatibility(filmType: scanFilmType).allowsAutomaticCorrection
            options.brightnessAdjustment = Self.scannerHardwareAdjustment(
                scannerBrightness,
                range: capabilities.brightnessRange,
                scannerID: scannerID,
                bitDepth: bitDepthChoice
            )
            options.contrastAdjustment = Self.scannerHardwareAdjustment(
                scannerContrast,
                range: capabilities.contrastRange,
                scannerID: scannerID,
                bitDepth: bitDepthChoice
            )
            let flatbedRegion = flatbedRegions.indices.contains(offset)
                ? flatbedRegions[offset]
                : nil
            if let flatbedRegion,
               let scanArea = FlatbedScanRegionGeometry.physicalArea(
                   for: flatbedRegion,
                   previewScanArea: flatbedPreviewScanArea,
                   capabilities: capabilities
               ) {
                options.scanArea = scanArea
            } else if let scanArea = resolvedHardwareScanArea(for: capabilities) {
                options.scanArea = scanArea
            }
            options.temporaryOutputURL = outputFolder.appendingPathComponent(
                FrameStorageNaming.scanFileBaseName(
                    prefix: scannerAbbreviation,
                    number: outputNumber.partialValue
                ) + ".tiff"
            )
            let carryover = flatbedRegion == nil && offset == 0 ? previewCarryover : nil
            var initialTransform = Self.scannerInitialTransform(
                carryover: flatbedRegion == nil
                    ? carryover?.transform
                    : previewCarryover?.transform.orientationTemplate,
                template: nextScanOrientation,
                defaultRotation: defaultScanRotation
            )
            if let flatbedRegion {
                initialTransform.cropRect = nil
                initialTransform.cropAspect = nil
                initialTransform.straightenAngle = initialTransform.flipHorizontal
                    != initialTransform.flipVertical
                    ? -flatbedRegion.straightenAngle
                    : flatbedRegion.straightenAngle
            }
            let publication = try ScanFramePublicationSnapshot(
                scanIndex: scanIndex.partialValue,
                initialTransform: initialTransform,
                developTarget: developTarget,
                scannerProfileID: scannerProfileID,
                presetID: "neutral",
                storageGroupName: assignment.draftName,
                regionDefectDisplayROI: flatbedRegion == nil ? carryover?.defectDisplayROI : nil,
                regionDefectSensitivity: flatbedRegion != nil || carryover?.defectDisplayROI == nil
                    ? nil
                    : carryover?.defectSensitivity
            )
            jobs.append(try ScanJob(
                id: jobID,
                sessionID: sessionID,
                ordinal: offset + 1,
                kind: .full,
                requestedOptions: options,
                framePublication: publication,
                createdAt: createdAt
            ))
        }

        return FullScanPlan(
            session: try ScanSession(
                id: sessionID,
                createdAt: createdAt,
                device: device,
                backend: scanBackendSnapshot(backend),
                environment: currentScanEnvironmentSnapshot(),
                jobs: jobs
            ),
            assignment: assignment
        )
    }

    private func existingScanFolder(for roll: LibraryRoll) -> URL? {
        let memberIDs = Set(roll.frameIDs)
        guard let folder = frames.reversed().first(where: {
            memberIDs.contains($0.id)
                && !$0.isPreviewScan
                && $0.sourceKind == .scannerTIFF
                && FileManager.default.fileExists(
                    atPath: $0.rawScanURL.deletingLastPathComponent().path
                )
        })?.rawScanURL.deletingLastPathComponent().standardizedFileURL else {
            return nil
        }
        let scanRootComponents = diskStorage.scansURL.standardizedFileURL.pathComponents
        let folderComponents = folder.pathComponents
        let isInsideConfiguredScanRoot = folderComponents.count > scanRootComponents.count
            && Array(folderComponents.prefix(scanRootComponents.count)) == scanRootComponents
        if isInsideConfiguredScanRoot,
           folderComponents.count - scanRootComponents.count < 3 {
            return nil
        }
        return folder
    }

    private func shouldContinueScan(
        in roll: LibraryRoll,
        scannerAbbreviation: String
    ) -> Bool {
        guard let name = roll.name,
              !FrameStorageNaming.isLegacyScannerRollName(
                  name,
                  scannerAbbreviation: scannerAbbreviation
              ) else {
            return false
        }
        let memberIDs = Set(roll.frameIDs)
        let scannerFrames = frames.filter {
            memberIDs.contains($0.id)
                && !$0.isPreviewScan
                && $0.sourceFrameID == nil
                && $0.sourceKind == .scannerTIFF
        }
        return scannerFrames.isEmpty || scannerFrames.contains {
            FileManager.default.fileExists(atPath: $0.rawScanURL.path)
        }
    }

    private func scanBackendSnapshot(_ backend: ScannerBackend) -> ScanBackendSnapshot {
        if let external = backend as? ExternalScannerBackend {
            return ScanBackendSnapshot(
                type: .plugin,
                identifier: "external-process-json",
                version: "protocol-\(external.plugin.manifest.resolvedProtocolVersion)",
                pluginIdentifier: external.plugin.id,
                pluginVersion: external.plugin.manifest.pluginVersion
            )
        }
        return ScanBackendSnapshot(
            type: backend.backendType,
            identifier: "builtin.\(backend.backendType.rawValue)",
            version: NegaflowProductVersion.current
        )
    }

    private func currentScanEnvironmentSnapshot() -> ScanEnvironmentSnapshot {
        ScanEnvironmentSnapshot(
            applicationName: "negaflow",
            applicationVersion: NegaflowProductVersion.applicationVersion(),
            operatingSystem: "macOS",
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.currentArchitecture
        )
    }

    private nonisolated static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }


}
