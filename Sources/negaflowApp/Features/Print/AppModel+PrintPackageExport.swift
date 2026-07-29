import AppKit
import Chromabase
import Foundation

@MainActor
private struct PrintPackageFramePlan {
    let frame: ScanFrame
    let snapshot: ExportFrameSnapshot
    let trackingIdentity: ExportFrameTrackingIdentity
    let baseKey: FilmBaseCacheKey
    let layoutSize: CGSize
}

@MainActor
struct PrintPackageContributorCommit {
    let frame: ScanFrame
    let trackingIdentity: ExportFrameTrackingIdentity
    let sourceGeneration: ExportFrameSourceGeneration
    let event: LibraryExportEvent
}

extension AppModel {
    func startPrintPackageExport(
        root: URL,
        format: ExportFormat,
        options: ExportOptions,
        namingTemplate: String,
        sequenceStart: Int = 1,
        printerOutputProfile: ICCOutputProfileSnapshot?,
        composition: PrintCompositionSettings,
        package: PrintPackageSettings,
        recipeIdentity: ExportRecipeIdentity?
    ) {
        guard printerOutputProfile?.validatedColorSpace() != nil else {
            statusMessage = text(.printOutputProfileRequired)
            return
        }
        let selectedFrames = exportSelection
        guard canQuickExportSelection,
              format != .rawScanTIFF,
              composition.isValid,
              package.isValid,
              !selectedFrames.isEmpty,
              ExportNamingTemplate.isValid(namingTemplate) else { return }
        guard let pageCount = PrintPackageLayout.expectedPageCount(
            sourceCount: selectedFrames.count,
            package: package
        ) else {
            statusMessage = text(.printPackagePageLimit)
            return
        }
        guard pageCount > 0 else { return }
        var packageComposition = composition
        packageComposition.perforationStyle = .none
        let packageOptions = printPackageExportOptions(options, dpi: packageComposition.dpi)
        let date = Date()
        let firstFrame = selectedFrames[0]
        let folder = exportDestinationFolder(root: root, frame: firstFrame, date: date)
        let baseName = exportBaseName(
            for: firstFrame,
            namingTemplate: namingTemplate,
            sequence: max(1, sequenceStart),
            date: date,
            recipeIdentity: recipeIdentity
        )
        guard let artifactLayout = uniquePrintPackageArtifactLayout(
            folder: folder,
            baseName: baseName,
            pageCount: pageCount,
            format: format,
            protectedSources: selectedFrames.map(\.rawScanURL)
        ), reservePrintPackageArtifacts(artifactLayout) else { return }

        isPrintPackageExporting = true
        selectedFrames.forEach { $0.isDeveloping = true }
        statusMessage = text(AppLocalizedPhrase.exportingStatus)
        Task {
            await runPrintPackageExport(
                frames: selectedFrames,
                artifactLayout: artifactLayout,
                format: format,
                options: packageOptions,
                printerOutputProfile: printerOutputProfile,
                composition: packageComposition,
                package: package,
                recipeIdentity: recipeIdentity
            )
        }
    }

