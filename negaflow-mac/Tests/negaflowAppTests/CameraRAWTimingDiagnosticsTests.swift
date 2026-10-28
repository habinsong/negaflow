import AppKit
import Combine
import CoreImage
import Chromabase
import XCTest
@testable import negaflowApp

/// 카메라 RAW 네거티브를 앱과 같은 순서로 열 때 걸리는 시간을 잰다. 실제 파일이 필요해 기본은 건너뛴다.
///
///     NEGAFLOW_LIBRAW_LIBRARY=<libraw.dylib> NEGAFLOW_RAW_TIMING_FILES=<a.RAF:b.NEF> \
///       swift test -c release -Xswiftc -enable-testing --filter CameraRAWTimingDiagnosticsTests
///
/// 파일마다 새 모델에서 (1) 가져온 직후 선택: 첫 화면·정착 시각, (2) 같은 사진 재선택, (3) 썸네일 일괄
/// 현상 시간을 출력한다. 파일 내용은 보지 않고 시간만 잰다.
@MainActor
final class CameraRAWTimingDiagnosticsTests: XCTestCase {
    /// 기존 카탈로그에서의 첫 선택: 썸네일 시드나 이웃 선행 디코드 없이 잰다.
    func testColdCatalogStyleSelectionTiming() async throws {
        guard let list = ProcessInfo.processInfo.environment["NEGAFLOW_RAW_TIMING_FILES"],
              NativeCameraRAW.isAvailable else { throw XCTSkip("RAW samples and LibRaw required") }
        let urls = list.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        let (model, root) = try await makeModel()
        defer { model.cancelNeighborCameraRAWPrefetch(); try? FileManager.default.removeItem(at: root) }
        let frames = urls.enumerated().map {
            ScanFrame(scanIndex: $0.offset + 1, rawScanURL: $0.element,
                filmType: .colorNegative, sourceKind: .importedFile)
        }
        model.frames = frames
        XCTAssertTrue(model.assignNewPersistentFrames(frames))
        for frame in frames {
            NativeCameraRAW.purgePreviewCache()
            model.interactionScopeFrameIDs = [frame.id]
            let start = Date()
            model.activateFrame(frame.id)
            let first = try await wait(since: start) { frame.developedImage != nil }
            let settled = try await wait(since: start) { frame.developedIsSettled }
            await model.selectedFrameDevelopTask?.value
            XCTAssertEqual(model.selectedFrameID, frame.id)
            print(String(format: "[raw-catalog] %@ cold first %.0f ms settled %.0f ms",
                frame.rawScanURL.lastPathComponent, first * 1000, settled * 1000))
        }
    }

