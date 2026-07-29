import Foundation
import Chromabase

enum ExportFrameTransactionResult: Equatable {
    case completed(outputURL: URL, pairedURLs: [URL])
    case failed(message: String)
}

extension AppModel {
    func runExportFrameTransaction(
        _ frame: ScanFrame,
        to url: URL,
        format: ExportFormat,
        writeSidecar: Bool,
        writeMainFlatMaster: Bool,
        writeOriginalRaw: Bool,
        options: ExportOptions,
        printerOutputProfile: ICCOutputProfileSnapshot? = nil,
        printComposition: PrintCompositionSettings? = nil,
        recipeIdentity: ExportRecipeIdentity?,
        reportsGlobalStatus: Bool
    ) async -> ExportFrameTransactionResult {
        let trace = AppDiagnostics.start(.exportFrame, category: .export)
        defer { trace.finish() }
        let layout = ExportArtifactLayout(
            outputURL: url,
            format: format,
            sourceURL: frame.rawScanURL,
            writeSidecar: writeSidecar,
            writeMainFlatMaster: writeMainFlatMaster,
            writeOriginalRaw: writeOriginalRaw
        )
        guard reserveExportArtifacts(layout) else {
            frame.isDeveloping = false
            trace.fail(code: "destination_conflict")
            return failExport(
                text(AppLocalizedPhrase.exportDestinationConflict),
                reportsGlobalStatus: reportsGlobalStatus
            )
        }

        frame.isDeveloping = true
        if reportsGlobalStatus {
            statusMessage = text(AppLocalizedPhrase.exportingStatus)
        }
        defer {
            frame.isDeveloping = false
            releaseExportArtifacts(layout)
        }

        // 원본이 iCloud 에서 축출됐다면 여기서 받아둔다 — 그러지 않으면 첫 읽기에서 아무 표시 없이
        // 다운로드가 끝날 때까지 멈춘다.
        guard await materializeExportSources(
            [frame.rawScanURL],
            reportsGlobalStatus: reportsGlobalStatus
        ) else {
            trace.fail(code: "source_download_failed")
            return failExport(
                text(AppLocalizedPhrase.exportSourceDownloadFailed),
                reportsGlobalStatus: false
            )
        }
        guard await prepareCleanedRawForExport(frame, format: format) else {
            trace.fail(code: "defect_recipe_unavailable")
            return failExport(
                text(AppLocalizedPhrase.removingDefectsFailedStatus),
                reportsGlobalStatus: reportsGlobalStatus
            )
        }
        guard ownsFrame(frame), !frame.isPreviewScan else {
            trace.fail(code: "frame_not_exportable")
            return failExport(
                text(AppLocalizedPhrase.libraryCatalogBlockedStatus),
                reportsGlobalStatus: reportsGlobalStatus
            )
        }

        let verificationLevel = exportVerificationLevel
        do {
            let sourceURL = frame.rawScanURL
            guard let sourceVerification = await ExportFrameSourceGeneration.capture(
                at: sourceURL
            ) else {
                throw ChromabaseError.loadFailed("export source changed before snapshot")
            }
            let sourceIdentity = sourceVerification.sourceIdentity
            // 이 세대를 고정한 stat identity. 이후 재확인은 이걸 기준으로 한다(standard).
            let sourceBaselines = [
                sourceURL.standardizedFileURL.path: sourceVerification,
            ]
            guard ownsFrame(frame), !frame.isPreviewScan,
                  frame.rawScanURL.standardizedFileURL == sourceURL.standardizedFileURL else {
                throw ChromabaseError.loadFailed("export source changed before snapshot")
            }

            let scanSource = exportScanSourceSnapshot(for: frame)
            let plan = ExportFrameSnapshotBuilder.build(
                frame: frame,
                sourceIdentity: sourceIdentity,
                outputURL: url,
                format: format,
                writeSidecar: writeSidecar,
                writeMainFlatMaster: writeMainFlatMaster,
                writeOriginalRaw: writeOriginalRaw,
                options: options,
                printerOutputProfile: printerOutputProfile,
                printComposition: printComposition,
                exportRecipeIdentity: recipeIdentity,
                scannerModel: scanSource?.device.displayName,
                backendUsed: scanSource?.backend.type.rawValue,
                scannerMake: scanSource?.device.vendor,
                scannerDeviceModel: scanSource?.device.model,
                sourceFileIdentity: sourceVerification.fileIdentity,
                verificationLevel: verificationLevel
            )
            guard let trackingIdentity = plan.trackingIdentity,
                  plan.sourceGeneration.matchesCurrentState(
                    of: frame,
                    trackingIdentity: trackingIdentity,
                    format: format,
                    isOwnedByModel: ownsFrame(frame),
                    verification: sourceVerification
                  ) else {
                throw ChromabaseError.loadFailed("export tracking state changed")
            }

            let result = try await Task.detached(priority: .userInitiated) {
                try ExportFrameWriter.write(plan.snapshot)
            }.value
            let renderedSourceVerification = await ExportFrameSourceGeneration.currentVerifications(
                for: [plan.sourceGeneration],
                level: verificationLevel,
                baselines: sourceBaselines
            ).first ?? nil
            guard plan.sourceGeneration.matchesCurrentState(
                of: frame,
                trackingIdentity: trackingIdentity,
                format: format,
                isOwnedByModel: ownsFrame(frame),
                verification: renderedSourceVerification
            ), let event = ExportTrackingEventFactory.makeEvent(
                trackingIdentity: trackingIdentity,
                sourceIdentity: plan.snapshot.sourceIdentity,
                result: result,
                expectedLayout: layout,
                format: format,
                exportRecipeIdentity: recipeIdentity
            ) else {
                await ExportArtifactCommitJournal.cancelUncommittedAsync(
                    transactionID: result.commitTransactionID
                )
                trace.fail(code: "catalog_commit_rejected")
                return failExport(
                    text(AppLocalizedPhrase.libraryCatalogBlockedStatus),
                    reportsGlobalStatus: reportsGlobalStatus
                )
            }
            do {
                try await ExportArtifactCommitJournal.markCatalogCommitIntentAsync(
                    transactionID: result.commitTransactionID
                )
            } catch {
                await ExportArtifactCommitJournal.cancelUncommittedAsync(
                    transactionID: result.commitTransactionID
                )
                await ExportArtifactCommitJournal.cancelCatalogCommitIntentAsync(
                    transactionID: result.commitTransactionID
                )
                throw error
            }
            let catalogSourceVerification = await ExportFrameSourceGeneration.currentVerifications(
                for: [plan.sourceGeneration],
                level: verificationLevel,
                baselines: sourceBaselines
            ).first ?? nil
            guard plan.sourceGeneration.matchesCurrentState(
                of: frame,
                trackingIdentity: trackingIdentity,
                format: format,
                isOwnedByModel: ownsFrame(frame),
                verification: catalogSourceVerification
            ) else {
                await ExportArtifactCommitJournal.cancelCatalogCommitIntentAsync(
                    transactionID: result.commitTransactionID
                )
                trace.fail(code: "catalog_commit_rejected")
                return failExport(
                    text(AppLocalizedPhrase.libraryCatalogBlockedStatus),
                    reportsGlobalStatus: reportsGlobalStatus
                )
            }
            do {
                try await ExportArtifactCommitJournal.markCatalogCommitAttemptedAsync(
                    transactionID: result.commitTransactionID
                )
            } catch {
                await ExportArtifactCommitJournal.cancelCatalogCommitIntentAsync(
                    transactionID: result.commitTransactionID
                )
                throw error
            }
            let catalogCommitOutcome = commitSuccessfulExportEvent(
                event,
                for: frame,
                trackingIdentity: trackingIdentity,
                format: format,
                sourceGeneration: plan.sourceGeneration,
                sourceVerification: catalogSourceVerification
            )
            switch catalogCommitOutcome {
            case .committed:
                break
            case .definitelyNotCommitted:
                await ExportArtifactCommitJournal.cancelCatalogCommitIntentAsync(
                    transactionID: result.commitTransactionID
                )
                trace.fail(code: "catalog_commit_rejected")
                return failExport(
                    text(AppLocalizedPhrase.libraryCatalogBlockedStatus),
                    reportsGlobalStatus: reportsGlobalStatus
                )
            case .indeterminate:
                trace.fail(code: "catalog_commit_indeterminate")
                return failExport(
                    text(AppLocalizedPhrase.libraryCatalogBlockedStatus),
                    reportsGlobalStatus: reportsGlobalStatus
                )
            }

            guard acknowledgeCommittedExport(
                transactionID: result.commitTransactionID
            ) else {
                trace.fail(code: "catalog_commit_acknowledgement_failed")
                return .failed(message: text(AppLocalizedPhrase.libraryCatalogBlockedStatus))
            }
            guard await finalizeCommittedExport(
                transactionID: result.commitTransactionID
            ) else {
                trace.fail(code: "committed_export_finalization_failed")
                return .failed(message: text(AppLocalizedPhrase.libraryCatalogBlockedStatus))
            }
            let completedSourceVerification = await ExportFrameSourceGeneration.currentVerifications(
                for: [plan.sourceGeneration],
                level: verificationLevel,
                baselines: sourceBaselines
            ).first ?? nil
            if let base = result.base {
                ExportFilmBaseCacheCommitter.apply(
                    base,
                    baseKey: plan.baseKey,
                    to: frame,
                    trackingIdentity: trackingIdentity,
                    format: format,
                    sourceGeneration: plan.sourceGeneration,
                    sourceVerification: completedSourceVerification,
                    isOwnedByModel: ownsFrame(frame)
                )
            }
            let pairedURLs = [result.mainFlatMasterURL, result.originalRawURL].compactMap { $0 }
            if reportsGlobalStatus {
                let names = pairedURLs.map(\.lastPathComponent)
                statusMessage = names.isEmpty
                    ? text(AppLocalizedPhrase.exportCompleteFormat, url.lastPathComponent)
                    : text(
                        AppLocalizedPhrase.exportCompleteWithPairsFormat,
                        ([url.lastPathComponent] + names).joined(separator: " + ")
                    )
            }
            trace.finish()
            return .completed(outputURL: url, pairedURLs: pairedURLs)
        } catch {
            trace.fail(error)
            return failExport(error.localizedDescription, reportsGlobalStatus: reportsGlobalStatus)
        }
    }

    private func failExport(
        _ message: String,
        reportsGlobalStatus: Bool
    ) -> ExportFrameTransactionResult {
        if reportsGlobalStatus {
            statusMessage = text(AppLocalizedPhrase.exportFailedFormat, message)
        }
        return .failed(message: message)
    }
}