    private func runPrintPackageExport(
        frames selectedFrames: [ScanFrame],
        artifactLayout: PrintPackageArtifactLayout,
        format: ExportFormat,
        options: ExportOptions,
        printerOutputProfile: ICCOutputProfileSnapshot?,
        composition: PrintCompositionSettings,
        package: PrintPackageSettings,
        recipeIdentity: ExportRecipeIdentity?
    ) async {
        defer {
            selectedFrames.forEach { $0.isDeveloping = false }
            isPrintPackageExporting = false
            releasePrintPackageArtifacts(artifactLayout)
        }

        let verificationLevel = exportVerificationLevel
        do {
            var plans: [PrintPackageFramePlan] = []
            var sourceBaselines: [String: ExportFrameSourceVerification] = [:]
            plans.reserveCapacity(selectedFrames.count)
            for frame in selectedFrames {
                guard await prepareCleanedRawForExport(frame, format: format),
                      ownsFrame(frame),
                      !frame.isPreviewScan,
                      let layoutSize = printPackageLayoutSize(for: frame) else {
                    throw ChromabaseError.loadFailed("print package source is unavailable")
                }
                let sourceURL = frame.rawScanURL
                guard let sourceVerification = await ExportFrameSourceGeneration.capture(
                    at: sourceURL
                ) else {
                    throw ChromabaseError.loadFailed("print package source changed before snapshot")
                }
                let sourceIdentity = sourceVerification.sourceIdentity
                sourceBaselines[sourceURL.standardizedFileURL.path] = sourceVerification
                guard ownsFrame(frame),
                      !frame.isPreviewScan,
                      frame.rawScanURL.standardizedFileURL == sourceURL.standardizedFileURL else {
                    throw ChromabaseError.loadFailed("print package source changed before snapshot")
                }
                let scanSource = exportScanSourceSnapshot(for: frame)
                let build = ExportFrameSnapshotBuilder.build(
                    frame: frame,
                    sourceIdentity: sourceIdentity,
                    outputURL: artifactLayout.outputURLs[0],
                    format: format,
                    writeSidecar: false,
                    writeMainFlatMaster: false,
                    writeOriginalRaw: false,
                    options: options,
                    printComposition: nil,
                    exportRecipeIdentity: recipeIdentity,
                    scannerModel: scanSource?.device.displayName,
                    backendUsed: scanSource?.backend.type.rawValue,
                    scannerMake: scanSource?.device.vendor,
                    scannerDeviceModel: scanSource?.device.model,
                    sourceFileIdentity: sourceVerification.fileIdentity,
                    verificationLevel: verificationLevel
                )
                guard let trackingIdentity = build.trackingIdentity,
                      build.sourceGeneration.matchesCurrentState(
                        of: frame,
                        trackingIdentity: trackingIdentity,
                        format: format,
                        isOwnedByModel: ownsFrame(frame),
                        verification: sourceVerification
                      ) else {
                    throw ChromabaseError.loadFailed("print package tracking state changed")
                }
                plans.append(PrintPackageFramePlan(
                    frame: frame,
                    snapshot: build.snapshot,
                    trackingIdentity: trackingIdentity,
                    baseKey: build.baseKey,
                    layoutSize: layoutSize
                ))
            }

            let request = PrintPackageExportRequest(
                sources: plans.map { plan in
                    PrintPackageExportSource(
                        snapshot: plan.snapshot,
                        layoutSize: plan.layoutSize,
                        caption: PrintPackageCaptionFormatter.caption(
                            for: plan.frame,
                            mode: package.captionMode
                        )
                    )
                },
                composition: composition,
                package: package,
                artifactLayout: artifactLayout,
                format: format,
                options: options,
                printerOutputProfile: printerOutputProfile,
                appVersion: NegaflowProductVersion.applicationVersion()
            )
            let result = try await Task.detached(priority: .userInitiated) {
                try PrintPackageExportWriter.write(request)
            }.value

            let sourceGenerations = plans.map {
                ExportFrameSourceGeneration(snapshot: $0.snapshot)
            }
            let capturedSourceBaselines = sourceBaselines
            let artifactGenerations = Array(zip(result.outputURLs, result.outputIdentities))
            async let renderedSourceVerifications = ExportFrameSourceGeneration.currentVerifications(
                for: sourceGenerations,
                level: verificationLevel,
                baselines: capturedSourceBaselines
            )
            async let renderedArtifactsMatch: Bool = Task.detached(priority: .userInitiated) {
                artifactGenerations.allSatisfy { url, identity in
                    (try? RenderManifest.sourceIdentity(for: url)) == identity
                }
            }.value
            let renderedVerification = await (renderedSourceVerifications, renderedArtifactsMatch)
            guard renderedVerification.1,
                  renderedVerification.0.count == plans.count,
                  zip(plans, renderedVerification.0).allSatisfy({ pair in
                      let (plan, sourceVerification) = pair
                      return ExportFrameSourceGeneration(snapshot: plan.snapshot)
                          .matchesCurrentState(
                            of: plan.frame,
                            trackingIdentity: plan.trackingIdentity,
                            format: format,
                            isOwnedByModel: ownsFrame(plan.frame),
                            verification: sourceVerification
                          )
                  }), let contributors = makePrintPackageContributorCommits(
                plans: plans,
                result: result,
                format: format,
                recipeIdentity: recipeIdentity
            ) else {
                await ExportArtifactCommitJournal.cancelUncommittedAsync(
                    transactionID: result.transactionID
                )
                throw ChromabaseError.writeFailed("print package catalog commit rejected")
            }
            do {
                try await ExportArtifactCommitJournal.markCatalogCommitIntentAsync(
                    transactionID: result.transactionID
                )
            } catch {
                await ExportArtifactCommitJournal.cancelUncommittedAsync(
                    transactionID: result.transactionID
                )
                await ExportArtifactCommitJournal.cancelCatalogCommitIntentAsync(
                    transactionID: result.transactionID
                )
                throw error
            }
            let catalogSourceVerifications = await ExportFrameSourceGeneration.currentVerifications(
                for: sourceGenerations,
                level: verificationLevel,
                baselines: capturedSourceBaselines
            )
            guard catalogSourceVerifications.count == plans.count,
                  zip(plans, catalogSourceVerifications).allSatisfy({ pair in
                      let (plan, sourceVerification) = pair
                      return ExportFrameSourceGeneration(snapshot: plan.snapshot)
                          .matchesCurrentState(
                            of: plan.frame,
                            trackingIdentity: plan.trackingIdentity,
                            format: format,
                            isOwnedByModel: ownsFrame(plan.frame),
                            verification: sourceVerification
                          )
                  }) else {
                await ExportArtifactCommitJournal.cancelCatalogCommitIntentAsync(
                    transactionID: result.transactionID
                )
                throw ChromabaseError.writeFailed("print package catalog commit rejected")
            }
            var sourceVerifications: [UUID: ExportFrameSourceVerification] = [:]
            for (plan, verification) in zip(plans, catalogSourceVerifications) {
                if let verification { sourceVerifications[plan.frame.id] = verification }
            }
            guard sourceVerifications.count == plans.count else {
                await ExportArtifactCommitJournal.cancelCatalogCommitIntentAsync(
                    transactionID: result.transactionID
                )
                throw ChromabaseError.writeFailed("print package catalog commit rejected")
            }
            do {
                try await ExportArtifactCommitJournal.markCatalogCommitAttemptedAsync(
                    transactionID: result.transactionID
                )
            } catch {
                await ExportArtifactCommitJournal.cancelCatalogCommitIntentAsync(
                    transactionID: result.transactionID
                )
                throw error
            }
            let catalogCommitOutcome = commitSuccessfulPrintPackageEvents(
                contributors,
                format: format,
                sourceVerifications: sourceVerifications
            )
            switch catalogCommitOutcome {
            case .committed:
                break
            case .definitelyNotCommitted:
                await ExportArtifactCommitJournal.cancelCatalogCommitIntentAsync(
                    transactionID: result.transactionID
                )
                throw ChromabaseError.writeFailed("print package catalog commit rejected")
            case .indeterminate:
                statusMessage = libraryCatalogBlockMessage(.writeFailed)
                return
            }

            guard acknowledgeCommittedExport(transactionID: result.transactionID) else { return }
            guard await finalizeCommittedExport(transactionID: result.transactionID) else { return }
            let completedSourceVerifications = await ExportFrameSourceGeneration.currentVerifications(
                for: sourceGenerations,
                level: verificationLevel,
                baselines: capturedSourceBaselines
            )
            for (sourceIndex, base) in result.estimatedBases where plans.indices.contains(sourceIndex) {
                let plan = plans[sourceIndex]
                let sourceVerification = completedSourceVerifications.indices.contains(sourceIndex)
                    ? completedSourceVerifications[sourceIndex]
                    : nil
                ExportFilmBaseCacheCommitter.apply(
                    base,
                    baseKey: plan.baseKey,
                    to: plan.frame,
                    trackingIdentity: plan.trackingIdentity,
                    format: format,
                    sourceGeneration: sourceGenerations[sourceIndex],
                    sourceVerification: sourceVerification,
                    isOwnedByModel: ownsFrame(plan.frame)
                )
            }
            statusMessage = text(
                AppLocalizedPhrase.exportCompleteFormat,
                result.outputURLs.count == 1
                    ? result.outputURLs[0].lastPathComponent
                    : "\(result.outputURLs[0].lastPathComponent) + \(result.outputURLs.count - 1)"
            )
        } catch {
            statusMessage = text(AppLocalizedPhrase.exportFailedFormat, error.localizedDescription)
        }
    }

