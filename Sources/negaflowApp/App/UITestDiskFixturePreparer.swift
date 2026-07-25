import Foundation

enum UITestDiskFixturePreparer {
    static func prepare(_ configuration: AppLaunchConfiguration) {
        guard configuration.preparesCorruptCatalog else { return }
        let root = configuration.uiTestRoot
        let catalogURL = root.appendingPathComponent("Library/catalog.sqlite")
        let defectsURL = root.appendingPathComponent("Library/Defects", isDirectory: true)
        let backupsURL = root.appendingPathComponent("Library/Backups", isDirectory: true)
        do {
            try LibraryBackupStore.createSnapshot(
                catalogURL: catalogURL,
                defectDirectory: defectsURL,
                backupDirectory: backupsURL
            )
            try Data("{corrupt-ui-test-catalog".utf8).write(to: catalogURL, options: .atomic)
        } catch {
            try? Data("fixture-preparation-failed".utf8).write(
                to: root.appendingPathComponent("fixture-error.txt"),
                options: .atomic
            )
        }
    }
}
