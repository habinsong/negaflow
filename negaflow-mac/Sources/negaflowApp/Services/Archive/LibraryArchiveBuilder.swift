import Foundation

enum LibraryArchiveBuilder {
    @discardableResult
    static func create(
        catalogURL: URL,
        defectDirectory: URL = DefectSidecarFile.defaultDirectoryURL(),
        destinationURL: URL,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> LibraryArchiveValidationReport {
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw LibraryArchiveError.destinationExists
        }
        guard case let .loaded(catalog, _) = LibraryCatalogFile.read(
            from: catalogURL,
            fileManager: fileManager
        ), let catalogData = LibraryCatalogFile.encode(catalog) else {
            throw LibraryArchiveError.invalidCatalog
        }

        let parent = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString).staging",
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        var committed = false
        defer {
            if !committed { try? fileManager.removeItem(at: staging) }
        }

        var collector = LibraryArchivePayloadCollector(
            stagingURL: staging,
            fileManager: fileManager
        )
        try collector.addCatalog(catalogData)
        let frames = try collectFrames(
            catalog.frames,
            defectDirectory: defectDirectory,
            collector: &collector
        )
        let payloads = collector.payloads.sorted { $0.relativePath < $1.relativePath }
        let archiveManifest = LibraryArchiveManifest(
            createdAt: now,
            catalogVersion: LibraryCatalog.currentVersion,
            frames: frames,
            payloads: payloads
        )
        try writeTagFiles(
            archiveManifest: archiveManifest,
            stagingURL: staging,
            fileManager: fileManager
        )
        let report = try LibraryArchiveValidator.validate(
            at: staging,
            fileManager: fileManager
        )
        try fileManager.moveItem(at: staging, to: destinationURL)
        committed = true
        return report
    }

    private static func collectFrames(
        _ records: [LibraryFrameRecord],
        defectDirectory: URL,
        collector: inout LibraryArchivePayloadCollector
    ) throws -> [LibraryArchiveFrame] {
        try records.sorted { $0.id.uuidString < $1.id.uuidString }.map { frame in
            let originalID = try collector.addSource(at: frame.rawScanPath, role: .original)
            let infraredID = try frame.infraredScanPath.map {
                try collector.addSource(at: $0, role: .infrared)
            }
            let defectID = try frame.hasDefectEdits == true
                ? collector.addDefectRecipe(for: frame.id, from: defectDirectory)
                : nil
            return LibraryArchiveFrame(
                frameID: frame.id,
                originalPayloadID: originalID,
                infraredPayloadID: infraredID,
                defectRecipePayloadID: defectID
            )
        }
    }

    private static func writeTagFiles(
        archiveManifest: LibraryArchiveManifest,
        stagingURL: URL,
        fileManager: FileManager
    ) throws {
        let archiveData = try LibraryArchiveBagIt.encodeArchiveManifest(archiveManifest)
        let bagInfo = LibraryArchiveBagIt.bagInfo(
            createdAt: archiveManifest.createdAt,
            payloads: archiveManifest.payloads
        )
        try Data(LibraryArchiveBagIt.bagItText.utf8)
            .write(to: stagingURL.appendingPathComponent("bagit.txt"), options: .atomic)
        try bagInfo.write(to: stagingURL.appendingPathComponent("bag-info.txt"), options: .atomic)
        try archiveData.write(
            to: stagingURL.appendingPathComponent("negaflow-archive.json"),
            options: .atomic
        )
        let payloadRecords = Dictionary(uniqueKeysWithValues: archiveManifest.payloads.map {
            ($0.relativePath, $0.sha256)
        })
        try Data(LibraryArchiveBagIt.manifestText(payloadRecords).utf8).write(
            to: stagingURL.appendingPathComponent("manifest-sha256.txt"),
            options: .atomic
        )

        let tagPaths = ["bagit.txt", "bag-info.txt", "manifest-sha256.txt", "negaflow-archive.json"]
        let tagRecords = try Dictionary(uniqueKeysWithValues: tagPaths.map { path in
            (path, try LibraryArchiveFileIO.hash(stagingURL.appendingPathComponent(path)).sha256)
        })
        try Data(LibraryArchiveBagIt.manifestText(tagRecords).utf8).write(
            to: stagingURL.appendingPathComponent("tagmanifest-sha256.txt"),
            options: .atomic
        )
    }
}
