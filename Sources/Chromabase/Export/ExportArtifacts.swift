import Foundation

public struct ExportWriteResult: Sendable, Equatable {
    public let outputURL: URL
    public let mainFlatMasterURL: URL?

    public init(outputURL: URL, mainFlatMasterURL: URL? = nil) {
        self.outputURL = outputURL
        self.mainFlatMasterURL = mainFlatMasterURL
    }
}

public enum ExportPairing {
    public static let mainFlatSuffix = "main-flat"
    public static let originalRawSuffix = "original"

    public static func mainFlatMasterURL(for outputURL: URL) -> URL {
        let ext = outputURL.pathExtension
        let base = outputURL.deletingPathExtension()
        let sibling = base
            .deletingLastPathComponent()
            .appendingPathComponent("\(base.lastPathComponent)-\(mainFlatSuffix)")
        guard !ext.isEmpty else { return sibling }
        return sibling.appendingPathExtension(ext)
    }

    public static func originalRawURL(for outputURL: URL, sourceExtension: String = "tiff") -> URL {
        let base = outputURL.deletingPathExtension()
        let sibling = base
            .deletingLastPathComponent()
            .appendingPathComponent("\(base.lastPathComponent)-\(originalRawSuffix)")
        let ext = sourceExtension.isEmpty ? "tiff" : sourceExtension
        return sibling.appendingPathExtension(ext)
    }
}

/// 출력 경로가 원본 또는 다른 출력과 같은 파일을 가리키는지, 경로와 기존 파일 identity로 검사한다.
public enum ExportDestinationSafety {
    public static func validateDistinct(
        protectedSources: [URL],
        outputURLs: [URL],
        fileManager: FileManager = .default
    ) throws {
        for output in outputURLs {
            for source in protectedSources where referencesSameFile(source, output, fileManager: fileManager) {
                throw ChromabaseError.writeFailed("output conflicts with source: \(output.path)")
            }
        }
        for index in outputURLs.indices {
            for otherIndex in outputURLs.indices where otherIndex > index {
                if referencesSameFile(
                    outputURLs[index],
                    outputURLs[otherIndex],
                    fileManager: fileManager
                ) {
                    throw ChromabaseError.writeFailed(
                        "output paths overlap: \(outputURLs[otherIndex].path)"
                    )
                }
            }
        }
    }

    public static func referencesSameFile(
        _ lhs: URL,
        _ rhs: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let left = lhs.resolvingSymlinksInPath().standardizedFileURL
        let right = rhs.resolvingSymlinksInPath().standardizedFileURL
        if left.path == right.path { return true }
        guard fileManager.fileExists(atPath: left.path),
              fileManager.fileExists(atPath: right.path),
              let leftID = try? left.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
              let rightID = try? right.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
              let leftHashable = leftID as? AnyHashable,
              let rightHashable = rightID as? AnyHashable else {
            return false
        }
        return leftHashable == rightHashable
    }
}

/// 출력 파일에 들어갈 EXIF/TIFF 메타데이터.
public struct ExportMeta: Sendable {
    public var scannerMake: String?
    public var scannerModel: String?
    public var resolutionDPI: Int?
    public var filmType: String?
    public var software: String?
    public var sourceDate: Date?
    public var metadataDate: Date?
    public var sourceMetadata: ExportSourceMetadata?
    public var metadataPolicy: ExportMetadataPolicy

    public init(scannerMake: String? = nil, scannerModel: String? = nil, resolutionDPI: Int? = nil,
                filmType: String? = nil, software: String? = nil,
                sourceDate: Date? = nil, metadataDate: Date? = Date(),
                sourceMetadata: ExportSourceMetadata? = nil,
                metadataPolicy: ExportMetadataPolicy = .minimal) {
        self.scannerMake = scannerMake
        self.scannerModel = scannerModel
        self.resolutionDPI = resolutionDPI
        self.filmType = filmType
        self.software = software
        self.sourceDate = sourceDate
        self.metadataDate = metadataDate
        self.sourceMetadata = sourceMetadata
        self.metadataPolicy = metadataPolicy
    }
}

public extension DevelopParameters {
    func mainFlatMasterParameters() -> DevelopParameters {
        var master = DevelopParameters()
        master.filmType = filmType
        master.developTarget = .main
        master.baseEstimationMode = baseEstimationMode
        master.manualBaseRGB = manualBaseRGB
        master.filmStockDminID = filmStockDminID
        master.lightSourceProfileID = lightSourceProfileID
        master.imageTransform = imageTransform
        return master
    }
}
