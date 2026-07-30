import Foundation
import Chromabase

extension AppModel {
    var exportSelection: [ScanFrame] { actionableSelectedFrames }

    var canExportSelection: Bool {
        canQuickExportSelection && ExportNamingTemplate.isValid(exportNamingTemplate)
    }

    var canQuickExportSelection: Bool {
        let selection = exportSelection
        return !selection.isEmpty
            && !exportBatchStore.isRunning
            && !isPrintPackageExporting
            && selection.allSatisfy { $0.hasDevelopedOnce && !$0.isDeveloping }
    }

    var canQuickExportPrintSelection: Bool {
        let selection = exportSelection
        return !selection.isEmpty
            && !exportBatchStore.isRunning
            && !isPrintPackageExporting
            && selection.allSatisfy { !$0.isPreviewScan && !$0.isDeveloping }
    }

    var canExportPrintSelection: Bool {
        canQuickExportPrintSelection && ExportNamingTemplate.isValid(exportNamingTemplate)
    }

    func exportSelectionToFolder() {
        guard canExportSelection else { return }
        let printerOutputProfile = selectedPrinterOutputProfile
        let mainRecipeIdentity = currentExportRecipeIdentity()
        let printRecipeIdentity = exportFormat == .rawScanTIFF
            ? nil
            : currentExportRecipeIdentity(
                outputProfileSHA256: printerOutputProfile?.profileSHA256
            )
        startExportBatch(
            root: exportFolderURL,
            format: exportFormat,
            writeSidecar: exportWriteSidecar,
            writeMainFlatMaster: exportWriteMainFlatMaster,
            writeOriginalRaw: exportWriteOriginalRaw,
            options: exportOptions,
            printerOutputProfile: printerOutputProfile,
            namingTemplate: exportNamingTemplate,
            sequenceStart: exportSequenceStart,
            recipeIdentity: mainRecipeIdentity,
            printRecipeIdentity: printRecipeIdentity
        )
    }

    func quickExportSelection() {
        guard canQuickExportSelection else { return }
        let printerOutputProfile = selectedPrinterOutputProfile
        let mainRecipeIdentity = quickExportRecipeIdentity()
        let printRecipeIdentity = quickExportFormat == .rawScanTIFF
            ? nil
            : quickExportRecipeIdentity(
                outputProfileSHA256: printerOutputProfile?.profileSHA256
            )
        startExportBatch(
            root: quickExportFolderURL,
            format: quickExportFormat,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: quickExportOptions,
            printerOutputProfile: printerOutputProfile,
            namingTemplate: ExportNamingTemplate.defaultPattern,
            recipeIdentity: mainRecipeIdentity,
            printRecipeIdentity: printRecipeIdentity
        )
    }

    func startExportBatch(
        root: URL,
        format: ExportFormat,
        writeSidecar: Bool,
        writeMainFlatMaster: Bool,
        writeOriginalRaw: Bool,
        options: ExportOptions,
        printerOutputProfile: ICCOutputProfileSnapshot? = nil,
        namingTemplate: String,
        sequenceStart: Int = 1,
        printComposition: PrintCompositionSettings? = nil,
        recipeIdentity: ExportRecipeIdentity?,
        printRecipeIdentity: ExportRecipeIdentity? = nil
    ) {
        let canStart = printComposition == nil
            ? canQuickExportSelection
            : canQuickExportPrintSelection
        guard canStart else { return }
        let requiresPrinterOutputProfile = format != .rawScanTIFF
            && exportSelection.contains { $0.params.developTarget == .print }
        guard !requiresPrinterOutputProfile
                || printerOutputProfile?.validatedColorSpace() != nil else {
            statusMessage = text(.printOutputProfileRequired)
            return
        }
        let plans = makeExportBatchPlans(
            frames: exportSelection,
            root: root,
            format: format,
            writeSidecar: writeSidecar,
            writeMainFlatMaster: writeMainFlatMaster,
            writeOriginalRaw: writeOriginalRaw,
            options: options,
            printerOutputProfile: printerOutputProfile,
            printComposition: printComposition,
            namingTemplate: namingTemplate,
            sequenceStart: sequenceStart,
            recipeIdentity: recipeIdentity,
            printRecipeIdentity: printRecipeIdentity
        )
        let previousPlans = activeExportBatchPlans
        let previousStates = Dictionary(uniqueKeysWithValues: previousPlans.compactMap { plan in
            exportBatchStore.state(for: plan.id).map { (plan.id, $0) }
        })
        activeExportBatchPlans = plans
        exportBatchStore.begin(plans)
        guard persistExportBatchCheckpoint() else {
            activeExportBatchPlans = previousPlans
            exportBatchStore.restore(previousPlans, states: previousStates)
            return
        }
        statusMessage = text(AppLocalizedPhrase.exportingStatus)
        Task { await runExportBatch(plans, maximumConcurrent: 2) }
    }

    /// 배치 전체가 쓸 원본을 미리 한 번에 내려받는다. 장마다 멈추는 대신 앞에서 한 구간으로 모은다.
    func prefetchExportBatchSources(_ plans: [ExportBatchPlan]) async -> Bool {
        await materializeExportSources(
            plans.map(\.frame.rawScanURL),
            reportsGlobalStatus: true
        )
    }

