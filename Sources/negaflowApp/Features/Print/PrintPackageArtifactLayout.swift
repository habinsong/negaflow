import Chromabase
import Foundation

struct PrintPackageArtifactLayout: Equatable, Sendable {
    let outputURLs: [URL]

    init?(folder: URL, stem: String, pageCount: Int, format: ExportFormat) {
        guard !stem.isEmpty,
              (1...PrintPackageSettings.maximumPageCount).contains(pageCount) else { return nil }
        outputURLs = (0..<pageCount).map { pageIndex in
            folder.appendingPathComponent(
                "\(stem)-page-\(String(format: "%03d", pageIndex + 1)).\(format.fileExtension)"
            )
        }
    }

    var standardizedPaths: Set<String> {
        Set(outputURLs.map { $0.standardizedFileURL.path })
    }

    func staged(in directory: URL) -> [URL] {
        outputURLs.map { directory.appendingPathComponent($0.lastPathComponent) }
    }

    func isAvailable(
        protectedSources: [URL],
        reservedPaths: Set<String>,
        fileManager: FileManager = .default
    ) -> Bool {
        guard outputURLs.count == standardizedPaths.count,
              reservedPaths.isDisjoint(with: standardizedPaths),
              outputURLs.allSatisfy({ !fileManager.fileExists(atPath: $0.path) }),
              (try? ExportDestinationSafety.validateDistinct(
                protectedSources: protectedSources,
                outputURLs: outputURLs,
                fileManager: fileManager
              )) != nil else { return false }
        return true
    }
}
