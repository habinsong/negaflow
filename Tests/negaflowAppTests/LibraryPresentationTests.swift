import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Chromabase
@testable import negaflowApp

@MainActor
final class LibraryPresentationTests: XCTestCase {
    func testImportedFrameDisplayNamePrefersFileNameAndSupportsRename() {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow/roll-a/Color 001.tif"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )

        XCTAssertEqual(frame.displayName(language: .korean), "Color 001")
        XCTAssertEqual(frame.sourceFileNameWithExtension, "Color 001.tif")

        frame.renameDisplayName(to: "First keeper")

        XCTAssertEqual(frame.displayName(language: .english), "First keeper")
    }

    func testFolderSectionsIncludeRegisteredEmptyFoldersAndImportedFiles() {
        let model = AppModel()
        let folder = URL(fileURLWithPath: "/tmp/negaflow/library/roll-a", isDirectory: true)
        let empty = URL(fileURLWithPath: "/tmp/negaflow/library/empty-roll", isDirectory: true)
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: folder.appendingPathComponent("scan-a.tif"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )

        model.registerLibraryFolder(folder)
        model.registerLibraryFolder(empty)
        model.frames = [frame]

        let sections = LibraryPresentation.folderSections(
            frames: model.frames,
            folders: model.libraryFolders,
            sortKey: .inputOrder,
            ascending: true
        )

        XCTAssertEqual(sections.map(\.title), ["empty-roll", "roll-a"])
        XCTAssertEqual(sections.first { $0.title == "empty-roll" }?.frames.count, 0)
        XCTAssertEqual(sections.first { $0.title == "roll-a" }?.frames.map(\.sourceFileNameWithExtension), ["scan-a.tif"])
    }

