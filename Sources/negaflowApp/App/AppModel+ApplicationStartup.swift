import Foundation
import ScannerKit

extension AppModel {
    func startApplication(configuration: AppLaunchConfiguration? = .current) async {
        await restoreLibraryOnLaunch()
        if configuration?.enablesDemoScanner == true {
            await refreshDevices()
        } else {
            await refreshDevicesOnStartup()
        }
        prepareUITestFixture(configuration)
        if configuration == nil {
            await runScheduledBackupIfDue()
        }
    }

    private func prepareUITestFixture(_ configuration: AppLaunchConfiguration?) {
        guard let configuration, configuration.importsSyntheticNegative else { return }
        let fixtureURL = configuration.uiTestRoot
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("synthetic-negative.tiff")
        do {
            try FileManager.default.createDirectory(
                at: fixtureURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try MockScannerBackend.writeSyntheticNegative(width: 640, height: 480, to: fixtureURL)
            importImages(urls: [fixtureURL])
            if configuration.createsDropTargetFolder {
                _ = createLibraryFolder(
                    named: "DropTarget",
                    in: configuration.uiTestRoot
                )
            }
        } catch {
            statusMessage = text(.importLibraryRegistrationFailedStatus)
        }
    }
}
