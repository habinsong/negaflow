import Foundation

struct LibraryArchivePayloadCollector {
    let stagingURL: URL
    let fileManager: FileManager
    private(set) var payloads: [LibraryArchivePayload] = []
    private var sourcePayloadIDs: [String: String] = [:]
    private var roleCounts: [LibraryArchivePayloadRole: Int] = [:]

    init(stagingURL: URL, fileManager: FileManager) {
        self.stagingURL = stagingURL
        self.fileManager = fileManager
    }

    mutating func addCatalog(_ data: Data) throws {
        let relativePath = "data/catalog/library.json"
        let destination = stagingURL.appendingPathComponent(relativePath)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
        let digest = try LibraryArchiveFileIO.hash(destination)
        payloads.append(LibraryArchivePayload(
            id: "catalog",
            role: .catalog,
            relativePath: relativePath,
            originalFileName: "library.json",
            byteCount: digest.byteCount,
            sha256: digest.sha256
        ))
    }

    mutating func addSource(
        at sourcePath: String,
        role: LibraryArchivePayloadRole
    ) throws -> String {
        let source = URL(fileURLWithPath: sourcePath).resolvingSymlinksInPath()
        guard fileManager.fileExists(atPath: source.path) else {
            throw LibraryArchiveError.missingSource(sourcePath)
        }
        let key = "\(role.rawValue):\(source.standardizedFileURL.path)"
        if let existing = sourcePayloadIDs[key] { return existing }

        let count = (roleCounts[role] ?? 0) + 1
        roleCounts[role] = count
        let prefix = role == .original ? "original" : "infrared"
        let id = String(format: "%@-%06d", prefix, count)
        let relativePath = "data/\(prefix)/\(id)\(safeExtension(source))"
        let destination = stagingURL.appendingPathComponent(relativePath)
        let digest = try LibraryArchiveFileIO.copyAndHash(
            from: source,
            to: destination,
            fileManager: fileManager
        )
        payloads.append(LibraryArchivePayload(
            id: id,
            role: role,
            relativePath: relativePath,
            originalFileName: source.lastPathComponent,
            byteCount: digest.byteCount,
            sha256: digest.sha256
        ))
        sourcePayloadIDs[key] = id
        return id
    }

    mutating func addDefectRecipe(
        for frameID: UUID,
        from defectDirectory: URL
    ) throws -> String {
        guard let data = DefectSidecarFile.validatedRawData(
            for: frameID,
            in: defectDirectory
        ) else {
            throw LibraryArchiveError.missingDefectRecipe(frameID)
        }
        let id = "defect-\(frameID.uuidString.lowercased())"
        let relativePath = "data/defects/\(frameID.uuidString).plist"
        let destination = stagingURL.appendingPathComponent(relativePath)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
        let digest = try LibraryArchiveFileIO.hash(destination)
        payloads.append(LibraryArchivePayload(
            id: id,
            role: .defectRecipe,
            relativePath: relativePath,
            originalFileName: "\(frameID.uuidString).plist",
            byteCount: digest.byteCount,
            sha256: digest.sha256
        ))
        return id
    }

    private func safeExtension(_ url: URL) -> String {
        let value = url.pathExtension.lowercased()
        guard !value.isEmpty,
              value.count <= 16,
              value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            return String()
        }
        return String(format: ".%@", value)
    }
}
