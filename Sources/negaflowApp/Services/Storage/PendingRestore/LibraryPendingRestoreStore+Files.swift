import Foundation

extension LibraryPendingRestoreStore {
    static func copySnapshot(
        _ snapshot: LibraryBackupSnapshot,
        to destination: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try fileManager.copyItem(
            at: snapshot.directoryURL.appendingPathComponent("library.json"),
            to: destination.appendingPathComponent("library.json")
        )
        try fileManager.copyItem(
            at: snapshot.directoryURL.appendingPathComponent("manifest.json"),
            to: destination.appendingPathComponent("manifest.json")
        )
        let defects = destination.appendingPathComponent("defects", isDirectory: true)
        try fileManager.createDirectory(at: defects, withIntermediateDirectories: true)
        for frameID in snapshot.manifest.defectFrameIDs {
            try fileManager.copyItem(
                at: DefectSidecarFile.url(
                    for: frameID,
                    in: snapshot.directoryURL.appendingPathComponent("defects", isDirectory: true)
                ),
                to: DefectSidecarFile.url(for: frameID, in: defects)
            )
        }
    }

    static func rawMarker(
        for catalogURL: URL
    ) -> LibraryPendingRestoreMarker? {
        guard let data = try? Data(contentsOf: markerURL(for: catalogURL)) else { return nil }
        return try? LibraryPendingRestoreMarkerCodec.decode(data)
    }

    static func validPendingDirectoryName(_ name: String) -> Bool {
        name == (name as NSString).lastPathComponent && name.hasPrefix("restore-")
    }

    static func supportedMarkerVersion(_ version: Int) -> Bool {
        version >= LibraryPendingRestoreMarker.minimumSupportedVersion
            && version <= LibraryPendingRestoreMarker.currentVersion
    }

    static func directoryHasFiles(
        _ directory: URL,
        fileManager: FileManager
    ) -> Bool {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }
        return !contents.isEmpty
    }

}