    func commitSuccessfulPrintPackageEvents(
        _ contributors: [PrintPackageContributorCommit],
        format: ExportFormat,
        sourceVerifications: [UUID: ExportFrameSourceVerification],
        catalogCommit: (() -> Result<Void, LibraryCatalogCommitError>)? = nil
    ) -> ExportCatalogCommitOutcome {
        guard !contributors.isEmpty,
              Set(contributors.map { $0.frame.id }).count == contributors.count,
              Set(contributors.map { $0.event.id }).count == contributors.count,
              beginAcknowledgedLibraryTransaction() else { return .definitelyNotCommitted }
        defer { endAcknowledgedLibraryTransaction() }
        guard contributors.allSatisfy({ contribution in
            contribution.sourceGeneration.matchesCurrentState(
                of: contribution.frame,
                trackingIdentity: contribution.trackingIdentity,
                format: format,
                isOwnedByModel: ownsFrame(contribution.frame),
                verification: sourceVerifications[contribution.frame.id]
            )
        }) else { return .definitelyNotCommitted }

        let previousStates = contributors.map { ($0.frame, $0.frame.libraryWorkflowTrackingState) }
        for contribution in contributors {
            var state = contribution.frame.libraryWorkflowTrackingState
                ?? .newFrame(currentRecipeSHA256: contribution.trackingIdentity.developRecipeSHA256)
            state.exportTracking.coverage = .tracked
            state.exportTracking.successfulEvents.append(contribution.event)
            contribution.frame.libraryWorkflowTrackingState = state
        }
        let commitResult = catalogCommit?() ?? commitAcknowledgedLibrarySnapshot(
            frames: frames,
            rolls: rolls,
            activeRollID: activeRollID,
            scanSessions: scanSessions,
            scanRollAssignments: scanRollAssignments
        )
        switch commitResult {
        case .success:
            acknowledgeCurrentLibraryStateMatchesCommittedSnapshot()
            return .committed
        case .failure(.rollbackFailed):
            blockLibraryAfterIndeterminateExportState()
            return .indeterminate
        case .failure:
            for (frame, previousState) in previousStates {
                frame.libraryWorkflowTrackingState = previousState
            }
            return .definitelyNotCommitted
        }
    }

