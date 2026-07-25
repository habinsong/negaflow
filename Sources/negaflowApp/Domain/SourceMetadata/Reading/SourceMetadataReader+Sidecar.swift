import CryptoKit
import Foundation
import ImageIO

extension SourceMetadataReader {
    static func readSidecarXMP(
        for sourceURL: URL,
        fileManager: FileManager,
        bounds: inout MetadataBounds
    ) -> (
        state: SourceXMPReadState,
        metadata: SourceXMPMetadata?,
        containsStandardGPSMetadata: Bool,
        sha256: String?
    ) {
        let candidates = sidecarCandidates(for: sourceURL, fileManager: fileManager)
        guard !candidates.isEmpty else { return (.notFound, nil, false, nil) }
        let distinctCandidates = distinctFiles(candidates)
        guard distinctCandidates.count == 1 else { return (.ambiguous, nil, false, nil) }
        let sidecarURL = distinctCandidates[0]
        guard let values = try? sidecarURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey,
        ]),
        values.isRegularFile == true,
        let byteCount = values.fileSize,
        byteCount > 0 else {
            return (.invalid, nil, false, nil)
        }
        guard Int64(byteCount) <= maximumSidecarBytes else {
            return (.tooLarge, nil, false, nil)
        }
        guard let data = try? Data(contentsOf: sidecarURL, options: [.mappedIfSafe]) else {
            return (.invalid, nil, false, nil)
        }
        guard Int64(data.count) <= maximumSidecarBytes else {
            return (.tooLarge, nil, false, nil)
        }
        let digest = sha256(data)
        guard let metadata = CGImageMetadataCreateFromXMPData(data as CFData) else {
            return (.invalid, nil, false, digest)
        }
        let alternateTextResult = XMPAlternateTextReader.read(from: data)
        if alternateTextResult.hadInvalidValues {
            bounds.discardedInvalidValues = true
        }
        let xmp = readXMP(
            metadata,
            alternateTexts: alternateTextResult.valuesByPath,
            bounds: &bounds
        )
        return (
            .loaded,
            xmp.metadata.isEmpty ? nil : xmp.metadata,
            xmp.containsStandardGPSMetadata,
            digest
        )
    }

    static func sidecarCandidates(
        for sourceURL: URL,
        fileManager: FileManager
    ) -> [URL] {
        let directory = sourceURL.deletingLastPathComponent()
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let volumeValues = try? directory.resourceValues(forKeys: [
            .volumeSupportsCaseSensitiveNamesKey,
        ])
        let usesCaseSensitiveNames = volumeValues?.volumeSupportsCaseSensitiveNames ?? true
        if let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileResourceIdentifierKey],
            options: []
        ) {
            return contents.filter { candidate in
                let candidateStem = candidate.deletingPathExtension().lastPathComponent
                let stemMatches = usesCaseSensitiveNames
                    ? candidateStem == stem
                    : candidateStem.caseInsensitiveCompare(stem) == .orderedSame
                return candidate.pathExtension.caseInsensitiveCompare("xmp") == .orderedSame
                    && stemMatches
            }
        }
        return ["xmp", "XMP"].compactMap { pathExtension in
            let candidate = sourceURL.deletingPathExtension()
                .appendingPathExtension(pathExtension)
            return fileManager.fileExists(atPath: candidate.path) ? candidate : nil
        }
    }

    static func distinctFiles(_ urls: [URL]) -> [URL] {
        var resourceIdentifiers = Set<AnyHashable>()
        var fallbackPaths = Set<String>()
        var result: [URL] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey])
            if let identifier = values?.fileResourceIdentifier as? AnyHashable {
                if resourceIdentifiers.insert(identifier).inserted { result.append(url) }
            } else {
                let path = url.resolvingSymlinksInPath().standardizedFileURL.path
                if fallbackPaths.insert(path).inserted { result.append(url) }
            }
        }
        return result
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }


}