    func testNeighborPrefetchTimingAndPixelAgreement() async throws {
        guard let list = ProcessInfo.processInfo.environment["NEGAFLOW_RAW_TIMING_FILES"],
              NativeCameraRAW.isAvailable else {
            throw XCTSkip("NEGAFLOW_RAW_TIMING_FILES and NEGAFLOW_LIBRAW_LIBRARY are required")
        }
        let urls = list.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        guard urls.count >= 2 else { throw XCTSkip("At least two RAW files are required") }
        var reference: [Data] = []
        for prefetch in [false, true] {
            NativeCameraRAW.purgePreviewCache()
            let (model, root) = try await makeModel()
            defer { try? FileManager.default.removeItem(at: root) }
            let frames = urls.enumerated().map {
                ScanFrame(scanIndex: $0.offset + 1, rawScanURL: $0.element,
                          filmType: .colorNegative, sourceKind: .importedFile)
            }
            model.frames = frames
            XCTAssertTrue(model.assignNewPersistentFrames(frames))
            for (index, frame) in frames.enumerated() {
                if prefetch, index > 0 { await model.neighborCameraRAWPrefetchTask?.value }
                if !prefetch { model.interactionScopeFrameIDs = [frame.id] }
                model.seedInitialThumbnail(for: frame, from: frame.rawScanURL)
                let start = Date()
                model.activateFrame(frame.id)
                let first = try await wait(since: start) { frame.developedImage != nil }
                let settled = try await wait(since: start) { frame.developedIsSettled }
                await model.selectedFrameDevelopTask?.value
                let image = try XCTUnwrap(frame.developedImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
                let pixels = try XCTUnwrap(image.dataProvider?.data) as Data
                if prefetch { XCTAssertEqual(pixels, reference[index], "Prefetch must not change rendered pixels") }
                else { reference.append(pixels) }
                print(String(format: "[raw-prefetch] %@ on=%@ first %.0f ms settled %.0f ms",
                             frame.rawScanURL.lastPathComponent, prefetch ? "true" : "false", first * 1000, settled * 1000))
            }
            model.cancelNeighborCameraRAWPrefetch()
            await model.neighborCameraRAWPrefetchTask?.value
        }
    }

    func testEditingWhileNeighborPrefetchRuns() async throws {
        guard let list = ProcessInfo.processInfo.environment["NEGAFLOW_RAW_TIMING_FILES"],
              NativeCameraRAW.isAvailable else {
            throw XCTSkip("NEGAFLOW_RAW_TIMING_FILES and NEGAFLOW_LIBRAW_LIBRARY are required")
        }
        let urls = list.split(separator: ":").prefix(2).map { URL(fileURLWithPath: String($0)) }
        guard urls.count == 2 else { throw XCTSkip("At least two RAW files are required") }
        for prefetch in [false, true] {
            NativeCameraRAW.purgePreviewCache()
            let (model, root) = try await makeModel()
            defer { try? FileManager.default.removeItem(at: root) }
            let frames = urls.enumerated().map {
                ScanFrame(scanIndex: $0.offset + 1, rawScanURL: $0.element,
                          filmType: .colorNegative, sourceKind: .importedFile)
            }
            model.frames = frames
            XCTAssertTrue(model.assignNewPersistentFrames(frames))
            if !prefetch { model.interactionScopeFrameIDs = [frames[0].id] }
            model.activateFrame(frames[0].id)
            await model.selectedFrameDevelopTask?.value
            // 이웃 디코드가 CPU를 쓰는 동안 조작을 시작한다.
            try await Task.sleep(nanoseconds: 50_000_000)
            var times: [Double] = []
            for step in 1...5 {
                let start = Date()
                frames[0].updateParams { $0.exposure = Double(step) * 0.1 }
                frames[0].developedIsSettled = false
                model.requestDevelop(frames[0])
                times.append(try await wait(since: start) { frames[0].developedIsSettled } * 1000)
            }
            print("[raw-prefetch-edit] on=\(prefetch) settled ms=\(times.map { Int($0) })")
            model.cancelNeighborCameraRAWPrefetch()
            await model.neighborCameraRAWPrefetchTask?.value
        }
    }

    func testSelectionAndThumbnailTiming() async throws {
        guard let list = ProcessInfo.processInfo.environment["NEGAFLOW_RAW_TIMING_FILES"],
              NativeCameraRAW.isAvailable else {
            throw XCTSkip("NEGAFLOW_RAW_TIMING_FILES and NEGAFLOW_LIBRAW_LIBRARY are required")
        }
        let urls = list.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        for url in urls {
            let (model, root) = try await makeModel()
            defer { try? FileManager.default.removeItem(at: root) }
            let frame = ScanFrame(scanIndex: 1, rawScanURL: url, filmType: .colorNegative, sourceKind: .importedFile)
            model.frames = [frame]
            XCTAssertTrue(model.assignNewPersistentFrames([frame]))
            let start = Date()
            print(String(format: "[raw-timing] t=%.0f select %@", Double(DispatchTime.now().uptimeNanoseconds) / 1e6, url.lastPathComponent))
            model.seedInitialThumbnail(for: frame, from: url)
            model.activateFrame(frame.id)
            let first = try await wait(since: start) { frame.developedImage != nil }
            let settled = try await wait(since: start) { frame.developedIsSettled }
            await model.selectedFrameDevelopTask?.value
            print(String(format: "[raw-timing] %@ select-cold first %.0f ms settled %.0f ms",
                         url.lastPathComponent, first * 1000, settled * 1000))

            let other = ScanFrame(scanIndex: 2, rawScanURL: url, filmType: .colorNegative, sourceKind: .importedFile)
            model.frames.append(other)
            model.activateFrame(other.id)
            await model.selectedFrameDevelopTask?.value
            frame.developedImage = nil
            frame.developedIsSettled = false
            let restart = Date()
            model.activateFrame(frame.id)
            let reFirst = try await wait(since: restart) { frame.developedImage != nil }
            let reSettled = try await wait(since: restart) { frame.developedIsSettled }
            await model.selectedFrameDevelopTask?.value
            print(String(format: "[raw-timing] %@ reselect first %.0f ms settled %.0f ms",
                         url.lastPathComponent, reFirst * 1000, reSettled * 1000))
        }

        // 라이브러리 썸네일: 한 모델에서 모든 파일을 앱의 순차 현상 경로로 돌린다.
        let (model, root) = try await makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let frames = urls.enumerated().map {
            ScanFrame(scanIndex: $0.offset + 1, rawScanURL: $0.element, filmType: .colorNegative, sourceKind: .importedFile)
        }
        model.activeWorkspaceModule = .library
        model.frames = frames
        XCTAssertTrue(model.assignNewPersistentFrames(frames))
        let start = Date()
        await model.developImportedFramesSequentially(frames).value
        XCTAssertTrue(frames.allSatisfy { $0.thumbnailImage != nil })
        print(String(format: "[raw-timing] thumbnails %d frames %.0f ms", frames.count, -start.timeIntervalSinceNow * 1000))
    }

    func testRapidColdSelectionsOnlyPublishCurrentFrameWithinResidencyLimit() async throws {
        guard NativeCameraRAW.supportsProgressivePreview,
              let list = ProcessInfo.processInfo.environment["NEGAFLOW_RAW_TIMING_FILES"] else {
            throw XCTSkip("NEGAFLOW_RAW_TIMING_FILES and bundled LibRaw are required")
        }
        let urls = list.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        guard urls.count > 1 else { throw XCTSkip("At least two RAW files are required") }
        let (model, root) = try await makeModel()
        defer { model.selectedFrameDevelopTask?.cancel(); try? FileManager.default.removeItem(at: root) }
        let frames = urls.enumerated().map {
            ScanFrame(scanIndex: $0.offset + 1, rawScanURL: $0.element,
                filmType: .colorNegative, sourceKind: .importedFile)
        }
        model.frames = frames
        XCTAssertTrue(model.assignNewPersistentFrames(frames))
        model.applyFrameCacheLimits(FrameCacheLimits(cleanedRaw: 1, developed: 2))
        var unsettledOnLeave: [ScanFrame] = []
        for frame in frames {
            NativeCameraRAW.purgePreviewCache()
            model.interactionScopeFrameIDs = [frame.id]
            model.activateFrame(frame.id)
            if frame.id != frames.last?.id {
                try await Task.sleep(nanoseconds: 100_000_000)
                if !frame.developedIsSettled { unsettledOnLeave.append(frame) }
            }
        }
        let last = try XCTUnwrap(frames.last)
        _ = try await wait(since: Date()) { last.developedIsSettled }
        await model.selectedFrameDevelopTask?.value
        XCTAssertEqual(model.selectedFrameID, last.id)
        XCTAssertTrue(unsettledOnLeave.allSatisfy { !$0.developedIsSettled })
        XCTAssertLessThanOrEqual(model.frameCacheManager.residentDevelopedIDs.count, 2)
        XCTAssertLessThanOrEqual(frames.filter { $0.developedImage != nil }.count, 2)
    }

    /// 네거티브(LibRaw)와 포지티브(CIRAWFilter) 디코드가 같은 방향을 내는지 64px 휘도 지도의 상관으로 잰다.
    func testDecoderOrientationAgreement() throws {
        guard let list = ProcessInfo.processInfo.environment["NEGAFLOW_RAW_TIMING_FILES"],
              NativeCameraRAW.isAvailable else {
            throw XCTSkip("NEGAFLOW_RAW_TIMING_FILES and NEGAFLOW_LIBRAW_LIBRARY are required")
        }
        for path in list.split(separator: ":") {
            let url = URL(fileURLWithPath: String(path))
            guard ImageLoader.kind(of: url) == .rawDng else { continue }
            let native = try XCTUnwrap(ImageLoader.loadImportedPreview(url, maxDimension: 600,
                highResolutionThreshold: 0, rawRendering: .cameraNativeNegative)).image
            let apple = try XCTUnwrap(ImageLoader.loadImportedPreview(url, maxDimension: 600,
                highResolutionThreshold: 0, rawRendering: .sceneLinear)).image
            let reference = lumaMap(apple)
            let scores = (1...8).map { orientation -> (Int32, Double) in
                (Int32(orientation), correlation(lumaMap(native.oriented(forExifOrientation: Int32(orientation))), reference))
            }
            let best = scores.max { $0.1 < $1.1 }!
            XCTAssertGreaterThanOrEqual(scores[0].1 + 0.02, best.1,
                                        "Native and Apple decoder orientations differ: \(url.lastPathComponent)")
            print(String(format: "[raw-orientation] %@ native %.0fx%.0f apple %.0fx%.0f best exif %d (r=%.3f, identity r=%.3f)",
                         url.lastPathComponent, native.extent.width, native.extent.height,
                         apple.extent.width, apple.extent.height, best.0, best.1, scores[0].1))
        }
    }

    /// 프로세스·사용자 회전 전환 뒤 캔버스, 썸네일, 출력이 같은 방향을 유지해야 한다.
    /// 스캔 경로는 NEGAFLOW_ORIENTATION_SCANNER_FILES의 명시적 파일 목록으로 고른다.
    func testProcessSwitchKeepsOrientation() async throws {
        guard let list = ProcessInfo.processInfo.environment["NEGAFLOW_RAW_TIMING_FILES"],
              NativeCameraRAW.isAvailable else {
            throw XCTSkip("NEGAFLOW_RAW_TIMING_FILES and NEGAFLOW_LIBRAW_LIBRARY are required")
        }
        let scannerFiles = Set((ProcessInfo.processInfo.environment["NEGAFLOW_ORIENTATION_SCANNER_FILES"] ?? "")
            .split(separator: ":").map { URL(fileURLWithPath: String($0)).standardizedFileURL })
        for path in list.split(separator: ":") {
            let url = URL(fileURLWithPath: String(path))
            let (model, root) = try await makeModel()
            defer { try? FileManager.default.removeItem(at: root) }
            let frame = ScanFrame(scanIndex: 1, rawScanURL: url, filmType: .colorNegative,
                                  sourceKind: scannerFiles.contains(url.standardizedFileURL) ? .scannerTIFF : .importedFile)
            model.frames = [frame]
            XCTAssertTrue(model.assignNewPersistentFrames([frame]))
            model.activateFrame(frame.id)
            await model.selectedFrameDevelopTask?.value
            if ProcessInfo.processInfo.environment["NEGAFLOW_RAW_ROTATE"] == "1" {
                let before = try XCTUnwrap(frame.developedImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
                model.rotate(frame, clockwise: true)
                _ = try await wait(since: Date()) {
                    frame.transformTask == nil && frame.developedPreviewTransform == frame.imageTransform
                }
                let after = try XCTUnwrap(frame.developedImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
                XCTAssertEqual(after.width > after.height, before.height > before.width)
                assertSameOrientation(CIImage(cgImage: after),
                    reference: lumaMap(CIImage(cgImage: before).oriented(forExifOrientation: 6)),
                    label: "clockwise rotation \(url.lastPathComponent)")
            }
            let expectedTransform = frame.imageTransform
            let initial = try XCTUnwrap(frame.developedImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let expectedLandscape = initial.width > initial.height
            var transientAxisChanges = 0
            let observations = [frame.$developedImage, frame.$thumbnailImage].map { publisher in
                publisher.dropFirst().sink { image in
                    guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                    if (cg.width > cg.height) != expectedLandscape { transientAxisChanges += 1 }
                }
            }
            defer { observations.forEach { $0.cancel() } }
            var reference: [Double]?
            var landscape: Bool?
            for process in DevelopmentProcess.allCases + [.c41] {
                let revision = frame.developRevision
                model.applyDevelopmentProcess(process, to: frame)
                _ = try await wait(since: Date()) {
                    frame.developRevision > revision && frame.developedIsSettled && !frame.isDeveloping
                }
                let developed = try XCTUnwrap(frame.developedImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
                let thumb = try XCTUnwrap(frame.thumbnailImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
                let image = CIImage(cgImage: developed)
                let map = lumaMap(image)
                if reference == nil { reference = map; landscape = developed.width > developed.height }
                XCTAssertEqual(frame.imageTransform, expectedTransform, "Process must not change user geometry")
                XCTAssertEqual(developed.width > developed.height, landscape, "Canvas axis changed: \(url.lastPathComponent) \(process)")
                XCTAssertEqual(thumb.width > thumb.height, landscape, "Thumbnail axis changed: \(url.lastPathComponent) \(process)")
                assertSameOrientation(image, reference: reference!, label: "canvas \(url.lastPathComponent) \(process)")
                assertSameOrientation(CIImage(cgImage: thumb), reference: map,
                                      label: "thumbnail \(url.lastPathComponent) \(process)")
                // 두 RAW 디코더 경로를 모두 출력한다. B&W는 위에서 같은 입력 경로의 화면·썸네일을 검사한다.
                if process == .c41 || process == .digitalColor {
                    let destination = root.appendingPathComponent("orientation-\(process).tiff")
                    let result = await model.runExportFrameTransaction(frame, to: destination, format: .tiff16,
                        writeSidecar: false, writeMainFlatMaster: false, writeOriginalRaw: false,
                        options: .standard, recipeIdentity: nil, reportsGlobalStatus: false)
                    guard case .completed = result else {
                        XCTFail("Orientation export failed: \(result)")
                        continue
                    }
                    let exported = try XCTUnwrap(ImageLoader.loadImportedPreview(destination, maxDimension: 600,
                        highResolutionThreshold: 0)?.image ?? ImageLoader.loadImported(destination))
                    XCTAssertEqual(exported.extent.width > exported.extent.height, landscape,
                                   "Export axis changed: \(url.lastPathComponent) \(process)")
                    assertSameOrientation(exported, reference: map, label: "export \(url.lastPathComponent) \(process)")
                    try FileManager.default.removeItem(at: destination)
                }
                print("[raw-orientation] \(url.lastPathComponent) \(process) canvas \(developed.width)x\(developed.height) thumb \(thumb.width)x\(thumb.height) rotation \(expectedTransform.rotation)")
            }
            XCTAssertEqual(transientAxisChanges, 0, "An intermediate canvas or thumbnail changed axes")
            XCTAssertEqual(frame.rawScanURL, url)
        }
    }

    private func assertSameOrientation(_ image: CIImage, reference: [Double], label: String) {
        let scores = (1...8).map { abs(correlation(lumaMap(image.oriented(forExifOrientation: Int32($0))), reference)) }
        let best = scores.max()!
        // 프로세스별 색·대비 변화와 작은 RAW 유효영역 차이를 허용하되 회전·반전이 더 잘 맞으면 실패한다.
        XCTAssertGreaterThanOrEqual(scores[0] + 0.02, best, "\(label): orientation scores \(scores)")
    }

    private func lumaMap(_ image: CIImage) -> [Double] {
        let side = 64
        let scaled = image.transformed(by: CGAffineTransform(
            scaleX: CGFloat(side) / image.extent.width, y: CGFloat(side) / image.extent.height))
        let origin = scaled.transformed(by: CGAffineTransform(translationX: -scaled.extent.minX, y: -scaled.extent.minY))
        var pixels = [Float](repeating: 0, count: side * side * 4)
        ChromabaseEngine.sharedLinearRenderContext.render(origin, toBitmap: &pixels, rowBytes: side * 16,
                           bounds: CGRect(x: 0, y: 0, width: side, height: side), format: .RGBAf,
                           colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
        return (0..<(side * side)).map { Double(pixels[$0 * 4] + pixels[$0 * 4 + 1] + pixels[$0 * 4 + 2]) }
    }

    private func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let ma = a.reduce(0, +) / Double(a.count), mb = b.reduce(0, +) / Double(b.count)
        var num = 0.0, da = 0.0, db = 0.0
        for i in a.indices { num += (a[i] - ma) * (b[i] - mb); da += (a[i] - ma) * (a[i] - ma); db += (b[i] - mb) * (b[i] - mb) }
        return num / max(1e-12, (da * db).squareRoot())
    }

    /// 디코드가 끝난 뒤(마스터 캐시 적중) 현상 패스 하나에 드는 시간을 구성 요소별로 나눈다.
    func testRenderPassBreakdown() async throws {
        guard let list = ProcessInfo.processInfo.environment["NEGAFLOW_RAW_TIMING_FILES"],
              NativeCameraRAW.isAvailable else {
            throw XCTSkip("NEGAFLOW_RAW_TIMING_FILES and NEGAFLOW_LIBRAW_LIBRARY are required")
        }
        for path in list.split(separator: ":") {
            let url = URL(fileURLWithPath: String(path))
            let (model, root) = try await makeModel()
            defer { try? FileManager.default.removeItem(at: root) }
            let frame = ScanFrame(scanIndex: 1, rawScanURL: url, filmType: .colorNegative, sourceKind: .importedFile)
            model.frames = [frame]
            XCTAssertTrue(model.assignNewPersistentFrames([frame]))
            model.activateFrame(frame.id)
            await model.selectedFrameDevelopTask?.value
            let key = FilmBaseCacheKey(filmType: frame.filmType, mode: frame.params.baseEstimationMode,
                manualBaseRGB: frame.params.manualBaseRGB, filmStockDminID: frame.params.filmStockDminID,
                lightSourceProfileID: frame.params.lightSourceProfileID, imageTransform: frame.imageTransform)
            func time(_ label: String, dimension: CGFloat, raw: Bool, thumb: Bool) throws {
                var snapshot = model.makeSnapshot(for: frame, baseKey: key, needsRawPreview: raw,
                    needsNeutralPreview: false, needsDebugPreviews: false, needsThumbnail: thumb,
                    proxyMaxDimension: dimension)
                snapshot.preloadedPreviewRaw = nil
                snapshot.preloadedFullPreviewRaw = nil
                let context = DevelopFrameRenderer.renderContext()
                var start = Date()
                _ = try DevelopFrameRenderer.resolveRenderInput(snapshot, engine: ChromabaseEngine(), context: context)
                let input = -start.timeIntervalSinceNow
                start = Date()
                _ = try DevelopFrameRenderer.render(snapshot)
                print(String(format: "[raw-pass] %@ %@ input %.0f ms render %.0f ms", url.lastPathComponent, label,
                             input * 1000, -start.timeIntervalSinceNow * 1000))
            }
            for _ in 0..<2 {
                try time("2560 thumb", dimension: 2560, raw: false, thumb: true)
                try time("2560 bare", dimension: 2560, raw: false, thumb: false)
                try time("3600 raw+thumb", dimension: 3600, raw: true, thumb: true)
                try time("3600 bare", dimension: 3600, raw: false, thumb: false)
            }
        }
    }

    private func makeModel() async throws -> (AppModel, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("raw-timing-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = AppModel(libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups"))
        await model.restoreLibraryOnLaunch()
        model.activeWorkspaceModule = .develop
        model.canvasDisplayTargetPixels = 2_560
        return (model, root)
    }

    /// 조건이 참이 될 때까지 기다리고 `start` 부터 걸린 초를 돌려준다.
    private func wait(since start: Date, _ condition: () -> Bool) async throws -> TimeInterval {
        while !condition() {
            guard -start.timeIntervalSinceNow < 180 else {
                throw NSError(domain: "CameraRAWTimingDiagnosticsTests", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for the app pipeline"])
            }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        return -start.timeIntervalSinceNow
    }
}
