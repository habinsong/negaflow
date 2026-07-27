import Foundation
import Chromabase

extension AppModel {
    var exportBatchCheckpointURL: URL {
        ExportBatchCheckpoint.url(for: libraryCatalogURL)
    }

    @discardableResult
    func persistExportBatchCheckpoint() -> Bool {
        guard !activeExportBatchPlans.isEmpty else { return true }
        let checkpoint = ExportBatchCheckpoint(
            plans: activeExportBatchPlans,
            store: exportBatchStore
        )
        let activeIDs = Set(activeExportBatchPlans.map(\.id))
        guard checkpoint.items.count == activeExportBatchPlans.count,
              Set(checkpoint.items.map(\.id)) == activeIDs else {
            reportExportBatchCheckpointFailure("checkpoint-state")
            return false
        }
        do {
            try checkpoint.write(to: exportBatchCheckpointURL)
            return true
        } catch {
            reportExportBatchCheckpointFailure("checkpoint-save")
            return false
        }
    }

    // 체크포인트는 중단된 배치를 재개하기 위한 기록이다. 재개할 항목이 없는데도 파일을
    // 남기면, 프레임이 라이브러리에서 사라진 뒤부터 매 실행마다 복원 불가를 보고한다.
    func discardExportBatchCheckpoint() {
        try? FileManager.default.removeItem(at: exportBatchCheckpointURL)
    }