    func runExportBatch(
        _ plans: [ExportBatchPlan],
        maximumConcurrent: Int
    ) async {
        guard !plans.isEmpty else {
            exportBatchStore.finish()
            return
        }
        var checkpointPersistenceFailed = false
        guard await prefetchExportBatchSources(plans) else {
            exportBatchStore.finish()
            return
        }
        await ExportBatchScheduler.run(plans, maximumConcurrent: maximumConcurrent) { [weak self] plan in
            guard let self else { return }
            guard await exportBatchStore.awaitSchedulingPermission() else { return }
            exportBatchStore.markRunning(plan.id)
            if !persistExportBatchCheckpoint() {
                checkpointPersistenceFailed = true
            }
            let result = await runExportFrameTransaction(
                plan.frame,
                to: plan.outputURL,
                format: plan.format,
                writeSidecar: plan.writeSidecar,
                writeMainFlatMaster: plan.writeMainFlatMaster,
                writeOriginalRaw: plan.writeOriginalRaw,
                options: plan.options,
                printerOutputProfile: plan.printerOutputProfile,
                printComposition: plan.printComposition,
                recipeIdentity: plan.recipeIdentity,
                reportsGlobalStatus: false
            )
            exportBatchStore.markFinished(plan.id, result: result)
            if !persistExportBatchCheckpoint() {
                checkpointPersistenceFailed = true
            }
        }
        exportBatchStore.finish()
        if exportBatchStore.retryableItemIDs.isEmpty {
            // 재시도할 항목 없이 끝난 배치는 재개 기록을 남기지 않는다.
            discardExportBatchCheckpoint()
        } else if !persistExportBatchCheckpoint() {
            checkpointPersistenceFailed = true
        }
        guard !checkpointPersistenceFailed else { return }
        let total = exportBatchStore.items.count
        if exportBatchStore.failedCount == 0 {
            statusMessage = text(
                AppLocalizedPhrase.exportCompleteFormat,
                "\(exportBatchStore.completedCount)/\(total)"
            )
        } else {
            statusMessage = text(
                AppLocalizedPhrase.exportFailedFormat,
                "\(exportBatchStore.failedCount)/\(total)"
            )
        }
    }

    func pauseExportBatch() {
        exportBatchStore.requestPause()
        persistExportBatchCheckpoint()
    }

    func resumeExportBatch() {
        exportBatchStore.resume()
        persistExportBatchCheckpoint()
    }

    func cancelExportBatch() {
        exportBatchStore.requestCancellation()
        persistExportBatchCheckpoint()
    }

    func retryFailedExportBatchItems() {
        let ids = exportBatchStore.retryableItemIDs
        guard !ids.isEmpty else { return }
        let previousPlans = activeExportBatchPlans
        let previousStates = Dictionary(uniqueKeysWithValues: previousPlans.compactMap { plan in
            exportBatchStore.state(for: plan.id).map { (plan.id, $0) }
        })
        var plannedPaths = Set<String>()
        for plan in activeExportBatchPlans where !ids.contains(plan.id) {
            plannedPaths.formUnion(artifactLayout(for: plan).standardizedPaths)
        }
        let retryPlans = activeExportBatchPlans.filter { ids.contains($0.id) }.map { plan in
            let outputURL = recoverableBatchOutputURL(
                plan.outputURL,
                frame: plan.frame,
                format: plan.format,
                writeSidecar: plan.writeSidecar,
                writeMainFlatMaster: plan.writeMainFlatMaster,
                writeOriginalRaw: plan.writeOriginalRaw,
                excluding: plannedPaths
            )
            let refreshed = ExportBatchPlan(
                id: plan.id,
                frame: plan.frame,
                outputURL: outputURL,
                format: plan.format,
                writeSidecar: plan.writeSidecar,
                writeMainFlatMaster: plan.writeMainFlatMaster,
                writeOriginalRaw: plan.writeOriginalRaw,
                options: plan.options,
                printerOutputProfile: plan.printerOutputProfile,
                printComposition: plan.printComposition,
                recipeIdentity: plan.recipeIdentity
            )
            plannedPaths.formUnion(artifactLayout(for: refreshed).standardizedPaths)
            return refreshed
        }
        guard retryPlans.count == ids.count else { return }
        let refreshedByID = Dictionary(uniqueKeysWithValues: retryPlans.map { ($0.id, $0) })
        activeExportBatchPlans = activeExportBatchPlans.map { refreshedByID[$0.id] ?? $0 }
        exportBatchStore.prepareRetry(retryPlans)
        guard persistExportBatchCheckpoint() else {
            activeExportBatchPlans = previousPlans
            exportBatchStore.restore(previousPlans, states: previousStates)
            return
        }
        Task { await runExportBatch(retryPlans, maximumConcurrent: 2) }
    }

    private func artifactLayout(for plan: ExportBatchPlan) -> ExportArtifactLayout {
        ExportArtifactLayout(
            outputURL: plan.outputURL,
            format: plan.format,
            sourceURL: plan.frame.rawScanURL,
            writeSidecar: plan.writeSidecar,
            writeMainFlatMaster: plan.writeMainFlatMaster,
            writeOriginalRaw: plan.writeOriginalRaw
        )
    }
}