    func testLibrarySortingCoversInputNameRatingAndFlagOrder() {
        let first = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/b.tif"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        let second = ScanFrame(
            scanIndex: 2,
            rawScanURL: URL(fileURLWithPath: "/tmp/a.tif"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        let third = ScanFrame(
            scanIndex: 3,
            rawScanURL: URL(fileURLWithPath: "/tmp/c.tif"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        first.setRating(2)
        second.setRating(5)
        third.pickState = .picked

        let frames = [first, second, third]

        XCTAssertEqual(
            LibraryPresentation.sortedFrames(frames, key: .inputOrder, ascending: true).map(\.id),
            [first.id, second.id, third.id]
        )
        XCTAssertEqual(
            LibraryPresentation.sortedFrames(frames, key: .name, ascending: true).map(\.id),
            [second.id, first.id, third.id]
        )
        XCTAssertEqual(
            LibraryPresentation.sortedFrames(frames, key: .rating, ascending: false).map(\.id),
            [second.id, first.id, third.id]
        )
        XCTAssertEqual(
            LibraryPresentation.sortedFrames(frames, key: .flag, ascending: true).map(\.id).first,
            third.id
        )
    }

    func testProjectedFolderSectionsKeepHeadersAndUseResultOrder() {
        let folderURL = URL(fileURLWithPath: "/tmp/negaflow/library/projected", isDirectory: true)
        let emptyURL = URL(fileURLWithPath: "/tmp/negaflow/library/empty", isDirectory: true)
        let first = ScanFrame(
            scanIndex: 1,
            rawScanURL: folderURL.appendingPathComponent("first.tif"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        let second = ScanFrame(
            scanIndex: 2,
            rawScanURL: folderURL.appendingPathComponent("second.tif"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        let sections = LibraryPresentation.folderSections(
            frames: [first, second],
            folders: [LibraryFolder(url: folderURL), LibraryFolder(url: emptyURL)],
            sortKey: .inputOrder,
            ascending: true
        )

        let projected = LibraryPresentation.projectedFolderSections(
            sections,
            orderedFrameIDs: [second.id, first.id, second.id]
        )

        XCTAssertEqual(projected.map(\.title), ["empty", "projected"])
        XCTAssertTrue(projected[0].frames.isEmpty)
        XCTAssertEqual(projected[1].frames.map(\.id), [second.id, first.id])
    }

    func testVisibleFolderSectionsCanRestrictDevelopSidebarToSelectedFolder() {
        let sections = [
            LibraryFolderSection(id: "/roll/a", folder: nil, title: "A", frames: []),
            LibraryFolderSection(id: "/roll/b", folder: nil, title: "B", frames: []),
        ]

        XCTAssertEqual(
            LibraryPresentation.visibleFolderSections(sections, restrictedTo: nil).map(\.id),
            ["/roll/a", "/roll/b"]
        )
        XCTAssertEqual(
            LibraryPresentation.visibleFolderSections(
                sections,
                restrictedTo: ["/roll/b"]
            ).map(\.id),
            ["/roll/b"]
        )
        XCTAssertTrue(
            LibraryPresentation.visibleFolderSections(
                sections,
                restrictedTo: []
            ).isEmpty
        )
    }

    func testFilmTypeViewFiltersByStorageFolderAndKeepsIndividualFilmFolders() {
        let root = URL(fileURLWithPath: "/Volumes/Scans/20260724", isDirectory: true)
        let colorFolder = root
            .appendingPathComponent("color-negative", isDirectory: true)
            .appendingPathComponent("Portra 400", isDirectory: true)
        let secondColorFolder = root
            .appendingPathComponent("color-negative", isDirectory: true)
            .appendingPathComponent("Gold 200", isDirectory: true)
        let slideFolder = root
            .appendingPathComponent("color-slide", isDirectory: true)
            .appendingPathComponent("Velvia 50", isDirectory: true)
        let color = ScanFrame(
            scanIndex: 1,
            rawScanURL: colorFolder.appendingPathComponent("one.tiff"),
            filmType: .bwNegative
        )
        let secondColor = ScanFrame(
            scanIndex: 2,
            rawScanURL: secondColorFolder.appendingPathComponent("two.tiff"),
            filmType: .colorPositive
        )
        let slide = ScanFrame(
            scanIndex: 3,
            rawScanURL: slideFolder.appendingPathComponent("three.tiff"),
            filmType: .colorNegative
        )
        let imported = ScanFrame(
            scanIndex: 4,
            rawScanURL: URL(fileURLWithPath: "/Volumes/Imports/four.tiff"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        let frames = [color, secondColor, slide, imported]
        let framesByID = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0) })

        let colorIDs = LibraryPresentation.frameIDs(
            frames.map(\.id),
            storedUnder: .colorNegative,
            framesByID: framesByID
        )

        XCTAssertEqual(colorIDs, [color.id, secondColor.id])

        let projection = LibraryBrowserProjection(
            contextGeneration: 1,
            sourceCount: 2,
            matchedCount: 2,
            orderedFrameIDs: colorIDs,
            folderSections: [
                .init(
                    id: colorFolder.path,
                    folderID: nil,
                    title: "Portra 400",
                    orderedFrameIDs: [color.id]
                ),
                .init(
                    id: secondColorFolder.path,
                    folderID: nil,
                    title: "Gold 200",
                    orderedFrameIDs: [secondColor.id]
                ),
                .init(
                    id: slideFolder.path,
                    folderID: nil,
                    title: "Velvia 50",
                    orderedFrameIDs: []
                ),
            ],
            queryWasValid: true
        ).restrictingFolderSections(toStoredFilmType: .colorNegative)

        XCTAssertEqual(
            projection.folderSections.map(\.title),
            ["Portra 400", "Gold 200"]
        )
    }

    func testRatingButtonSelectionClearsWhenSameValueIsChosenAgain() {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow/rating-toggle.tif"),
            filmType: .colorNegative
        )

        frame.toggleRating(5)
        XCTAssertEqual(frame.rating, 5)

        frame.toggleRating(5)
        XCTAssertEqual(frame.rating, 0)

        frame.toggleRating(3)
        XCTAssertEqual(frame.rating, 3)

        frame.toggleRating(4)
        XCTAssertEqual(frame.rating, 4)
    }

    func testBrowserInteractionScopeUsesProjectedFolderWithoutPromotingAnotherFolder() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let projection = LibraryBrowserProjection(
            contextGeneration: 4,
            sourceCount: 3,
            matchedCount: 3,
            orderedFrameIDs: [thirdID, firstID, secondID],
            folderSections: [
                LibraryBrowserFolderSection(
                    id: "folder-a",
                    folderID: nil,
                    title: "A",
                    orderedFrameIDs: [firstID, secondID]
                ),
                LibraryBrowserFolderSection(
                    id: "folder-b",
                    folderID: nil,
                    title: "B",
                    orderedFrameIDs: [thirdID]
                ),
            ],
            queryWasValid: true
        )

        XCTAssertEqual(
            LibraryBrowserInteractionScope.frameIDs(
                viewMode: .all,
                selectedFolderID: "folder-a",
                selectedFrameID: firstID,
                projection: projection
            ),
            [thirdID, firstID, secondID]
        )
        XCTAssertEqual(
            LibraryBrowserInteractionScope.frameIDs(
                viewMode: .folders,
                selectedFolderID: "folder-b",
                selectedFrameID: firstID,
                projection: projection
            ),
            [thirdID]
        )
        XCTAssertEqual(
            LibraryBrowserInteractionScope.frameIDs(
                viewMode: .filmType,
                selectedFolderID: "folder-a",
                selectedFrameID: thirdID,
                projection: projection
            ),
            [firstID, secondID]
        )
        XCTAssertEqual(
            LibraryBrowserInteractionScope.frameIDs(
                viewMode: .folders,
                selectedFolderID: nil,
                selectedFrameID: secondID,
                projection: projection
            ),
            [firstID, secondID]
        )
        XCTAssertTrue(
            LibraryBrowserInteractionScope.frameIDs(
                viewMode: .folders,
                selectedFolderID: "missing-folder",
                selectedFrameID: thirdID,
                projection: projection
            ).isEmpty
        )
    }

    func testDuplicateFrameIdentifiersFailClosedInPresentation() {
        let duplicateID = UUID()
        let first = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/duplicate-a.tif"),
            filmType: .colorNegative,
            sourceKind: .importedFile,
            id: duplicateID
        )
        let second = ScanFrame(
            scanIndex: 2,
            rawScanURL: URL(fileURLWithPath: "/tmp/duplicate-b.tif"),
            filmType: .colorNegative,
            sourceKind: .importedFile,
            id: duplicateID
        )

        XCTAssertTrue(
            LibraryPresentation.sortedFrames(
                [first, second],
                key: .inputOrder,
                ascending: true
            ).isEmpty
        )
        XCTAssertTrue(
            LibraryPresentation.folderSections(
                frames: [first, second],
                folders: [],
                sortKey: .inputOrder,
                ascending: true
            ).isEmpty
        )
    }

    func testLibrarySearchSymbolsExist() {
        let symbols = [
            "magnifyingglass", "xmark.circle.fill", "film", "flag.fill",
            "xmark.octagon.fill", "externaldrive.badge.questionmark", "wave.3.right",
            "bandage", "checkmark.seal", "doc.questionmark",
            "line.3.horizontal.decrease.circle", "exclamationmark.circle",
        ]

        for symbol in symbols {
            XCTAssertNotNil(
                NSImage(systemSymbolName: symbol, accessibilityDescription: nil),
                "Missing SF Symbol: \(symbol)"
            )
        }
    }

    func testFileSizeSortUsesCatalogSnapshotAndKeepsUnknownSizesLast() {
        let small = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/small.tif"),
            filmType: .colorNegative,
            sourceKind: .importedFile,
            sourceMetadata: SourceMetadataSnapshot(fileSizeBytes: 100)
        )
        let unknown = ScanFrame(
            scanIndex: 2,
            rawScanURL: URL(fileURLWithPath: "/offline/unknown.tif"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        let large = ScanFrame(
            scanIndex: 3,
            rawScanURL: URL(fileURLWithPath: "/offline/large.tif"),
            filmType: .colorNegative,
            sourceKind: .importedFile,
            sourceMetadata: SourceMetadataSnapshot(fileSizeBytes: 200)
        )

        XCTAssertEqual(
            LibraryPresentation.sortedFrames(
                [small, unknown, large],
                key: .fileSize,
                ascending: true
            ).map(\.id),
            [small.id, large.id, unknown.id]
        )
        XCTAssertEqual(
            LibraryPresentation.sortedFrames(
                [small, unknown, large],
                key: .fileSize,
                ascending: false
            ).map(\.id),
            [large.id, small.id, unknown.id]
        )
    }

    // 라이브러리/필름스트립 카드 모두 썸네일(네거티브는 최초부터 현상본)을 우선하고,
    // 썸네일이 아직 없을 때만 원본 프리뷰로 대체한다(Lightroom 방식 디스크 캐시와 동일 상태).
    func testFrameStripPresentationPrefersThumbnailWithoutVisibleSubtitle() {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negative.tif"),
            filmType: .colorNegative,
            sourceKind: .scannerTIFF
        )
        let raw = NSImage(size: NSSize(width: 2, height: 2))
        let thumbnail = NSImage(size: NSSize(width: 3, height: 3))
        frame.rawPreviewImage = raw
        frame.thumbnailImage = thumbnail
        frame.developedImage = thumbnail

        XCTAssertNil(FrameStripPresentationMode.raw.subtitle(for: frame, language: .korean))
        XCTAssertTrue(FrameStripPresentationMode.raw.previewImage(for: frame) === thumbnail)
        XCTAssertTrue(FrameStripPresentationMode.developed.previewImage(for: frame) === thumbnail)

        frame.thumbnailImage = nil
        frame.developedImage = nil
        XCTAssertNil(FrameStripPresentationMode.raw.previewImage(for: frame))
    }

    func testNegativeInitialThumbnailIsFirstPublishedByPositiveDevelopment() async throws {
        let model = AppModel()
        let url = try Self.writeSyntheticPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        for (index, filmType) in [FilmType.colorNegative, .bwNegative].enumerated() {
            let frame = ScanFrame(
                scanIndex: index + 1,
                rawScanURL: url,
                filmType: filmType,
                sourceKind: .importedFile
            )
            model.frames = [frame]

            model.seedInitialThumbnail(for: frame, from: url)
            if let seed = frame.initialThumbnailSeedTask { await seed.value }

            XCTAssertNotNil(frame.rawPreviewImage)
            XCTAssertNil(frame.thumbnailImage, "\(filmType) must never publish the raw negative as a thumbnail")
            XCTAssertNil(FrameStripPresentationMode.raw.previewImage(for: frame))

            await model.developFrameAfterFastPreview(frame)

            XCTAssertTrue(frame.hasDevelopedOnce)
            XCTAssertNotNil(frame.thumbnailImage)
            XCTAssertFalse(frame.thumbnailImage === frame.rawPreviewImage)
            XCTAssertTrue(
                FrameStripPresentationMode.developed.previewImage(for: frame) === frame.thumbnailImage
            )
        }
    }

    func testPositiveInitialThumbnailCanUseOriginalImage() async throws {
        let model = AppModel()
        let url = try Self.writeSyntheticPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        let frame = ScanFrame(
            scanIndex: 1, rawScanURL: url, filmType: .colorPositive, sourceKind: .importedFile
        )
        model.frames = [frame]

        model.seedInitialThumbnail(for: frame, from: url)
        if let seed = frame.initialThumbnailSeedTask { await seed.value }

        XCTAssertNotNil(frame.thumbnailImage)
        XCTAssertTrue(frame.thumbnailImage === frame.rawPreviewImage)
    }

    // 첫/복원 썸네일은 원본 픽셀(변형 전)이라, 프레임 방향 변형을 적용해 현상 결과와 방향을 맞춘다.
    // (회귀 방지: 시드가 변형을 빼먹으면 스캔 방향 템플릿이 걸린 프레임에서 썸네일이 180°/90° 어긋남.)
    func testOrientedThumbnailAppliesFrameTransform() throws {
        let cg = try Self.makeSyntheticCGImage(width: 8, height: 4)

        // identity → 무연산(동일 인스턴스 반환).
        XCTAssertTrue(AppModel.orientedThumbnail(cg, transform: .identity) === cg)

        // deg90 → 가로/세로 스왑(변형이 실제로 적용됨).
        let rotated90 = AppModel.orientedThumbnail(cg, transform: ImageTransform(rotation: .deg90))
        XCTAssertEqual(rotated90.width, 4)
        XCTAssertEqual(rotated90.height, 8)

        // deg180 → 크기 유지(사용자가 겪은 실제 시나리오).
        let rotated180 = AppModel.orientedThumbnail(cg, transform: ImageTransform(rotation: .deg180))
        XCTAssertEqual(rotated180.width, 8)
        XCTAssertEqual(rotated180.height, 4)
    }

    private static func makeSyntheticCGImage(width: Int, height: Int) throws -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(ctx.makeImage())
    }

    private static func writeSyntheticPNG(width: Int = 8, height: Int = 8) throws -> URL {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(ctx.makeImage())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-seed-\(UUID().uuidString).png")
        let dest = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }
}
