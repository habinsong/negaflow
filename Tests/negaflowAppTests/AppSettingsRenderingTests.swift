import AppKit
import SwiftUI
import XCTest
@testable import negaflowApp

@MainActor
final class AppSettingsRenderingTests: XCTestCase {
    /// `AppSettingsView`가 고정하는 설정창 크기.
    static let windowSize = CGSize(width: 760, height: 640)

    func testEverySettingsPaneRendersInLightAndDarkAppearance() throws {
        let suiteName = "negaflow-settings-render.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let selectedTabKey = AppSettingsTab.defaultsKey
        let previousSelectedTab = UserDefaults.standard.object(forKey: selectedTabKey)
        defer {
            if let previousSelectedTab {
                UserDefaults.standard.set(previousSelectedTab, forKey: selectedTabKey)
            } else {
                UserDefaults.standard.removeObject(forKey: selectedTabKey)
            }
        }

        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            presentationPreferencesStore: PresentationPreferencesStore(defaults: defaults),
            workflowShortcutStore: WorkflowShortcutStore(defaults: defaults),
            diskStorageStore: DiskStorageStore(defaults: defaults),
            backupDestinationStore: LibraryBackupDestinationStore(defaults: defaults),
            backupScheduleStore: LibraryBackupScheduleStore(defaults: defaults),
            scannerPluginTrustStore: nil,
            libraryCatalogURL: temporaryURL("catalog.json"),
            libraryDefectDirectoryURL: temporaryURL("defects"),
            libraryBackupDirectoryURL: temporaryURL("backups")
        )

        for colorScheme in [ColorScheme.light, .dark] {
            for tab in AppSettingsTab.allCases {
                UserDefaults.standard.set(tab.rawValue, forKey: selectedTabKey)
                let representation = try render(
                    model: model,
                    colorScheme: colorScheme
                )
                XCTAssertEqual(representation.size, AppSettingsRenderingTests.windowSize)
                try writeSnapshotIfRequested(
                    representation,
                    tab: tab,
                    colorScheme: colorScheme
                )
            }
        }
    }

    private func render(
        model: AppModel,
        colorScheme: ColorScheme
    ) throws -> NSBitmapImageRep {
        let size = Self.windowSize
        let hostingView = NSHostingView(
            rootView: AppSettingsView()
                .environmentObject(model)
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(colorScheme)
        )
        hostingView.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hostingView.bounds,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))

        let representation = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        return representation
    }

    private func writeSnapshotIfRequested(
        _ representation: NSBitmapImageRep,
        tab: AppSettingsTab,
        colorScheme: ColorScheme
    ) throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment[
            "NEGAFLOW_SETTINGS_UI_SNAPSHOT_DIRECTORY"
        ] else { return }
        let png = try XCTUnwrap(
            representation.representation(using: .png, properties: [:])
        )
        try png.write(
            to: URL(fileURLWithPath: outputDirectory, isDirectory: true)
                .appendingPathComponent(
                    "settings-\(appearanceName(colorScheme))-\(tab.rawValue).png"
                ),
            options: .atomic
        )
    }

    private func appearanceName(_ colorScheme: ColorScheme) -> String {
        colorScheme == .dark ? "dark" : "light"
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-settings-render-\(UUID().uuidString)")
            .appendingPathComponent(name)
    }
}
