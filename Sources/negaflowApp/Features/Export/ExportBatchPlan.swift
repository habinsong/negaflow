import Foundation
import Chromabase

@MainActor
struct ExportBatchPlan: Identifiable {
    let id: UUID
    let frame: ScanFrame
    let outputURL: URL
    let format: ExportFormat
    let writeSidecar: Bool
    let writeMainFlatMaster: Bool
    let writeOriginalRaw: Bool
    let options: ExportOptions
    let printerOutputProfile: ICCOutputProfileSnapshot?
    let printComposition: PrintCompositionSettings?
    let recipeIdentity: ExportRecipeIdentity?

    init(
        id: UUID = UUID(),
        frame: ScanFrame,
        outputURL: URL,
        format: ExportFormat,
        writeSidecar: Bool,
        writeMainFlatMaster: Bool,
        writeOriginalRaw: Bool,
        options: ExportOptions,
        printerOutputProfile: ICCOutputProfileSnapshot? = nil,
        printComposition: PrintCompositionSettings? = nil,
        recipeIdentity: ExportRecipeIdentity? = nil
    ) {
        self.id = id
        self.frame = frame
        self.outputURL = outputURL
        self.format = format
        self.writeSidecar = writeSidecar
        self.writeMainFlatMaster = writeMainFlatMaster
        self.writeOriginalRaw = writeOriginalRaw
        self.options = options
        self.printerOutputProfile = printerOutputProfile
        self.printComposition = printComposition
        self.recipeIdentity = recipeIdentity
    }
}

extension AppModel {
    func makeExportBatchPlans(
        frames: [ScanFrame],
        root: URL,
        format: ExportFormat,
        writeSidecar: Bool,
        writeMainFlatMaster: Bool,
        writeOriginalRaw: Bool,
        options: ExportOptions,
        printerOutputProfile: ICCOutputProfileSnapshot? = nil,
        printComposition: PrintCompositionSettings? = nil,
        namingTemplate: String = ExportNamingTemplate.defaultPattern,
        sequenceStart: Int = 1,
        recipeIdentity: ExportRecipeIdentity? = nil,
        printRecipeIdentity: ExportRecipeIdentity? = nil
    ) -> [ExportBatchPlan] {
        var plannedPaths = Set<String>()
        let date = Date()
        return frames.enumerated().map { offset, frame in
            let requiresPrinterOutputProfile = format != .rawScanTIFF
                && (printComposition != nil || frame.params.developTarget == .print)
            let frameRecipeIdentity = requiresPrinterOutputProfile
                ? (printRecipeIdentity ?? recipeIdentity)
                : recipeIdentity
            let folder = exportDestinationFolder(root: root, frame: frame, date: date)
            let outputURL = uniqueExportURL(
                in: folder,
                baseName: exportBaseName(
                    for: frame,
                    namingTemplate: namingTemplate,
                    sequence: max(1, sequenceStart) + offset,
                    date: date,
                    recipeIdentity: frameRecipeIdentity
                ),
                frame: frame,
                format: format,
                writeSidecar: writeSidecar,
                writeMainFlatMaster: writeMainFlatMaster,
                writeOriginalRaw: writeOriginalRaw,
                excluding: plannedPaths
            )
            let layout = ExportArtifactLayout(
                outputURL: outputURL,
                format: format,
                sourceURL: frame.rawScanURL,
                writeSidecar: writeSidecar,
                writeMainFlatMaster: writeMainFlatMaster,
                writeOriginalRaw: writeOriginalRaw
            )
            plannedPaths.formUnion(layout.standardizedPaths)
            return ExportBatchPlan(
                frame: frame,
                outputURL: outputURL,
                format: format,
                writeSidecar: writeSidecar,
                writeMainFlatMaster: writeMainFlatMaster,
                writeOriginalRaw: writeOriginalRaw,
                options: options,
                printerOutputProfile: printerOutputProfile,
                printComposition: printComposition,
                recipeIdentity: frameRecipeIdentity
            )
        }
    }
}
