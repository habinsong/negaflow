import AppKit
import SwiftUI
import XCTest
@testable import negaflowApp

@MainActor
final class PrintWorkspaceInspectorRenderingTests: XCTestCase {
    func testPrintInspectorTabsRenderAtDefaultPanelWidth() throws {
        let suiteName = "negaflow-print-inspector-render.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = PrintWorkspaceSettingsStore(defaults: defaults)
        settings.layoutMode = .contactSheet
        settings.packageSettings.captionMode = .fileName
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            printWorkspaceSettingsStore: settings
        )
        settings.outputProcess = .cPrint
        for tab in PrintInspectorTab.allCases {
            let representation = try render(
                tab: tab,
                settings: settings,
                model: model
            )
            XCTAssertEqual(
                representation.size,
                CGSize(
                    width: WorkspaceAdaptiveLayout.developPanelDefaultWidth,
                    height: 900
                )
            )
            try writeSnapshotIfRequested(representation, tab: tab)
        }
    }

    func testHistoricalLayoutsReuseSingleImageInspectorSurface() throws {
        let suiteName = "negaflow-print-inspector-historical.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = PrintWorkspaceSettingsStore(defaults: defaults)
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            printWorkspaceSettingsStore: settings
        )

        for mode in [
            PrintWorkspaceLayoutMode.cyanotype,
            .glassPlate,
            .gelatin,
        ] {
            settings.layoutMode = mode
            for tab in [PrintInspectorTab.layout, .output] {
                let representation = try render(
                    tab: tab,
                    settings: settings,
                    model: model
                )
                XCTAssertEqual(
                    representation.size.width,
                    WorkspaceAdaptiveLayout.developPanelDefaultWidth
                )
                XCTAssertEqual(representation.size.height, 900)
            }
        }
    }

    private func render(
        tab: PrintInspectorTab,
        settings: PrintWorkspaceSettingsStore,
        model: AppModel
    ) throws -> NSBitmapImageRep {
        let size = CGSize(
            width: WorkspaceAdaptiveLayout.developPanelDefaultWidth,
            height: 900
        )
        let hostingView = NSHostingView(
            rootView: PrintWorkspaceInspector(
                settingsStore: settings,
                initialTab: tab
            )
                .environmentObject(model)
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
        )
        hostingView.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hostingView.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        let representation = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        return representation
    }

    private func writeSnapshotIfRequested(
        _ representation: NSBitmapImageRep,
        tab: PrintInspectorTab
    ) throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment[
            "NEGAFLOW_PRINT_UI_SNAPSHOT_DIRECTORY"
        ] else { return }
        let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try png.write(
            to: URL(fileURLWithPath: outputDirectory, isDirectory: true)
                .appendingPathComponent("print-inspector-\(tab.rawValue).png"),
            options: .atomic
        )
    }
}