    private func makePrintPackageContributorCommits(
        plans: [PrintPackageFramePlan],
        result: PrintPackageExportResult,
        format: ExportFormat,
        recipeIdentity: ExportRecipeIdentity?
    ) -> [PrintPackageContributorCommit]? {
        let contributorIndices = result.contributorPageIndices.keys.sorted()
        guard !contributorIndices.isEmpty else { return nil }
        let completedAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        var commits: [PrintPackageContributorCommit] = []
        commits.reserveCapacity(contributorIndices.count)
        for (offset, sourceIndex) in contributorIndices.enumerated() {
            guard plans.indices.contains(sourceIndex),
                  let pageIndices = result.contributorPageIndices[sourceIndex],
                  !pageIndices.isEmpty else { return nil }
            let artifactURLs = pageIndices.compactMap { pageIndex in
                result.outputURLs.indices.contains(pageIndex) ? result.outputURLs[pageIndex] : nil
            }
            guard artifactURLs.count == pageIndices.count,
                  artifactURLs.allSatisfy({ url in
                    guard let values = try? url.resourceValues(
                        forKeys: [.isRegularFileKey, .fileSizeKey]
                    ) else { return false }
                    return values.isRegularFile == true && (values.fileSize ?? 0) > 0
                  }) else { return nil }
            let plan = plans[sourceIndex]
            let event = LibraryExportEvent(
                id: offset == 0 ? result.transactionID : UUID(),
                completedAt: completedAt,
                primaryOutputPath: artifactURLs[0].standardizedFileURL.path,
                artifactPaths: artifactURLs.map { $0.standardizedFileURL.path },
                formatRawValue: format.rawValue,
                renderKind: .developed,
                developRecipeSHA256: plan.trackingIdentity.developRecipeSHA256,
                defectRecipeSHA256: plan.trackingIdentity.defectRecipeIdentity?.recipeSHA256,
                sourceIdentity: plan.snapshot.sourceIdentity,
                exportRecipePresetID: recipeIdentity?.presetID,
                exportRecipeSHA256: recipeIdentity?.configurationSHA256
            )
            commits.append(PrintPackageContributorCommit(
                frame: plan.frame,
                trackingIdentity: plan.trackingIdentity,
                sourceGeneration: ExportFrameSourceGeneration(snapshot: plan.snapshot),
                event: event
            ))
        }
        return commits
    }

