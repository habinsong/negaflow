import CoreGraphics
import Chromabase
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import negaflowApp

// 가져온 사진이 현상 작업공간에서 저해상도 썸네일에 고착되던 회귀 방지.
//
// 실제 버그(2026-08-03, Leica DNG 로 재현): 가져오기는 썸네일 시드 태스크를 건 **직후** 그 사진을
// 선택한다. selectedFrameNeedsDevelopment 는 중복 디코드를 막으려고 시드가 도는 동안 false 를
// 돌려주므로 선택 시점 판정은 항상 false 였고, 자동 현상이 꺼진 기본 설정에서는 시드가 끝난 뒤
// 아무도 현상을 다시 걸지 않았다. 그래서 캔버스가 360px 시드 썸네일을 확대해 보여주다가,
// 다른 사진에 갔다 오면(=선택 변경이 한 번 더 일어나면) 그제서야 풀해상도로 바뀌었다.
@MainActor
final class ImportedFrameSelectionDevelopTests: XCTestCase {

    func testFrameSelectedWhileThumbnailSeedRunsStillDevelops() async throws {
        let url = try Self.writeSyntheticPNG()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        model.activeWorkspaceModule = .develop
        model.canvasDisplayTargetPixels = 1_024
        let frame = ScanFrame(
            scanIndex: 1, rawScanURL: url, filmType: .colorPositive, sourceKind: .importedFile
        )
        model.frames = [frame]

        // 가져오기와 같은 순서: 시드를 걸자마자 그 사진을 선택한다.
        model.seedInitialThumbnail(for: frame, from: url)
        XCTAssertNotNil(frame.initialThumbnailSeedTask)
        XCTAssertFalse(
            model.selectedFrameNeedsDevelopment(frame),
            "시드가 도는 동안에는 중복 디코드를 막으려고 현상을 미룬다"
        )

        model.selectedFrameID = frame.id

        let developTask = try XCTUnwrap(
            model.selectedFrameDevelopTask,
            "시드를 기다린다는 이유로 현상 요청을 버리면 사진이 영영 현상되지 않는다"
        )
        await developTask.value

        XCTAssertTrue(frame.hasDevelopedOnce, "시드가 끝나면 선택된 사진이 현상돼야 한다")
        XCTAssertNotNil(frame.developedImage)
    }

    // 라이브러리에서는 여전히 명시적 진입 전까지 현상을 시작하지 않는다.
    func testLibraryModuleStillDefersFirstDevelopment() throws {
        let url = try Self.writeSyntheticPNG()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        model.activeWorkspaceModule = .library
        let frame = ScanFrame(
            scanIndex: 1, rawScanURL: url, filmType: .colorPositive, sourceKind: .importedFile
        )
        model.frames = [frame]
        model.seedInitialThumbnail(for: frame, from: url)
        defer { frame.initialThumbnailSeedTask?.cancel() }

        XCTAssertFalse(model.developmentWaitsForThumbnailSeed(frame))

        model.activeWorkspaceModule = .develop
        XCTAssertTrue(model.developmentWaitsForThumbnailSeed(frame))
    }

    func testCameraNativeNegativeDoesNotWaitForImageIOThumbnailSeed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("raw-seed-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("negative.dng")
        try Data().write(to: url)
        let model = AppModel()
        model.activeWorkspaceModule = .develop
        let raw = ScanFrame(scanIndex: 1, rawScanURL: url,
                            filmType: .colorNegative, sourceKind: .importedFile)
        raw.initialThumbnailSeedTask = Task { }
        defer { raw.initialThumbnailSeedTask?.cancel() }
        XCTAssertFalse(model.developSharesThumbnailSeedDecode(raw))
        XCTAssertTrue(model.selectedFrameNeedsDevelopment(raw))

        raw.params.isDigitalSource = true
        // 입력 해석 전환은 이전 시드를 취소한다. 새 해석의 시드가 도는 상태로 다시 검사한다.
        raw.initialThumbnailSeedTask = Task { }
        XCTAssertTrue(model.developSharesThumbnailSeedDecode(raw))
        XCTAssertFalse(model.selectedFrameNeedsDevelopment(raw))
    }

    func testCameraRAWPrefetchUsesOnlyTheNextVisibleEligibleFrame() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("raw-prefetch-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel()
        let frames = try (1...3).map {
            let url = root.appendingPathComponent("negative\($0).dng")
            try Data().write(to: url)
            return ScanFrame(scanIndex: $0, rawScanURL: url,
                             filmType: .colorNegative, sourceKind: .importedFile)
        }
        model.frames = frames
        // 라이브러리에서는 초기 현상·미리 읽기를 시작하지 않는다.
        model.activeWorkspaceModule = .library
        model.selectedFrameID = frames[0].id
        XCTAssertTrue(model.cameraRAWPrefetchCandidate(after: frames[0]) === frames[1])

        frames[1].params.isDigitalSource = true
        XCTAssertNil(model.cameraRAWPrefetchCandidate(after: frames[0]), "부적격 사진 너머까지 찾아 읽지 않는다")
        frames[1].params.isDigitalSource = nil
        frames[1].defectEditsNeedRestore = true
        XCTAssertNil(model.cameraRAWPrefetchCandidate(after: frames[0]))
        frames[1].defectEditsNeedRestore = false
        let image = try XCTUnwrap(CIContext().createCGImage(CIImage(color: .gray),
            from: CGRect(x: 0, y: 0, width: 8, height: 8)))
        frames[1].cachedSettledPreviewRaw = DevelopFramePreviewRaw(image: image, usesLinearSRGB: true)
        XCTAssertNil(model.cameraRAWPrefetchCandidate(after: frames[0]))
        frames[1].cachedSettledPreviewRaw = nil
        model.interactionScopeFrameIDs = [frames[0].id, frames[2].id]
        XCTAssertTrue(model.cameraRAWPrefetchCandidate(after: frames[0]) === frames[2])
        model.applyFrameCachePressure(.warning)
        XCTAssertNil(model.cameraRAWPrefetchCandidate(after: frames[0]))
    }

    func testNewSelectionCancelsUnrelatedPrefetchButSharesItsOwnDecode() {
        let model = AppModel()
        let id = UUID()
        let pending = Task<Void, Never> { }
        model.neighborCameraRAWPrefetchTask = pending
        model.neighborCameraRAWPrefetchFrameID = id
        model.cancelNeighborCameraRAWPrefetch(keeping: id)
        XCTAssertFalse(pending.isCancelled)
        model.cancelNeighborCameraRAWPrefetch(keeping: UUID())
        XCTAssertTrue(pending.isCancelled)
        XCTAssertNil(model.neighborCameraRAWPrefetchFrameID)
    }

    private static func writeSyntheticPNG(width: Int = 64, height: Int = 48) throws -> URL {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-import-select-\(UUID().uuidString).png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
