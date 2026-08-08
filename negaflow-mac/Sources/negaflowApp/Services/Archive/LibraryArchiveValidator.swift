import Foundation

enum LibraryArchiveValidator {
    static func validate(
        at archiveURL: URL,
        fileManager: FileManager = .default
    ) throws -> LibraryArchiveValidationReport {
        let digests = try LibraryArchiveChecksumValidator.validate(
            root: archiveURL,
            fileManager: fileManager
        )
        let manifest = try LibraryArchiveBagIt.decodeArchiveManifest(
            Data(contentsOf: archiveURL.appendingPathComponent("negaflow-archive.json"))
        )
        guard manifest.format == LibraryArchiveManifest.formatIdentifier,
              manifest.version == LibraryArchiveManifest.currentVersion else {
            throw LibraryArchiveError.invalidPackage("unsupported archive manifest")
        }
        let payloadsByID = Dictionary(grouping: manifest.payloads, by: \LibraryArchivePayload.id)
        let payloadsByPath = Dictionary(grouping: manifest.payloads, by: \LibraryArchivePayload.relativePath)
        guard payloadsByID.values.allSatisfy({ $0.count == 1 }),
              payloadsByPath.values.allSatisfy({ $0.count == 1 }) else {
            throw LibraryArchiveError.invalidPackage("duplicate payload identity")
        }
        for payload in manifest.payloads {
            guard LibraryArchiveFileIO.isSafeRelativePath(payload.relativePath),
                  payload.relativePath.hasPrefix("data/"),
                  let digest = digests[payload.relativePath],
                  digest.byteCount == payload.byteCount,
                  digest.sha256 == payload.sha256 else {
                throw LibraryArchiveError.invalidPackage("payload metadata mismatch")
            }
        }
        try validateCatalogAndFrames(
            manifest,
            payloadsByID: payloadsByID.mapValues { $0[0] },
            archiveURL: archiveURL
        )
        try validatePayloadOxum(manifest.payloads, archiveURL: archiveURL)
        return LibraryArchiveValidationReport(
            frameCount: manifest.frames.count,
            payloadCount: manifest.payloads.count,
            payloadByteCount: manifest.payloads.reduce(0) { $0 + $1.byteCount }
        )
    }

    private static func validateCatalogAndFrames(
        _ manifest: LibraryArchiveManifest,
        payloadsByID: [String: LibraryArchivePayload],
        archiveURL: URL
    ) throws {
        guard let catalogPayload = payloadsByID["catalog"],
              catalogPayload.role == .catalog,
              catalogPayload.relativePath == "data/catalog/library.json",
              case let .loaded(catalog, sourceVersion) = LibraryCatalogFile.read(
                from: archiveURL.appendingPathComponent(catalogPayload.relativePath)
              ),
              sourceVersion == manifest.catalogVersion else {
            throw LibraryArchiveError.invalidPackage("catalog payload mismatch")
        }
        let framesByID = Dictionary(grouping: manifest.frames, by: \LibraryArchiveFrame.frameID)
        guard framesByID.values.allSatisfy({ $0.count == 1 }),
              Set(framesByID.keys) == Set(catalog.frames.map(\.id)) else {
            throw LibraryArchiveError.invalidPackage("frame set mismatch")
        }
        var referencedPayloadIDs: Set<String> = [catalogPayload.id]
        let defectDirectory = archiveURL.appendingPathComponent("data/defects", isDirectory: true)
        for record in catalog.frames {
            guard let archived = framesByID[record.id]?.first,
                  payloadsByID[archived.originalPayloadID]?.role == .original else {
                throw LibraryArchiveError.invalidPackage("missing original mapping")
            }
            referencedPayloadIDs.insert(archived.originalPayloadID)
            try validateOptionalPayload(
                archived.infraredPayloadID,
                expected: record.infraredScanPath == nil ? nil : .infrared,
                payloadsByID: payloadsByID,
                referenced: &referencedPayloadIDs
            )
            try validateOptionalPayload(
                archived.defectRecipePayloadID,
                expected: record.hasDefectEdits == true ? .defectRecipe : nil,
                payloadsByID: payloadsByID,
                referenced: &referencedPayloadIDs
            )
            if record.hasDefectEdits == true,
               DefectSidecarFile.validatedRawData(for: record.id, in: defectDirectory) == nil {
                throw LibraryArchiveError.invalidPackage("invalid defect recipe")
            }
        }
        guard referencedPayloadIDs == Set(payloadsByID.keys) else {
            throw LibraryArchiveError.invalidPackage("unreferenced payload")
        }
    }

    private static func validateOptionalPayload(
        _ payloadID: String?,
        expected role: LibraryArchivePayloadRole?,
        payloadsByID: [String: LibraryArchivePayload],
        referenced: inout Set<String>
    ) throws {
        guard payloadID != nil || role == nil,
              payloadID == nil || role != nil else {
            throw LibraryArchiveError.invalidPackage("optional payload presence mismatch")
        }
        guard let payloadID else { return }
        guard payloadsByID[payloadID]?.role == role else {
            throw LibraryArchiveError.invalidPackage("optional payload role mismatch")
        }
        referenced.insert(payloadID)
    }

    private static func validatePayloadOxum(
        _ payloads: [LibraryArchivePayload],
        archiveURL: URL
    ) throws {
        let data = try Data(contentsOf: archiveURL.appendingPathComponent("bag-info.txt"))
        guard let text = String(data: data, encoding: .utf8) else {
            throw LibraryArchiveError.invalidPackage("bag-info is not UTF-8")
        }
        let bytes = payloads.reduce(Int64(0)) { $0 + $1.byteCount }
        guard text.split(separator: "\n").contains("Payload-Oxum: \(bytes).\(payloads.count)") else {
            throw LibraryArchiveError.invalidPackage("payload oxum mismatch")
        }
    }
}