    private func uniquePrintPackageArtifactLayout(
        folder: URL,
        baseName: String,
        pageCount: Int,
        format: ExportFormat,
        protectedSources: [URL]
    ) -> PrintPackageArtifactLayout? {
        for suffixIndex in 0..<100_000 {
            let stem = suffixIndex == 0 ? baseName : "\(baseName)-\(suffixIndex)"
            guard let layout = PrintPackageArtifactLayout(
                folder: folder,
                stem: stem,
                pageCount: pageCount,
                format: format
            ) else { return nil }
            if layout.isAvailable(
                protectedSources: protectedSources,
                reservedPaths: reservedExportArtifactPaths
            ) {
                return layout
            }
        }
        return nil
    }

    private func reservePrintPackageArtifacts(_ layout: PrintPackageArtifactLayout) -> Bool {
        guard layout.outputURLs.count == layout.standardizedPaths.count,
              reservedExportArtifactPaths.isDisjoint(with: layout.standardizedPaths),
              layout.outputURLs.allSatisfy({ !FileManager.default.fileExists(atPath: $0.path) }) else {
            return false
        }
        reservedExportArtifactPaths.formUnion(layout.standardizedPaths)
        return true
    }

    private func releasePrintPackageArtifacts(_ layout: PrintPackageArtifactLayout) {
        reservedExportArtifactPaths.subtract(layout.standardizedPaths)
    }

    private func printPackageLayoutSize(for frame: ScanFrame) -> CGSize? {
        if let size = frame.displayPixelSize, validPrintPackageSize(size) { return size }
        if let image = frame.developedImage ?? frame.rawPreviewImage ?? frame.thumbnailImage {
            let size = image.representations.first.map {
                CGSize(width: $0.pixelsWide, height: $0.pixelsHigh)
            } ?? image.size
            if validPrintPackageSize(size) { return size }
        }
        guard let width = frame.sourcePixelWidth,
              let height = frame.sourcePixelHeight,
              width > 0,
              height > 0 else { return nil }
        return transformedPrintPackageSize(
            CGSize(width: width, height: height),
            transform: frame.imageTransform
        )
    }

    private func transformedPrintPackageSize(
        _ sourceSize: CGSize,
        transform: ImageTransform
    ) -> CGSize? {
        var width = sourceSize.width
        var height = sourceSize.height
        if transform.rotation == .deg90 || transform.rotation == .deg270 {
            swap(&width, &height)
        }
        if abs(transform.straightenAngle) > 1e-4 {
            let radians = transform.straightenAngle * .pi / 180
            let cosine = abs(cos(radians))
            let sine = abs(sin(radians))
            let insetHeight = min(
                width * height / (width * cosine + height * sine),
                height * height / (width * sine + height * cosine)
            )
            width = width / height * insetHeight
            height = insetHeight
        }
        if let crop = transform.cropRect {
            width *= crop.z
            height *= crop.w
        }
        let result = CGSize(width: width, height: height)
        return validPrintPackageSize(result) ? result : nil
    }

    private func validPrintPackageSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}
