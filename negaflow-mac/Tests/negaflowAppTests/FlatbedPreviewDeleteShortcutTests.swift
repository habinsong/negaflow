import CoreGraphics
import XCTest
@testable import Chromabase
@testable import ScannerKit
@testable import negaflowApp

/// 프레임이 그려진 프리뷰 스캔에서 삭제 키(백스페이스)는 사진이 아니라 프레임을 지운다.
///
/// 프리뷰는 프레임을 잡으려고 띄운 임시 이미지다. 여기서 사진을 지우면 방금 잡아 놓은 프레임이
/// 통째로 사라지고 프리뷰부터 다시 떠야 한다 — 휴지통 버튼과 같은 동작이 맞다.
@MainActor
final class FlatbedPreviewDeleteShortcutTests: XCTestCase {
    private var root: URL!
    private var defaultsName: String!

    override func tearDown() async throws {
        if let defaultsName {
            UserDefaults.standard.removePersistentDomain(forName: defaultsName)
        }
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
        defaultsName = nil
        try await super.tearDown()
    }

    func testDeleteKeyRemovesTheSelectedFrameAndKeepsThePreviewImage() async throws {
        let model = try await makeFlatbedPreviewModel()
        let before = model.flatbedScanRegions.count
        XCTAssertGreaterThan(before, 0)
        let selected = try XCTUnwrap(model.selectedFlatbedScanRegionID)
        let previewFrameID = try XCTUnwrap(model.flatbedPreviewFrame?.id)

        model.performWorkflowShortcutAction(.deletePhoto)

        XCTAssertEqual(model.flatbedScanRegions.count, before - 1, "프레임 하나가 지워져야 한다.")
        XCTAssertFalse(model.flatbedScanRegions.contains { $0.id == selected })
        XCTAssertTrue(model.frames.contains { $0.id == previewFrameID },
                      "프리뷰 이미지는 그대로 있어야 한다.")
    }

    func testDeleteKeyStillRemovesOrdinaryPhotos() async throws {
        let model = try await makeFlatbedPreviewModel()
        // 프레임을 모두 지운 프리뷰는 더 이상 "프레임이 그려진 상태"가 아니다.
        model.flatbedScanRegions = []
        model.selectedFlatbedScanRegionID = nil

        let photo = ScanFrame(
            scanIndex: 99,
            rawScanURL: root.appendingPathComponent("photo.tiff"),
            filmType: .colorNegative,
            sourceKind: .scannerTIFF
        )
        model.frames.append(photo)
        model.includeFrameInInteractionScopeIfNeeded(photo.id)
        model.selectedFrameID = photo.id

        model.performWorkflowShortcutAction(.deletePhoto)

        XCTAssertFalse(model.frames.contains { $0.id == photo.id },
                       "보통 사진은 예전처럼 카탈로그에서 제거돼야 한다.")
    }

    private func makeFlatbedPreviewModel() async throws -> AppModel {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-flatbed-delete-\(UUID().uuidString)",
            isDirectory: true
        )
        defaultsName = "negaflow.flatbed-delete.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let diskStorage = DiskStorageStore(defaults: defaults)
        diskStorage.locationMode = .custom
        diskStorage.rootPath = root.appendingPathComponent("storage", isDirectory: true).path
        diskStorage.scansPath = root.appendingPathComponent("storage/Scans", isDirectory: true).path
        diskStorage.scanPreviewsPath = root
            .appendingPathComponent("storage/Scan Previews", isDirectory: true).path
        let support = root.appendingPathComponent("support", isDirectory: true)
        let model = AppModel(
            diskStorageStore: diskStorage,
            scannerDemoBackend: MockScannerBackend(),
            libraryCatalogURL: support.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: support.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: support.appendingPathComponent("Backups", isDirectory: true)
        )
        model.libraryPersistenceEnabled = false
        model.demoMode = true
        model.selectedDeviceID = MockScannerBackend.flatbedScannerID
        await model.loadCapabilities()
        XCTAssertTrue(model.usesFlatbedRegionWorkflow)
        await model.runScan(preview: true)
        XCTAssertFalse(model.flatbedScanRegions.isEmpty)
        return model
    }
}