    func restoreExportBatchCheckpoint() {
        let checkpoint: ExportBatchCheckpoint
        do {
            checkpoint = try ExportBatchCheckpoint.read(from: exportBatchCheckpointURL)
        } catch ExportBatchCheckpoint.LoadError.fileNotFound {
            return
        } catch let error as ExportBatchCheckpoint.LoadError {
            reportExportBatchCheckpointFailure(checkpointFailureCode(for: error))
            return
        } catch {
            reportExportBatchCheckpointFailure("checkpoint-read")
            return
        }
        guard checkpoint.items.contains(where: { $0.state != .succeeded }) else {
            // 전부 성공한 배치는 재개할 것도 재시도할 것도 없다. 실패가 아니므로 조용히 지운다.
            discardExportBatchCheckpoint()
            return
        }
        let framesByID = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0) })
        var plannedPaths = Set<String>()
        var plans: [ExportBatchPlan] = []
        var states: [UUID: ExportBatchStore.State] = [:]
        let printerOutputProfiles = Dictionary(
            uniqueKeysWithValues: (checkpoint.printerOutputProfiles ?? []).compactMap { stored in
                stored.resolved.map { (stored.profileSHA256, $0) }
            }
        )

        for item in checkpoint.items {
            let compression = item.tiffCompression.flatMap(ExportTIFFCompression.init(rawValue:))
            let bitDepth = item.tiffBitDepth.flatMap(ExportTIFFBitDepth.init(rawValue:))
            let metadataPolicy = item.metadataPolicy.flatMap(ExportMetadataPolicy.init(rawValue:))
            let sharpeningMedium = item.outputSharpeningMedium.flatMap(
                OutputSharpeningMedium.init(rawValue:)
            )
            let hasRestorablePrinterOutputProfile = item.printerOutputProfileSHA256.map {
                printerOutputProfiles[$0] != nil
            } ?? true
            guard let frame = framesByID[item.frameID],
                  !frame.isPreviewScan,
                  let format = ExportFormat(rawValue: item.format),
                  let colorSpace = ExportColorSpace(rawValue: item.colorSpace),
                  item.outputPath.hasPrefix("/"),
                  item.dpi >= 0,
                  item.tiffCompression == nil || compression != nil,
                  item.tiffBitDepth == nil || bitDepth != nil,
                  item.metadataPolicy == nil || metadataPolicy != nil,
                  item.outputSharpeningMedium == nil || sharpeningMedium != nil,
                  hasRestorablePrinterOutputProfile,
                  item.longEdge.map({ $0 > 0 }) ?? true else {
                continue
            }
            let options = ExportOptions(
                colorSpace: colorSpace,
                dpi: item.dpi,
                longEdge: item.longEdge,
                jpegQuality: item.jpegQuality ?? 0.95,
                tiffCompression: compression ?? .none,
                tiffBitDepth: bitDepth ?? .sixteen,
                preserveAlpha: item.preserveAlpha ?? false,
                metadataPolicy: metadataPolicy ?? .minimal,
                outputSharpening: item.outputSharpening ?? 0,
                outputSharpeningMedium: sharpeningMedium ?? .screen
            )
            guard (try? options.validate(for: format)) != nil else { continue }
            let requiresPrinterOutputProfile = format != .rawScanTIFF
                && (item.printComposition != nil || frame.params.developTarget == .print)
            guard !requiresPrinterOutputProfile
                    || item.printerOutputProfileSHA256.flatMap({
                        printerOutputProfiles[$0]
                    }) != nil else {
                continue
            }
            let requestedURL = URL(fileURLWithPath: item.outputPath)
            // Catalog event + complete artifact set is the authoritative commit record. The
            // checkpoint can still say `running` if the process stopped after catalog commit but
            // before the next checkpoint write; treating that window as cancelled duplicates output.
            let committed = exportEventWasCommitted(frame: frame, outputURL: requestedURL)
            let outputURL = committed
                ? requestedURL
                : recoverableBatchOutputURL(
                    requestedURL,
                    frame: frame,
                    format: format,
                    writeSidecar: item.writeSidecar,
                    writeMainFlatMaster: item.writeMainFlatMaster,
                    writeOriginalRaw: item.writeOriginalRaw,
                    excluding: plannedPaths
                )
            let plan = ExportBatchPlan(
                id: item.id,
                frame: frame,
                outputURL: outputURL,
                format: format,
                writeSidecar: item.writeSidecar,
                writeMainFlatMaster: item.writeMainFlatMaster,
                writeOriginalRaw: item.writeOriginalRaw,
                options: options,
                printerOutputProfile: item.printerOutputProfileSHA256.flatMap {
                    printerOutputProfiles[$0]
                },
                printComposition: item.printComposition,
                recipeIdentity: item.recipeSHA256.map {
                    ExportRecipeIdentity(
                        presetID: item.recipePresetID,
                        presetName: item.recipePresetName,
                        configurationSHA256: $0
                    )
                }
            )
            let layout = ExportArtifactLayout(
                outputURL: outputURL,
                format: format,
                sourceURL: frame.rawScanURL,
                writeSidecar: item.writeSidecar,
                writeMainFlatMaster: item.writeMainFlatMaster,
                writeOriginalRaw: item.writeOriginalRaw
            )
            guard plannedPaths.isDisjoint(with: layout.standardizedPaths) else { continue }
            plannedPaths.formUnion(layout.standardizedPaths)
            plans.append(plan)
            states[item.id] = committed ? .succeeded : .cancelled
        }

        guard !plans.isEmpty, plans.count == checkpoint.items.count else {
            reportExportBatchCheckpointFailure("checkpoint-unrestorable")
            return
        }
        activeExportBatchPlans = plans
        exportBatchStore.restore(plans, states: states)
        persistExportBatchCheckpoint()
    }

    private func checkpointFailureCode(
        for error: ExportBatchCheckpoint.LoadError
    ) -> String {
        switch error {
        case .fileNotFound:
            "checkpoint-missing"
        case .permissionDenied:
            "checkpoint-permission"
        case .readFailed:
            "checkpoint-read"
        case .decodingFailed:
            "checkpoint-decode"
        case .validationFailed:
            "checkpoint-invalid"
        }
    }

    private func reportExportBatchCheckpointFailure(_ code: String) {
        statusMessage = text(AppLocalizedPhrase.exportFailedFormat, code)
    }

    private func exportEventWasCommitted(frame: ScanFrame, outputURL: URL) -> Bool {
        let path = outputURL.standardizedFileURL.path
        return FileManager.default.fileExists(atPath: path)
            && (frame.libraryWorkflowTrackingState?.exportTracking.successfulEvents.contains {
                $0.primaryOutputPath == path && $0.artifactPaths.allSatisfy {
                    FileManager.default.fileExists(atPath: $0)
                }
            } ?? false)
    }

    func recoverableBatchOutputURL(
        _ requestedURL: URL,
        frame: ScanFrame,
        format: ExportFormat,
        writeSidecar: Bool,
        writeMainFlatMaster: Bool,
        writeOriginalRaw: Bool,
        excluding plannedPaths: Set<String>
    ) -> URL {
        let layout = ExportArtifactLayout(
            outputURL: requestedURL,
            format: format,
            sourceURL: frame.rawScanURL,
            writeSidecar: writeSidecar,
            writeMainFlatMaster: writeMainFlatMaster,
            writeOriginalRaw: writeOriginalRaw
        )
        if exportArtifactsAreAvailable(layout, excluding: plannedPaths) {
            return requestedURL
        }
        return uniqueExportURL(
            in: requestedURL.deletingLastPathComponent(),
            baseName: requestedURL.deletingPathExtension().lastPathComponent,
            frame: frame,
            format: format,
            writeSidecar: writeSidecar,
            writeMainFlatMaster: writeMainFlatMaster,
            writeOriginalRaw: writeOriginalRaw,
            excluding: plannedPaths
        )
    }
}
