import Foundation
import CryptoKit

extension LibraryBackupStore {
    static func validSnapshots(
        in backupDirectory: URL,
        fileManager: FileManager
    ) -> [LibraryBackupSnapshot] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { url in
            guard url.lastPathComponent.hasPrefix("backup-"),
                  (try? url.resourceValues(forKeys: keys).isDirectory) == true else { return nil }
            return validateSnapshot(at: url, fileManager: fileManager)
        }
    }

    static func validateSnapshot(
        at directory: URL,
        fileManager: FileManager
    ) -> LibraryBackupSnapshot? {
        guard let manifestData = try? Data(contentsOf: manifestURL(in: directory)),
              let manifest = try? decodeManifest(manifestData),
              (1...LibraryBackupManifest.currentVersion).contains(manifest.version),
              let catalogData = try? Data(contentsOf: catalogURL(in: directory)),
              let catalogSourceVersion = sourceCatalogVersion(in: catalogData),
              let catalog = LibraryCatalogFile.decode(catalogData),
              manifest.frameCount == catalog.frames.count else { return nil }

        let expectedIDs = catalog.frames
            .filter { $0.hasDefectEdits == true }
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
        guard manifest.defectFrameIDs == expectedIDs else { return nil }
        let snapshotDefectDirectory = defectsDirectory(in: directory)
        guard expectedIDs.allSatisfy({
            DefectSidecarFile.load(for: $0, in: snapshotDefectDirectory) != nil
        }) else {
            return nil
        }
        let health = LibraryCatalogHealthInspector.inspect(
            catalog,
            defectDirectory: snapshotDefectDirectory,
            fileManager: fileManager
        )
        guard health.canOpenSafely else { return nil }
        let snapshotDirectory = directory
        let integrity: LibraryBackupIntegrity
        switch manifest.version {
        case 1:
            integrity = .legacyStructureOnly
        case LibraryBackupManifest.checksummedVersion...LibraryBackupManifest.currentVersion:
            guard manifest.catalogVersion == catalogSourceVersion,
                  let recordedFiles = manifest.files,
                  let actualFiles = try? backupFileRecords(
                    defectFrameIDs: expectedIDs,
                    in: snapshotDirectory,
                    fileManager: fileManager
                  ),
                  recordedFiles == actualFiles else { return nil }
            integrity = .checksummed
        default:
            return nil
        }
        return LibraryBackupSnapshot(
            directoryURL: snapshotDirectory,
            manifest: manifest,
            catalog: catalog,
            sourceCatalogVersion: catalogSourceVersion,
            integrity: integrity
        )
    }


}
