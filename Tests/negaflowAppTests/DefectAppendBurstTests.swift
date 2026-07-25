import AppKit
import CoreGraphics
import ScannerKit
import XCTest
@testable import Chromabase
@testable import negaflowApp

/// 연속 편집 버스트 성능 경로 회귀:
///  - 빌드가 진행 중이어도 append 는 커밋된 메모리 베이스(적용 스탬프 일치) 위 증분으로 이어진다.
///  - 디스크 persist 는 빌드 태스크와 분리·코얼레싱된다(다음 편집이 인코딩을 기다리지 않는다).
///  - 영역 결함 제거 는 세션 첫 검출에서 디코드한 원본을 세션 동안 재사용한다.
@MainActor
final class DefectAppendBurstTests: XCTestCase {
    // cleaned-raw persist 가 사용자 머신의 실제/iCloud 폴더를 쓰지 않게 per-test temp 로 격리한다.
    nonisolated(unsafe) private var cleanedRawIsolation: CleanedRawFolderIsolation?

    override func setUp() {
        super.setUp()
        cleanedRawIsolation = CleanedRawFolderIsolation()
    }

    override func tearDown() {
        cleanedRawIsolation?.restore()
        cleanedRawIsolation = nil
        super.tearDown()
    }

    func testRapidAppendsMatchSequentialResultAndKeepStamps() async throws {
        let root = temporaryDirectory("burst-equivalence")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // 같은 원본 바이트의 두 소스: 버스트(대조군은 순차 대기) 결과가 동일해야 한다.
        let burstURL = root.appendingPathComponent("burst.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 24, height: 18, to: burstURL)
        let referenceURL = root.appendingPathComponent("reference.tiff")
        try FileManager.default.copyItem(at: burstURL, to: referenceURL)

        let edits = [
            makeEdit(x: 0.2, y: 0.3),
            makeEdit(x: 0.5, y: 0.5),
            makeEdit(x: 0.8, y: 0.7),
        ]

        let burstModel = makeModel(root: root, name: "burst")
        let burstFrame = ScanFrame(scanIndex: 1, rawScanURL: burstURL, filmType: .colorNegative)
        burstModel.frames = [burstFrame]
        // 첫 편집을 커밋해 메모리 베이스를 만든 뒤, 나머지를 빌드 완료를 기다리지 않고 겹쳐
        // 넣는다 — 스탬프 기반 증분(suffix) 경로의 픽셀 결과가 순차 대조군과 같아야 한다.
        burstModel.appendDefectEdit(edits[0], to: burstFrame)
        while let task = burstFrame.cleanRawTask { await task.value }
        for edit in edits.dropFirst() {
            burstModel.appendDefectEdit(edit, to: burstFrame)
        }
        while let task = burstFrame.cleanRawTask { await task.value }

        let referenceModel = makeModel(root: root, name: "reference")
        let referenceFrame = ScanFrame(scanIndex: 1, rawScanURL: referenceURL, filmType: .colorNegative)
        referenceModel.frames = [referenceFrame]
        for edit in edits {
            referenceModel.appendDefectEdit(edit, to: referenceFrame)
            while let task = referenceFrame.cleanRawTask { await task.value }
        }

        XCTAssertEqual(burstFrame.cleanedRawEditCount, edits.count)
        XCTAssertEqual(
            burstFrame.cleanedRawAppliedStamps,
            burstFrame.defectEdits.map(\.appliedStamp)
        )
        XCTAssertEqual(burstFrame.cleanedRawMemoryIdentity, burstFrame.defectRecipeIdentity)
        let burstPixels = try XCTUnwrap(rgba16Bytes(of: burstFrame.cleanedRawImage))
        let referencePixels = try XCTUnwrap(rgba16Bytes(of: referenceFrame.cleanedRawImage))
        XCTAssertEqual(burstPixels, referencePixels)

        burstFrame.cleanedRawPersistTask?.cancel()
        referenceFrame.cleanedRawPersistTask?.cancel()
        cleanupOwnedCaches(for: [burstFrame, referenceFrame])
    }

    func testAppendWithValidMemoryBaseIncrementsWhileBuildInFlight() async throws {
        let root = temporaryDirectory("inflight-increment")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("scan.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 24, height: 18, to: sourceURL)

        let model = makeModel(root: root, name: "inflight")
        let frame = ScanFrame(scanIndex: 1, rawScanURL: sourceURL, filmType: .colorNegative)
        model.frames = [frame]

        model.appendDefectEdit(makeEdit(x: 0.25, y: 0.25), to: frame)
        while let task = frame.cleanRawTask { await task.value }
        let committedBase = try XCTUnwrap(frame.cleanedRawImage)

        // 두 번째 append 직후(빌드 진행 중) 세 번째를 겹쳐 넣는다 — 둘 다 커밋 베이스 위 증분이어야
        // 하므로 진행 중 빌드가 있어도 이전 커밋 픽셀/스탬프는 그대로 남아 있다.
        model.appendDefectEdit(makeEdit(x: 0.5, y: 0.5), to: frame)
        XCTAssertNotNil(frame.cleanRawTask)
        XCTAssertTrue(frame.cleanedRawImage === committedBase)
        XCTAssertEqual(frame.cleanedRawAppliedStamps.count, 1)
        model.appendDefectEdit(makeEdit(x: 0.75, y: 0.75), to: frame)
        while let task = frame.cleanRawTask { await task.value }

        XCTAssertEqual(frame.cleanedRawEditCount, 3)
        XCTAssertEqual(frame.cleanedRawAppliedStamps, frame.defectEdits.map(\.appliedStamp))
        frame.cleanedRawPersistTask?.cancel()
        cleanupOwnedCaches(for: [frame])
    }

    func testDiskPersistIsDecoupledFromBuildAndCoalesced() async throws {
        let root = temporaryDirectory("persist-coalesce")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("scan.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 24, height: 18, to: sourceURL)

        let model = makeModel(root: root, name: "persist")
        let frame = ScanFrame(scanIndex: 1, rawScanURL: sourceURL, filmType: .colorNegative)
        model.frames = [frame]

        model.appendDefectEdit(makeEdit(x: 0.3, y: 0.4), to: frame)
        while let task = frame.cleanRawTask { await task.value }

        // 빌드 종료 시점에 디스크 백킹은 아직 없다(persist 는 분리·지연) — 다음 편집이 인코딩을
        // 기다리지 않는다는 계약 그 자체다.
        XCTAssertNil(frame.cleanRawTask)
        XCTAssertNotNil(frame.cleanedRawPersistTask)
        XCTAssertNil(frame.cleanedRawDiskURL)

        // 버스트 두 번째 편집이 이전 persist 예약을 취소하고 마지막 상태만 저장한다.
        model.appendDefectEdit(makeEdit(x: 0.6, y: 0.6), to: frame)
        while let task = frame.cleanRawTask { await task.value }
        if let persist = frame.cleanedRawPersistTask { await persist.value }

        let identity = try XCTUnwrap(frame.defectRecipeIdentity)
        XCTAssertEqual(frame.cleanedRawDiskIdentity, identity)
        let diskURL = try XCTUnwrap(frame.cleanedRawDiskURL)
        XCTAssertTrue(CleanedRawCacheFile.isOwnedCacheURL(diskURL, frameID: frame.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: diskURL.path))
        XCTAssertEqual(
            ownedCacheFileCount(
                frameID: frame.id,
                in: diskURL.deletingLastPathComponent()
            ),
            1
        )
        cleanupOwnedCaches(for: [frame])
    }

    func testRegionDetectCachesSessionRawAndClearsOnSessionEnd() async throws {
        let root = temporaryDirectory("region-session")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("scan.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 48, height: 36, to: sourceURL)

        let model = makeModel(root: root, name: "region")
        let frame = ScanFrame(scanIndex: 1, rawScanURL: sourceURL, filmType: .colorNegative)
        model.frames = [frame]
        let roi = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)

        model.runRegionDetect(frame, displayROI: roi)
        while let task = frame.defectDetectTask { await task.value }
        // 첫 검출은 ROI 만 굳혀 즉시 반환하고(검출 시작 지연 제거), 전체 세션 캐시는
        // 백그라운드 solidify 가 채운다 — 완료를 기다린 뒤 캐시 계약을 검증한다.
        if let solidify = frame.defectSessionSolidifyTask { await solidify.value }

        // cleanedRawImage 가 없는 프레임 = 디스크 소스 → 세션 캐시가 굳는다.
        let sessionRaw = try XCTUnwrap(frame.defectSessionRaw)
        XCTAssertEqual(frame.defectSessionRawRevision, frame.cleanRawRevision)
        XCTAssertNotNil(frame.defectBaseSize)

        // 같은 세션의 재검출은 캐시를 재사용한다(동일 객체 유지 + 결과 정상).
        model.runRegionDetect(frame, displayROI: roi)
        while let task = frame.defectDetectTask { await task.value }
        XCTAssertTrue(frame.defectSessionRaw === sessionRaw)
        XCTAssertNotNil(frame.defectBaseSize)

        model.cancelRegionDefect(frame)
        XCTAssertNil(frame.defectSessionRaw)
        XCTAssertEqual(frame.defectSessionRawRevision, -1)
    }

    func testRepeatedRegionCommitsFinishWithoutViewOwnedCleanup() async throws {
        let root = temporaryDirectory("region-repeat")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("scan.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 24, height: 18, to: sourceURL)

        let model = makeModel(root: root, name: "region-repeat")
        let frame = ScanFrame(scanIndex: 1, rawScanURL: sourceURL, filmType: .colorNegative)
        model.frames = [frame]
        model.selectedFrameID = frame.id

        for pass in 1...8 {
            installDetectedRegionSession(on: frame)
            model.commitRegionDefect(frame)

            try await waitUntil("region edit append pass \(pass)") {
                frame.defectEdits.count == pass
            }
            try await waitUntil("region build finish pass \(pass)") {
                frame.cleanRawTask == nil
                    && frame.cleanedRawEditCount == pass
                    && !frame.isRemovingDefects
                    && !frame.defectIsRemoving
            }

            XCTAssertFalse(frame.defectActive)
            XCTAssertEqual(frame.cleanedRawAppliedStamps, frame.defectEdits.map(\.appliedStamp))
            XCTAssertEqual(frame.cleanedRawMemoryIdentity, frame.defectRecipeIdentity)
            XCTAssertEqual(frame.defectEdits.filter { $0.cachedPatches != nil }.count, 1)
            XCTAssertTrue(frame.defectEditUndoStack.allSatisfy { snapshot in
                snapshot.allSatisfy { $0.cachedPatches == nil }
            })
        }

        frame.cleanedRawPersistTask?.cancel()
        cleanupOwnedCaches(for: [frame])
    }

    func testRegionCommitValidationFailureRollsBackAndReenablesRemoval() async throws {
        let root = temporaryDirectory("region-rollback")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("scan.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 24, height: 18, to: sourceURL)

        let model = makeModel(root: root, name: "region-rollback")
        let frame = ScanFrame(scanIndex: 1, rawScanURL: sourceURL, filmType: .colorNegative)
        model.frames = [frame]
        model.selectedFrameID = frame.id
        frame.defectRecipeRevision = UInt64.max
        installDetectedRegionSession(on: frame)

        model.commitRegionDefect(frame)
        try await waitUntil("failed region commit cleanup") {
            !frame.isRemovingDefects && !frame.defectIsRemoving
        }

        XCTAssertTrue(frame.defectEdits.isEmpty)
        XCTAssertTrue(frame.defectEditUndoStack.isEmpty)
        XCTAssertNil(frame.cleanRawTask)
        XCTAssertTrue(frame.defectActive)
        XCTAssertNotNil(frame.defectLabelField)
    }

    func testCriticalPressureDoesNotEvictCleanedRawBeforeDevelopConsumesIt() async throws {
        let root = temporaryDirectory("critical-develop")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("scan.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 24, height: 18, to: sourceURL)

        let model = makeModel(root: root, name: "critical-develop")
        let frame = ScanFrame(scanIndex: 1, rawScanURL: sourceURL, filmType: .colorNegative)
        model.frames = [frame]
        model.selectedFrameID = frame.id
        model.applyFrameCachePressure(.critical)

        model.appendDefectEdit(makeRegionEdit(), to: frame)
        try await waitUntil("critical build finish") {
            frame.cleanRawTask == nil && !frame.isRemovingDefects
        }

        XCTAssertNotNil(frame.developedImage)
        XCTAssertTrue(frame.hasDevelopedOnce)
        XCTAssertNil(frame.cleanedRawImage)
        XCTAssertTrue(model.residentCleanedRawIDs.isEmpty)

        frame.cleanedRawPersistTask?.cancel()
        cleanupOwnedCaches(for: [frame])
    }

    // MARK: helpers

    private func temporaryDirectory(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-defect-burst-\(suffix)-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func makeModel(root: URL, name: String) -> AppModel {
        AppModel(
            libraryCatalogURL: root.appendingPathComponent("\(name)-library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("\(name)-defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("\(name)-Backups")
        )
    }

    private func makeEdit(x: CGFloat, y: CGFloat) -> DefectEditItem {
        DefectEditItem(
            edit: .brush([DefectStroke(
                points: [CGPoint(x: x, y: y)],
                thickness: 0.06
            )]),
            label: .brush(strokeCount: 1),
            summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)),
            preview: [],
            baseSize: nil
        )
    }

    private func makeRegionEdit() -> DefectEditItem {
        DefectEditItem(
            edit: .region(
                mask: .raw(Data(repeating: 255, count: 8 * 8 * 4)),
                roi: CGRect(x: 4, y: 4, width: 8, height: 8),
                width: 8,
                height: 8
            ),
            label: .guided(count: 1),
            summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)),
            preview: [],
            baseSize: CGSize(width: 24, height: 18)
        )
    }

    private func installDetectedRegionSession(on frame: ScanFrame) {
        let width = 8
        let height = 8
        let pixels = [27, 28, 35, 36]
        var labels = [Int32](repeating: -1, count: width * height)
        for pixel in pixels { labels[pixel] = 0 }
        let component = DefectComponent(
            id: 0,
            kind: .dust,
            pixels: pixels,
            minX: 3,
            minY: 3,
            maxX: 4,
            maxY: 4,
            classification: .dust,
            confidence: 1
        )
        frame.defectLabelField = DefectLabelField(
            width: width,
            height: height,
            labels: labels,
            components: [component]
        )
        frame.defectBaseSize = CGSize(width: 24, height: 18)
        frame.defectROIPixelX0 = 4
        frame.defectROIPixelY0 = 6
        frame.defectROICIyup = CGRect(x: 4, y: 4, width: 8, height: 8)
        frame.defectExcludedIDs = []
        frame.defectPreview = [DefectPreviewComponent(
            id: 0,
            kind: .dust,
            classification: .dust,
            confidence: 1,
            points: [CGPoint(x: 0.3, y: 0.5)]
        )]
        frame.defectActive = true
        frame.defectIsDetecting = false
        frame.defectIsRemoving = false
    }

    /// 픽셀 비교용 정규화 렌더(RGBA16 고정 레이아웃).
    private func rgba16Bytes(of image: CGImage?) -> [UInt8]? {
        guard let image else { return nil }
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 8)
        guard let space = CGColorSpace(name: CGColorSpace.linearSRGB),
              let context = CGContext(
                  data: &data,
                  width: width,
                  height: height,
                  bitsPerComponent: 16,
                  bytesPerRow: width * 8,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      | CGBitmapInfo.byteOrder16Little.rawValue
              ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    private func ownedCacheFileCount(frameID: UUID, in directory: URL) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { CleanedRawCacheFile.frameID(fromFileName: $0) == frameID }.count
    }

    private func cleanupOwnedCaches(for frames: [ScanFrame]) {
        let ids = Set(frames.map(\.id))
        var directories = Set(frames.compactMap {
            $0.cleanedRawDiskURL?.deletingLastPathComponent().standardizedFileURL
        })
        directories.insert(CleanedRawCacheFile.defaultDirectoryURL().standardizedFileURL)
        for directory in directories {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for name in names where CleanedRawCacheFile.frameID(fromFileName: name).map(ids.contains) == true {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }
}
