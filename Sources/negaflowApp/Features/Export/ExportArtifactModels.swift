import Foundation
import Chromabase

struct ExportArtifactLayout: Equatable, Sendable {
    let outputURL: URL
    let mainFlatMasterURL: URL?
    let originalRawURL: URL?
    let sidecarURL: URL?
    let xmpURL: URL?

    init(
        outputURL: URL,
        format: ExportFormat,
        sourceURL: URL,
        writeSidecar: Bool,
        writeMainFlatMaster: Bool,
        writeOriginalRaw: Bool
    ) {
        self.outputURL = outputURL
        self.mainFlatMasterURL = writeMainFlatMaster && format != .rawScanTIFF
            ? ExportPairing.mainFlatMasterURL(for: outputURL)
            : nil
        if writeOriginalRaw && format != .rawScanTIFF {
            let sourceExtension = sourceURL.pathExtension.isEmpty ? "tiff" : sourceURL.pathExtension
            self.originalRawURL = ExportPairing.originalRawURL(
                for: outputURL,
                sourceExtension: sourceExtension
            )
        } else {
            self.originalRawURL = nil
        }
        self.sidecarURL = writeSidecar
            ? outputURL.deletingPathExtension().appendingPathExtension("negaflow.json")
            : nil
        self.xmpURL = writeSidecar
            ? outputURL.deletingPathExtension().appendingPathExtension("xmp")
            : nil
    }

    var allURLs: [URL] {
        [outputURL, mainFlatMasterURL, originalRawURL, sidecarURL, xmpURL].compactMap { $0 }
    }

    var standardizedPaths: Set<String> {
        Set(allURLs.map { $0.standardizedFileURL.path })
    }

    func staged(in directory: URL) -> ExportArtifactLayout {
        func stagedURL(_ url: URL?) -> URL? {
            url.map { directory.appendingPathComponent($0.lastPathComponent) }
        }
        return ExportArtifactLayout(
            outputURL: directory.appendingPathComponent(outputURL.lastPathComponent),
            mainFlatMasterURL: stagedURL(mainFlatMasterURL),
            originalRawURL: stagedURL(originalRawURL),
            sidecarURL: stagedURL(sidecarURL),
            xmpURL: stagedURL(xmpURL)
        )
    }

    private init(
        outputURL: URL,
        mainFlatMasterURL: URL?,
        originalRawURL: URL?,
        sidecarURL: URL?,
        xmpURL: URL?
    ) {
        self.outputURL = outputURL
        self.mainFlatMasterURL = mainFlatMasterURL
        self.originalRawURL = originalRawURL
        self.sidecarURL = sidecarURL
        self.xmpURL = xmpURL
    }
}
