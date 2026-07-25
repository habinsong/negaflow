import XCTest
import Chromabase
import ScannerKit
@testable import negaflowApp

@MainActor
final class LibraryCatalogHealthTests: XCTestCase {
    func testOfflineSourcesAndFoldersAreWarningsNotDataCorruption() {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/missing/roll/frame.tiff"),
            filmType: .colorNegative,
            infraredScanURL: URL(fileURLWithPath: "/missing/roll/frame-ir.tiff")
        )
        let catalog = LibraryCatalog(
            folders: ["/missing/roll"],
            frames: [LibraryFrameRecord(frame: frame)]
        )

        let report = LibraryCatalogHealthInspector.inspect(catalog)

        XCTAssertTrue(report.canOpenSafely)
        XCTAssertEqual(report.errorCount, 0)
        XCTAssertTrue(report.issues.contains { $0.code == .offlineFolder })
        XCTAssertTrue(report.issues.contains { $0.code == .offlineSource })
        XCTAssertTrue(report.issues.contains { $0.code == .offlineInfraredSource })
    }

    func testSafetyOnlyInspectionSkipsWarningsButPreservesErrors() {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/missing/roll/frame.tiff"),
            filmType: .colorNegative
        )
        var record = LibraryFrameRecord(frame: frame)
        record.rating = 9
        let catalog = LibraryCatalog(
            folders: ["/missing/roll"],
            frames: [record]
        )

        let report = LibraryCatalogHealthInspector.inspect(catalog, includeWarnings: false)

        XCTAssertFalse(report.canOpenSafely)
        XCTAssertEqual(report.warningCount, 0)
        XCTAssertTrue(report.issues.contains {
            $0.code == .invalidRating && $0.severity == .error
        })
        XCTAssertFalse(report.issues.contains {
            $0.code == .offlineFolder || $0.code == .offlineSource
        })

        var validRecord = record
        validRecord.rating = 0
        let validCatalog = LibraryCatalog(
            folders: ["/missing/roll"],
            frames: [validRecord]
        )
        let incrementallyChecked = LibraryCatalogHealthInspector.inspect(
            catalog,
            includeWarnings: false,
            validatedPreviousCatalog: validCatalog
        )
        XCTAssertFalse(incrementallyChecked.canOpenSafely)
        XCTAssertTrue(incrementallyChecked.issues.contains { $0.code == .invalidRating })

        var brokenGlobalState = validCatalog
        brokenGlobalState.rolls = []
        let globalCheck = LibraryCatalogHealthInspector.inspect(
            brokenGlobalState,
            includeWarnings: false,
            validatedPreviousCatalog: validCatalog
        )
        XCTAssertFalse(globalCheck.canOpenSafely)
        XCTAssertTrue(globalCheck.issues.contains { $0.code == .frameMissingRollMembership })
    }

    func testDuplicateIDsAndMalformedRequiredFieldsAreErrors() {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/frame.tiff"),
            filmType: .colorNegative
        )
        var first = LibraryFrameRecord(frame: frame)
        first.sourceKind = "unknown"
        first.rating = 9
        first.baseRGB = [0.5, 0.4]
        var second = first
        second.rawScanPath = ""
        let catalog = LibraryCatalog(frames: [first, second])

        let report = LibraryCatalogHealthInspector.inspect(catalog)
        let codes = Set(
            report.issues
                .filter { $0.severity == .error }
                .map(\.code)
        )

        XCTAssertFalse(report.canOpenSafely)
        XCTAssertTrue(codes.contains(.duplicateFrameID))
        XCTAssertTrue(codes.contains(.emptySourcePath))
        XCTAssertTrue(codes.contains(.unsupportedSourceKind))
        XCTAssertTrue(report.issues.contains {
            $0.code == .invalidRating && $0.severity == .error
        })
        XCTAssertTrue(report.issues.contains {
            $0.code == .invalidBaseRGB && $0.severity == .warning
        })
    }

    func testLegacyDefectFieldsNeverBlockCatalogOpen() throws {
        // 결함 기록/캐시는 세션 전용이 됐다 — legacy catalog의 hasDefectEdits/cleanedRawPath는
        // 잔재 파일이 전혀 없어도 catalog 열기를 막지 않는다.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-health-defects-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let missingFrame = makeFrame(index: 1)
        let foreignFrame = makeFrame(index: 2)
        var missingRecord = LibraryFrameRecord(frame: missingFrame)
        missingRecord.hasDefectEdits = true
        var foreignRecord = LibraryFrameRecord(frame: foreignFrame)
        foreignRecord.hasDefectEdits = true
        foreignRecord.cleanedRawPath = "/tmp/user-owned-photo.tiff"

        let report = LibraryCatalogHealthInspector.inspect(
            LibraryCatalog(frames: [missingRecord, foreignRecord]),
            defectDirectory: root
        )

        XCTAssertTrue(report.canOpenSafely)
        XCTAssertFalse(report.issues.contains { $0.code == .missingDefectRecipe })
        XCTAssertFalse(report.issues.contains { $0.code == .invalidDefectRecipe })
        XCTAssertFalse(report.issues.contains { $0.code == .invalidCleanedRawCachePath })
        XCTAssertFalse(report.issues.contains { $0.code == .missingCleanedRawCache })
    }

    func testBrokenVirtualCopyRelationshipIsReportedWithoutDroppingFrame() {
        let frame = makeFrame(index: 1)
        var missingSource = LibraryFrameRecord(frame: frame)
        missingSource.sourceFrameID = UUID()
        missingSource.virtualCopyNumber = 2
        let report = LibraryCatalogHealthInspector.inspect(
            LibraryCatalog(frames: [missingSource])
        )

        XCTAssertTrue(report.canOpenSafely)
        XCTAssertTrue(report.issues.contains { $0.code == .missingVirtualCopySource })

        missingSource.sourceFrameID = frame.id
        let selfReference = LibraryCatalogHealthInspector.inspect(
            LibraryCatalog(frames: [missingSource])
        )
        XCTAssertTrue(selfReference.canOpenSafely)
        XCTAssertTrue(selfReference.issues.contains {
            $0.code == .selfReferentialVirtualCopy && $0.severity == .warning
        })
    }

    func testLegacyFrameWithoutSourceMetadataRemainsSafe() {
        let frame = makeFrame(index: 1)
        var record = LibraryFrameRecord(frame: frame)
        record.sourceKind = FrameSource.importedFile.storageKey
        record.sourcePixelWidth = 4_000
        record.sourcePixelHeight = 6_000
        record.sourceResolutionDPI = 2_400
        record.sourceBitDepth = 16
        record.sourceMetadata = nil

        let report = inspectRecords([record])

        XCTAssertTrue(report.canOpenSafely)
        XCTAssertFalse(report.issues.contains {
            $0.code == .unsupportedSourceMetadataVersion
                || $0.code == .invalidSourceMetadata
        })
    }

    func testUnsupportedSourceMetadataVersionFailsClosed() {
        var metadata = SourceMetadataSnapshot(fileSizeBytes: 1_024)
        metadata.version = SourceMetadataSnapshot.currentVersion + 1

        let report = inspectMetadata(metadata)

        XCTAssertFalse(report.canOpenSafely)
        XCTAssertTrue(report.issues.contains {
            $0.code == .unsupportedSourceMetadataVersion
                && $0.severity == .error
        })
        XCTAssertFalse(report.issues.contains { $0.code == .invalidSourceMetadata })
    }

    func testInvalidSourceMetadataScalarsFailClosed() {
        var zeroFileSize = SourceMetadataSnapshot()
        zeroFileSize.fileSizeBytes = 0
        var negativeImageIndex = SourceMetadataSnapshot()
        negativeImageIndex.imageIndex = -1
        var imageIndexOutsideImageCount = SourceMetadataSnapshot()
        imageIndexOutsideImageCount.imageIndex = 1
        imageIndexOutsideImageCount.imageCount = 1
        var zeroDPI = SourceMetadataSnapshot()
        zeroDPI.dpiWidth = 0
        var invalidOrientation = SourceMetadataSnapshot()
        invalidOrientation.orientation = 9

        for (index, metadata) in [
            zeroFileSize,
            negativeImageIndex,
            imageIndexOutsideImageCount,
            zeroDPI,
            invalidOrientation,
        ].enumerated() {
            let report = inspectMetadata(metadata)
            XCTAssertFalse(report.canOpenSafely, "invalid scalar case \(index)")
            XCTAssertTrue(
                report.issues.contains {
                    $0.code == .invalidSourceMetadata && $0.severity == .error
                },
                "invalid scalar case \(index)"
            )
        }
    }

    func testSourceMetadataStringAndListBoundariesAreEnforced() {
        let maximumText = String(
            repeating: "a",
            count: SourceMetadataReader.maximumTextLength
        )
        var maximumString = SourceMetadataSnapshot()
        maximumString.colorModel = maximumText
        XCTAssertFalse(inspectMetadata(maximumString).issues.contains {
            $0.code == .invalidSourceMetadata
        })

        var oversizedString = maximumString
        oversizedString.colorModel = maximumText + "a"
        XCTAssertTrue(inspectMetadata(oversizedString).issues.contains {
            $0.code == .invalidSourceMetadata && $0.severity == .error
        })

        let maximumKeywords = Array(
            repeating: "film",
            count: SourceMetadataReader.maximumListCount
        )
        var maximumList = SourceMetadataSnapshot()
        maximumList.iptc = makeIPTC(keywords: maximumKeywords)
        XCTAssertFalse(inspectMetadata(maximumList).issues.contains {
            $0.code == .invalidSourceMetadata
        })

        var oversizedList = maximumList
        oversizedList.iptc = makeIPTC(keywords: maximumKeywords + ["overflow"])
        XCTAssertTrue(inspectMetadata(oversizedList).issues.contains {
            $0.code == .invalidSourceMetadata && $0.severity == .error
        })
    }

    func testSourceMetadataEncodedSizeLimitFailsClosed() throws {
        let text = String(
            repeating: "x",
            count: SourceMetadataReader.maximumTextLength
        )
        let entryCount = SourceMetadataReader.maximumEncodedSnapshotBytes
            / SourceMetadataReader.maximumTextLength + 2
        let values = Dictionary(uniqueKeysWithValues: (0..<entryCount).map {
            ("lang-\($0)", text)
        })
        var metadata = SourceMetadataSnapshot()
        metadata.imageMetadataXMPView = makeXMP(
            title: SourceLocalizedText(valuesByLanguage: values)
        )

        XCTAssertLessThanOrEqual(values.count, SourceMetadataReader.maximumListCount)
        XCTAssertGreaterThan(
            try JSONEncoder().encode(metadata).count,
            SourceMetadataReader.maximumEncodedSnapshotBytes
        )
        let report = inspectMetadata(metadata)
        XCTAssertFalse(report.canOpenSafely)
        XCTAssertTrue(report.issues.contains {
            $0.code == .invalidSourceMetadata && $0.severity == .error
        })
    }

    func testSidecarMetadataRequiresLoadedReadState() {
        var metadata = SourceMetadataSnapshot()
        metadata.sidecarXMP = makeXMP(rating: 4)
        metadata.sidecarXMPState = .notFound

        let inconsistent = inspectMetadata(metadata)
        XCTAssertFalse(inconsistent.canOpenSafely)
        XCTAssertTrue(inconsistent.issues.contains {
            $0.code == .invalidSourceMetadata && $0.severity == .error
        })

        metadata.sidecarXMPState = .loaded
        metadata.sidecarXMPFileSHA256 = String(repeating: "a", count: 64)
        let loaded = inspectMetadata(metadata)
        XCTAssertTrue(loaded.canOpenSafely)
        XCTAssertFalse(loaded.issues.contains { $0.code == .invalidSourceMetadata })
    }

    func testVirtualCopyMetadataMustMatchRootSnapshot() {
        let root = makeFrame(index: 1)
        let virtualCopy = root.makeVirtualCopy(copyNumber: 1)
        let metadata = SourceMetadataSnapshot(
            fileTypeIdentifier: "public.tiff",
            fileSizeBytes: 1_024,
            pixelWidth: 4_000,
            pixelHeight: 6_000,
            bitsPerColorSample: 16
        )
        var rootRecord = LibraryFrameRecord(frame: root)
        rootRecord.sourceMetadata = metadata
        var copyRecord = LibraryFrameRecord(frame: virtualCopy)
        copyRecord.sourceMetadata = metadata

        let matching = inspectRecords([rootRecord, copyRecord])
        XCTAssertTrue(matching.canOpenSafely)
        XCTAssertFalse(matching.issues.contains {
            $0.code == .inconsistentVirtualCopyMetadata
        })

        copyRecord.sourceMetadata?.fileSizeBytes = 2_048
        let mismatched = inspectRecords([rootRecord, copyRecord])
        XCTAssertFalse(mismatched.canOpenSafely)
        XCTAssertTrue(mismatched.issues.contains {
            $0.code == .inconsistentVirtualCopyMetadata
                && $0.severity == .error
                && $0.frameID == virtualCopy.id
        })
    }

    func testScannerImageMetadataMayDifferFromManifestTechnicalFacts() throws {
        let workflow = try makeSucceededWorkflow()
        let imageMetadata = SourceMetadataSnapshot(
            fileTypeIdentifier: "public.tiff",
            fileSizeBytes: 4,
            imageCount: 1,
            pixelWidth: 20,
            pixelHeight: 16,
            resolutionDPI: 1_200,
            bitsPerColorSample: 8,
            orientation: 1,
            colorModel: "RGB"
        )
        var rootRecord = workflow.rootRecord
        rootRecord.sourceMetadata = imageMetadata
        var virtualRecord = workflow.virtualRecord
        virtualRecord.sourceMetadata = imageMetadata

        let report = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            frames: [rootRecord, virtualRecord],
            rolls: [workflow.roll],
            scanSessions: [workflow.session],
            scanRollAssignments: [workflow.assignment]
        ))

        XCTAssertTrue(report.canOpenSafely)
        XCTAssertFalse(report.issues.contains { $0.code == .invalidSourceMetadata })
        XCTAssertFalse(report.issues.contains { $0.code == .scanRootFrameCaptureMismatch })
    }

    func testPrepareForUseDoesNotOpenOrRewriteStructurallyUnsafeCatalog() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-health-open-\(UUID().uuidString)", isDirectory: true)
        let catalogURL = root.appendingPathComponent("library.json")
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let frame = makeFrame(index: 1)
        var record = LibraryFrameRecord(frame: frame)
        record.sourceKind = "not-supported"
        let data = try XCTUnwrap(
            LibraryCatalogFile.encode(LibraryCatalog(frames: [record]))
        )
        try data.write(to: catalogURL, options: .atomic)

        guard case let .blocked(reason) = LibraryCatalogFile.prepareForUse(
            at: catalogURL,
            defectDirectory: defects,
            backupDirectory: backups
        ) else {
            return XCTFail("unsafe catalog should block")
        }

        XCTAssertEqual(reason, .corrupt)
        XCTAssertEqual(try Data(contentsOf: catalogURL), data)
    }

    func testPrepareForUseOpensOfflineWarningCatalogWithoutChangingBytes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-health-offline-\(UUID().uuidString)", isDirectory: true)
        let catalogURL = root.appendingPathComponent("library.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: root.appendingPathComponent("offline.tiff"),
            filmType: .colorNegative
        )
        let data = try XCTUnwrap(
            LibraryCatalogFile.encode(
                LibraryCatalog(frames: [LibraryFrameRecord(frame: frame)])
            )
        )
        try data.write(to: catalogURL, options: .atomic)

        guard case let .loaded(_, recovered, migrated) = LibraryCatalogFile.prepareForUse(
            at: catalogURL,
            defectDirectory: root.appendingPathComponent("defects"),
            backupDirectory: root.appendingPathComponent("Backups")
        ) else {
            return XCTFail("offline warning should not block catalog")
        }

        XCTAssertFalse(recovered)
        XCTAssertNil(migrated)
        XCTAssertEqual(try Data(contentsOf: catalogURL), data)
    }

    func testPrepareForUsePreservesCatalogWithIsolatedStoredSearchDamage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-health-stored-search-\(UUID().uuidString)",
            isDirectory: true
        )
        let catalogURL = root.appendingPathComponent("library.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let rawPayload = #"{"version":1,"query":{"version":999}}"#
        let data = try XCTUnwrap(LibraryCatalogFile.encode(LibraryCatalog(
            savedSearches: [
                LibrarySavedSearch(
                    id: UUID(),
                    name: "Damaged",
                    definition: LibraryStoredSearchEnvelope(payloadJSON: rawPayload)
                ),
            ]
        )))
        try data.write(to: catalogURL, options: .atomic)

        guard case let .loaded(catalog, recovered, migrated) =
                LibraryCatalogFile.prepareForUse(
                    at: catalogURL,
                    defectDirectory: root.appendingPathComponent("defects"),
                    backupDirectory: root.appendingPathComponent("Backups")
                ) else {
            return XCTFail("isolated stored-search damage should not block catalog")
        }

        XCTAssertFalse(recovered)
        XCTAssertNil(migrated)
        XCTAssertEqual(catalog.savedSearches.first?.definition.payloadJSON, rawPayload)
        XCTAssertEqual(try Data(contentsOf: catalogURL), data)
    }

    func testHealthErrorPrimaryRecoversFromValidSnapshotAndPreservesBadBytes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-health-recovery-\(UUID().uuidString)", isDirectory: true)
        let catalogURL = root.appendingPathComponent("library.json")
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let healthyFrame = makeFrame(index: 1)
        let healthy = LibraryCatalog(
            folders: ["/healthy"],
            frames: [LibraryFrameRecord(frame: healthyFrame)]
        )
        try XCTUnwrap(LibraryCatalogFile.encode(healthy))
            .write(to: catalogURL, options: .atomic)
        _ = try LibraryBackupStore.createSnapshot(
            catalogURL: catalogURL,
            defectDirectory: defects,
            backupDirectory: backups
        )
        var brokenRecord = LibraryFrameRecord(frame: makeFrame(index: 2))
        brokenRecord.sourceKind = "unknown-source"
        let brokenData = try XCTUnwrap(
            LibraryCatalogFile.encode(LibraryCatalog(frames: [brokenRecord]))
        )
        try brokenData.write(to: catalogURL, options: .atomic)

        guard case let .loaded(restored, recovered, _) = LibraryCatalogFile.prepareForUse(
            at: catalogURL,
            defectDirectory: defects,
            backupDirectory: backups
        ) else {
            return XCTFail("valid snapshot should recover health error")
        }

        XCTAssertTrue(recovered)
        XCTAssertEqual(restored.folders, ["/healthy"])
        let preserved = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("library.corrupt-") }
        XCTAssertEqual(preserved.count, 1)
        XCTAssertEqual(try Data(contentsOf: preserved[0]), brokenData)
    }

    func testPhysicalRollMayBeEmptyAndCanBeActive() throws {
        let roll = try XCTUnwrap(LibraryRoll.physical(
            name: "Fresh Roll",
            createdAt: Date(timeIntervalSince1970: 10),
            filmType: .colorNegative
        ))
        let report = LibraryCatalogHealthInspector.inspect(
            LibraryCatalog(rolls: [roll], activeRollID: roll.id)
        )

        XCTAssertTrue(report.canOpenSafely)
        XCTAssertEqual(report.rollCount, 1)
        XCTAssertFalse(report.issues.contains { $0.rollID == roll.id })
    }

    func testRollMembershipMustReferenceEveryFrameExactlyOnce() throws {
        let first = makeFrame(index: 1)
        let second = makeFrame(index: 2)
        let firstRecord = LibraryFrameRecord(frame: first)
        let secondRecord = LibraryFrameRecord(frame: second)
        let physical = try XCTUnwrap(LibraryRoll.physical(
            name: "Roll",
            filmType: .colorNegative,
            frameIDs: [first.id, UUID()]
        ))
        let unassigned = LibraryRoll.unassigned(
            createdAt: Date(timeIntervalSince1970: 0),
            frameIDs: [first.id]
        )
        let report = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            frames: [firstRecord, secondRecord],
            rolls: [physical, unassigned]
        ))

        XCTAssertFalse(report.canOpenSafely)
        XCTAssertTrue(report.issues.contains {
            $0.code == .duplicateRollMembership && $0.frameID == first.id
        })
        XCTAssertTrue(report.issues.contains {
            $0.code == .frameMissingRollMembership && $0.frameID == second.id
        })
        XCTAssertTrue(report.issues.contains {
            $0.code == .rollReferencesMissingFrame && $0.rollID == physical.id
        })
    }

    func testRollIdentityAndActiveRollInvariantsFailClosed() throws {
        let duplicateID = UUID()
        let first = LibraryRoll(
            id: duplicateID,
            kind: .physical,
            name: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            filmType: nil,
            frameIDs: []
        )
        let second = LibraryRoll(
            id: duplicateID,
            kind: .physical,
            name: "Valid Name",
            createdAt: Date(timeIntervalSince1970: 2),
            filmType: .colorNegative,
            frameIDs: []
        )
        let malformedUnassigned = LibraryRoll(
            id: UUID(),
            kind: .unassigned,
            name: "Not Reserved",
            createdAt: Date(timeIntervalSince1970: 3),
            filmType: .bwNegative,
            frameIDs: []
        )
        let report = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            rolls: [first, second, malformedUnassigned],
            activeRollID: UUID()
        ))

        XCTAssertFalse(report.canOpenSafely)
        XCTAssertTrue(report.issues.contains { $0.code == .duplicateRollID })
        XCTAssertTrue(report.issues.contains { $0.code == .invalidPhysicalRoll })
        XCTAssertTrue(report.issues.contains { $0.code == .invalidUnassignedRoll })
        XCTAssertTrue(report.issues.contains { $0.code == .missingActiveRoll })

        let reserved = LibraryRoll.unassigned(
            createdAt: Date(timeIntervalSince1970: 4),
            frameIDs: []
        )
        let activeUnassigned = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            rolls: [reserved],
            activeRollID: reserved.id
        ))
        XCTAssertFalse(activeUnassigned.canOpenSafely)
        XCTAssertTrue(activeUnassigned.issues.contains {
            $0.code == .activeRollNotPhysical && $0.rollID == reserved.id
        })
    }

    func testVirtualCopyFamilyCannotBeSplitAcrossRolls() throws {
        let original = makeFrame(index: 1)
        let copy = original.makeVirtualCopy(copyNumber: 1)
        let firstRoll = try XCTUnwrap(LibraryRoll.physical(
            name: "Roll A",
            filmType: .colorNegative,
            frameIDs: [original.id]
        ))
        let secondRoll = try XCTUnwrap(LibraryRoll.physical(
            name: "Roll B",
            filmType: .colorNegative,
            frameIDs: [copy.id]
        ))
        let records = [LibraryFrameRecord(frame: original), LibraryFrameRecord(frame: copy)]

        let split = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            frames: records,
            rolls: [firstRoll, secondRoll]
        ))
        XCTAssertFalse(split.canOpenSafely)
        XCTAssertTrue(split.issues.contains {
            $0.code == .splitVirtualCopyFamily && $0.frameID == copy.id
        })

        var joinedRoll = firstRoll
        joinedRoll.frameIDs = [original.id, copy.id]
        let joined = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            frames: records,
            rolls: [joinedRoll]
        ))
        XCTAssertTrue(joined.canOpenSafely)
        XCTAssertFalse(joined.issues.contains { $0.code == .splitVirtualCopyFamily })
    }

    func testQueuedFullSessionMayReserveRollBeforeFirstSuccess() throws {
        let workflow = try makeQueuedWorkflow()
        let catalog = LibraryCatalog(
            scanSessions: [workflow.session],
            scanRollAssignments: [workflow.assignment]
        )

        let report = LibraryCatalogHealthInspector.inspect(catalog)

        XCTAssertTrue(report.canOpenSafely)
        XCTAssertTrue(catalog.rolls.isEmpty)
    }

    func testPersistedScanSessionMustContainAtLeastOneJob() throws {
        let sessionID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let session = try makeSession(id: sessionID, createdAt: createdAt, jobs: [])
        let assignment = LibraryScanRollAssignment(
            sessionID: sessionID,
            rollID: UUID(),
            draftName: "Empty Session",
            filmType: .colorNegative,
            createdAt: createdAt
        )

        let report = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            scanSessions: [session],
            scanRollAssignments: [assignment]
        ))

        XCTAssertFalse(report.canOpenSafely)
        XCTAssertTrue(report.issues.contains {
            $0.code == .emptyScanSession && $0.sessionID == sessionID
        })
    }

    func testSucceededFullJobAllowsExplicitlyRemovedRootButRequiresItsRoll() throws {
        let workflow = try makeSucceededWorkflow()
        let missingGeneration = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            scanSessions: [workflow.session],
            scanRollAssignments: [workflow.assignment]
        ))

        XCTAssertFalse(missingGeneration.canOpenSafely)
        XCTAssertTrue(missingGeneration.issues.contains {
            $0.code == .succeededScanRollMissing && $0.sessionID == workflow.session.id
        })
        XCTAssertTrue(missingGeneration.issues.contains {
            $0.code == .succeededScanJobMissingRootFrame
                && $0.severity == .warning
                && $0.jobID == workflow.jobID
        })

        var emptiedRoll = workflow.roll
        emptiedRoll.frameIDs = []
        let removedRoot = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            rolls: [emptiedRoll],
            scanSessions: [workflow.session],
            scanRollAssignments: [workflow.assignment]
        ))
        XCTAssertTrue(removedRoot.canOpenSafely)
        XCTAssertTrue(removedRoot.issues.contains {
            $0.code == .succeededScanJobMissingRootFrame && $0.severity == .warning
        })

        let complete = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            frames: [workflow.rootRecord, workflow.virtualRecord],
            rolls: [workflow.roll],
            scanSessions: [workflow.session],
            scanRollAssignments: [workflow.assignment]
        ))
        XCTAssertTrue(complete.canOpenSafely)

        var duplicateRoot = workflow.virtualRecord
        duplicateRoot.id = UUID()
        duplicateRoot.sourceFrameID = nil
        duplicateRoot.virtualCopyNumber = nil
        var rollWithDuplicate = workflow.roll
        rollWithDuplicate.frameIDs.append(duplicateRoot.id)
        let duplicate = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            frames: [workflow.rootRecord, duplicateRoot],
            rolls: [rollWithDuplicate],
            scanSessions: [workflow.session],
            scanRollAssignments: [workflow.assignment]
        ))
        XCTAssertFalse(duplicate.canOpenSafely)
        XCTAssertTrue(duplicate.issues.contains {
            $0.code == .succeededScanJobDuplicateRootFrame && $0.jobID == workflow.jobID
        })
    }

    func testFrameScanProvenanceMustBeCompleteAndReferenceSucceededFullJob() throws {
        let queued = try makeQueuedWorkflow()
        let frame = makeFrame(index: 1)
        var partial = LibraryFrameRecord(frame: frame)
        partial.scanSessionID = queued.session.id
        let roll = try XCTUnwrap(LibraryRoll.physical(
            id: queued.assignment.rollID,
            name: queued.assignment.draftName,
            filmType: queued.assignment.filmType,
            frameIDs: [frame.id]
        ))
        let partialReport = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            frames: [partial],
            rolls: [roll],
            scanSessions: [queued.session],
            scanRollAssignments: [queued.assignment]
        ))
        XCTAssertTrue(partialReport.issues.contains { $0.code == .partialFrameScanProvenance })

        partial.scanJobID = queued.jobID
        let queuedReference = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            frames: [partial],
            rolls: [roll],
            scanSessions: [queued.session],
            scanRollAssignments: [queued.assignment]
        ))
        XCTAssertTrue(queuedReference.issues.contains {
            $0.code == .frameScanJobNotSucceededFull && $0.jobID == queued.jobID
        })

        partial.scanSessionID = UUID()
        let missingSession = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            frames: [partial],
            rolls: [roll],
            scanSessions: [queued.session],
            scanRollAssignments: [queued.assignment]
        ))
        XCTAssertTrue(missingSession.issues.contains { $0.code == .frameScanSessionMissing })
    }

    func testSucceededProvenanceFramesMustRemainInAssignedRoll() throws {
        let workflow = try makeSucceededWorkflow()
        var assignedRoll = workflow.roll
        assignedRoll.frameIDs = []
        let otherRoll = try XCTUnwrap(LibraryRoll.physical(
            name: "Other Roll",
            filmType: .colorNegative,
            frameIDs: [workflow.rootRecord.id, workflow.virtualRecord.id]
        ))
        let report = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            frames: [workflow.rootRecord, workflow.virtualRecord],
            rolls: [assignedRoll, otherRoll],
            scanSessions: [workflow.session],
            scanRollAssignments: [workflow.assignment]
        ))

        XCTAssertFalse(report.canOpenSafely)
        XCTAssertTrue(report.issues.contains {
            $0.code == .frameScanRollMismatch && $0.frameID == workflow.rootRecord.id
        })
        XCTAssertTrue(report.issues.contains {
            $0.code == .frameScanRollMismatch && $0.frameID == workflow.virtualRecord.id
        })
    }

    func testPreviewJobsAndDuplicateWorkflowIdentitiesFailClosed() throws {
        let preview = try makeQueuedWorkflow(kind: .preview)
        let previewReport = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            scanSessions: [preview.session],
            scanRollAssignments: [preview.assignment]
        ))
        XCTAssertTrue(previewReport.issues.contains {
            $0.code == .previewJobPersisted && $0.jobID == preview.jobID
        })

        let succeeded = try makeSucceededWorkflow()
        let duplicateReport = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            frames: [succeeded.rootRecord, succeeded.virtualRecord],
            rolls: [succeeded.roll],
            scanSessions: [succeeded.session, succeeded.session],
            scanRollAssignments: [succeeded.assignment]
        ))
        XCTAssertTrue(duplicateReport.issues.contains {
            $0.code == .duplicateScanSessionID && $0.sessionID == succeeded.session.id
        })
        XCTAssertTrue(duplicateReport.issues.contains {
            $0.code == .duplicateScanJobID && $0.jobID == succeeded.jobID
        })
        XCTAssertTrue(duplicateReport.issues.contains {
            $0.code == .duplicateCaptureManifestID
        })
    }

    func testScanRollAssignmentsAreUniqueValidAndOwnedByOneSession() throws {
        let first = try makeQueuedWorkflow()
        let second = try makeQueuedWorkflow()
        let duplicateSession = LibraryScanRollAssignment(
            sessionID: first.session.id,
            rollID: UUID(),
            draftName: "Duplicate",
            filmType: .colorNegative,
            createdAt: first.assignment.createdAt
        )
        let duplicateRoll = LibraryScanRollAssignment(
            sessionID: second.session.id,
            rollID: first.assignment.rollID,
            draftName: "Shared",
            filmType: .colorNegative,
            createdAt: second.assignment.createdAt
        )
        let orphan = LibraryScanRollAssignment(
            sessionID: UUID(),
            rollID: LibraryRoll.unassignedID,
            draftName: " ",
            filmType: .bwNegative,
            createdAt: Date(timeIntervalSinceReferenceDate: .infinity)
        )
        let report = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            scanSessions: [first.session, second.session],
            scanRollAssignments: [first.assignment, duplicateSession, duplicateRoll, orphan]
        ))

        XCTAssertFalse(report.canOpenSafely)
        XCTAssertTrue(report.issues.contains { $0.code == .duplicateScanRollAssignment })
        XCTAssertTrue(report.issues.contains { $0.code == .duplicateScanRollAssignmentRollID })
        XCTAssertTrue(report.issues.contains { $0.code == .invalidScanRollAssignment })
        XCTAssertTrue(report.issues.contains { $0.code == .scanRollAssignmentMissingSession })
    }

    func testMultipleSessionsMayTargetSameExistingPhysicalRoll() throws {
        let sharedRollID = UUID()
        let first = try makeQueuedWorkflow(rollID: sharedRollID)
        let second = try makeQueuedWorkflow(rollID: sharedRollID)
        let roll = try XCTUnwrap(LibraryRoll.physical(
            id: sharedRollID,
            name: "Existing Roll",
            filmType: .colorNegative
        ))
        let healthy = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            rolls: [roll],
            scanSessions: [first.session, second.session],
            scanRollAssignments: [first.assignment, second.assignment]
        ))

        XCTAssertTrue(healthy.canOpenSafely)
        XCTAssertFalse(healthy.issues.contains {
            $0.code == .duplicateScanRollAssignmentRollID
        })

        var mismatchedAssignment = second.assignment
        mismatchedAssignment.filmType = .bwNegative
        let mismatch = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            rolls: [roll],
            scanSessions: [first.session, second.session],
            scanRollAssignments: [first.assignment, mismatchedAssignment]
        ))
        XCTAssertFalse(mismatch.canOpenSafely)
        XCTAssertTrue(mismatch.issues.contains {
            $0.code == .invalidScanRollAssignment
                && $0.sessionID == second.session.id
        })
    }

    func testSucceededRootFrameMustMatchManifestCaptureMetadata() throws {
        let workflow = try makeSucceededWorkflow()
        var wrongKind = workflow.rootRecord
        wrongKind.sourceKind = FrameSource.importedFile.storageKey
        var wrongWidth = workflow.rootRecord
        wrongWidth.sourcePixelWidth = 11
        var wrongHeight = workflow.rootRecord
        wrongHeight.sourcePixelHeight = 9
        var wrongResolution = workflow.rootRecord
        wrongResolution.sourceResolutionDPI = 1800
        var wrongDepth = workflow.rootRecord
        wrongDepth.sourceBitDepth = 8
        var wrongTimestamp = workflow.rootRecord
        wrongTimestamp.scannedAt = wrongTimestamp.scannedAt.addingTimeInterval(1)

        for rootRecord in [
            wrongKind,
            wrongWidth,
            wrongHeight,
            wrongResolution,
            wrongDepth,
            wrongTimestamp,
        ] {
            let report = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
                frames: [rootRecord, workflow.virtualRecord],
                rolls: [workflow.roll],
                scanSessions: [workflow.session],
                scanRollAssignments: [workflow.assignment]
            ))
            XCTAssertFalse(report.canOpenSafely)
            XCTAssertTrue(report.issues.contains {
                $0.code == .scanRootFrameCaptureMismatch
                    && $0.frameID == workflow.rootRecord.id
            })
        }
    }

    func testScanVirtualCopyMustReferenceUniqueProvenanceRoot() throws {
        let workflow = try makeSucceededWorkflow()
        var wrongVirtual = workflow.virtualRecord
        wrongVirtual.sourceFrameID = UUID()
        let report = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            frames: [workflow.rootRecord, wrongVirtual],
            rolls: [workflow.roll],
            scanSessions: [workflow.session],
            scanRollAssignments: [workflow.assignment]
        ))

        XCTAssertFalse(report.canOpenSafely)
        XCTAssertTrue(report.issues.contains {
            $0.code == .scanVirtualCopyRootMismatch
                && $0.frameID == workflow.virtualRecord.id
        })
    }

    func testSourceRelinkDoesNotInvalidateCaptureProvenance() throws {
        let originalURL = try makeCaptureFile()
        let workflow = try makeSucceededWorkflow(
            manifestRawURL: originalURL,
            frameRawURL: URL(fileURLWithPath: "/relinked/capture.tiff")
        )
        let report = LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            frames: [workflow.rootRecord, workflow.virtualRecord],
            rolls: [workflow.roll],
            scanSessions: [workflow.session],
            scanRollAssignments: [workflow.assignment]
        ))

        XCTAssertTrue(report.canOpenSafely)
    }

    func testManualCollectionsRequireUniqueIdentityNameAndExactFrameMembership() {
        let frame = makeFrame(index: 1)
        let record = LibraryFrameRecord(frame: frame)
        let collectionID = UUID()
        let missingFrameID = UUID()
        let catalog = LibraryCatalog(
            frames: [record],
            manualCollections: [
                LibraryManualCollection(
                    id: collectionID,
                    name: "   ",
                    frameIDs: [frame.id, frame.id, missingFrameID]
                ),
                LibraryManualCollection(
                    id: collectionID,
                    name: "Portfolio",
                    frameIDs: []
                ),
            ]
        )

        let report = LibraryCatalogHealthInspector.inspect(catalog)

        XCTAssertFalse(report.canOpenSafely)
        XCTAssertTrue(report.issues.contains {
            $0.code == .duplicateManualCollectionID
                && $0.collectionID == collectionID
        })
        XCTAssertTrue(report.issues.contains {
            $0.code == .invalidManualCollectionName
                && $0.collectionIndex == 0
        })
        XCTAssertTrue(report.issues.contains {
            $0.code == .duplicateManualCollectionMembership
                && $0.collectionID == collectionID
                && $0.frameID == frame.id
        })
        XCTAssertTrue(report.issues.contains {
            $0.code == .manualCollectionMissingFrame
                && $0.collectionID == collectionID
                && $0.frameID == missingFrameID
        })

        let emptyCollectionReport = LibraryCatalogHealthInspector.inspect(
            LibraryCatalog(
                frames: [record],
                manualCollections: [
                    LibraryManualCollection(id: UUID(), name: "Empty", frameIDs: []),
                ]
            )
        )
        XCTAssertTrue(emptyCollectionReport.canOpenSafely)
        XCTAssertFalse(emptyCollectionReport.issues.contains {
            $0.code == .duplicateManualCollectionID
                || $0.code == .invalidManualCollectionName
                || $0.code == .duplicateManualCollectionMembership
                || $0.code == .manualCollectionMissingFrame
        })
    }

    func testStoredSearchDamageIsIsolatedAsWarningButIdentityAndNameFailClosed() {
        let invalidEnvelope = LibraryStoredSearchEnvelope(
            payloadJSON: #"{"version":1,"query":{"version":999}}"#
        )
        let smartID = UUID()
        let savedID = UUID()
        let invalidIdentityCatalog = LibraryCatalog(
            smartCollections: [
                LibrarySmartCollection(id: smartID, name: "", definition: invalidEnvelope),
                LibrarySmartCollection(id: smartID, name: "Review", definition: invalidEnvelope),
            ],
            savedSearches: [
                LibrarySavedSearch(id: savedID, name: "\n", definition: invalidEnvelope),
                LibrarySavedSearch(id: savedID, name: "Recent", definition: invalidEnvelope),
            ]
        )

        let invalidIdentityReport = LibraryCatalogHealthInspector.inspect(
            invalidIdentityCatalog
        )

        XCTAssertFalse(invalidIdentityReport.canOpenSafely)
        XCTAssertTrue(invalidIdentityReport.issues.contains {
            $0.code == .duplicateSmartCollectionID && $0.collectionID == smartID
        })
        XCTAssertTrue(invalidIdentityReport.issues.contains {
            $0.code == .invalidSmartCollectionName && $0.collectionIndex == 0
        })
        XCTAssertTrue(invalidIdentityReport.issues.contains {
            $0.code == .duplicateSavedSearchID && $0.savedSearchID == savedID
        })
        XCTAssertTrue(invalidIdentityReport.issues.contains {
            $0.code == .invalidSavedSearchName && $0.savedSearchIndex == 0
        })

        let isolatedDamageReport = LibraryCatalogHealthInspector.inspect(
            LibraryCatalog(
                smartCollections: [
                    LibrarySmartCollection(
                        id: UUID(),
                        name: "Damaged Smart Collection",
                        definition: invalidEnvelope
                    ),
                ],
                savedSearches: [
                    LibrarySavedSearch(
                        id: UUID(),
                        name: "Damaged Saved Search",
                        definition: invalidEnvelope
                    ),
                ]
            )
        )
        XCTAssertTrue(isolatedDamageReport.canOpenSafely)
        XCTAssertTrue(isolatedDamageReport.issues.contains {
            $0.code == .invalidSmartCollectionQuery && $0.severity == .warning
        })
        XCTAssertTrue(isolatedDamageReport.issues.contains {
            $0.code == .invalidSavedSearchQuery && $0.severity == .warning
        })
    }

    func testUserEditTrackingMustMatchEffectiveRecipeAndCoverageContract() throws {
        let mismatchFrame = makeFrame(index: 1)
        var mismatch = LibraryFrameRecord(frame: mismatchFrame)
        mismatch.userEditTracking.currentRecipeSHA256 = String(repeating: "a", count: 64)

        let missingIngestFrame = makeFrame(index: 2)
        var missingIngest = LibraryFrameRecord(frame: missingIngestFrame)
        missingIngest.userEditTracking = LibraryUserEditTracking(
            coverage: .tracked,
            ingestRecipeSHA256: nil,
            currentRecipeSHA256: try LibraryDevelopRecipeFingerprint.sha256(
                filmType: missingIngest.filmType,
                presetID: missingIngest.presetID,
                params: missingIngest.params,
                imageTransform: missingIngest.imageTransform
            ),
            revision: 0
        )

        let legacyRevisionFrame = makeFrame(index: 3)
        var legacyRevision = LibraryFrameRecord(frame: legacyRevisionFrame)
        legacyRevision.userEditTracking = .legacyUnknown(
            currentRecipeSHA256: legacyRevision.userEditTracking.currentRecipeSHA256
        )
        legacyRevision.userEditTracking.revision = 1

        let report = inspectRecords([mismatch, missingIngest, legacyRevision])

        XCTAssertFalse(report.canOpenSafely)
        XCTAssertEqual(
            Set(report.issues.filter { $0.code == .invalidUserEditTracking }.compactMap(\.frameID)),
            Set([mismatch.id, missingIngest.id, legacyRevision.id])
        )

        let validFrame = makeFrame(index: 4)
        var valid = LibraryFrameRecord(frame: validFrame)
        let recipe = try XCTUnwrap(valid.userEditTracking.currentRecipeSHA256)
        valid.userEditTracking = LibraryUserEditTracking(
            coverage: .tracked,
            ingestRecipeSHA256: recipe,
            currentRecipeSHA256: recipe,
            revision: 0
        )
        let validReport = inspectRecords([valid])
        XCTAssertFalse(validReport.issues.contains { $0.code == .invalidUserEditTracking })
    }

    func testExportTrackingRequiresUniqueCoherentSuccessfulEvents() throws {
        let duplicateEventID = UUID()
        let recipe = String(repeating: "a", count: 64)
        let firstFrame = makeFrame(index: 1)
        var first = LibraryFrameRecord(frame: firstFrame)
        first.exportTracking = LibraryExportTracking(
            coverage: .tracked,
            successfulEvents: [
                LibraryExportEvent(
                    id: duplicateEventID,
                    completedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    primaryOutputPath: "/exports/one.tiff",
                    artifactPaths: ["/exports/one.tiff"],
                    formatRawValue: "tiff16",
                    renderKind: .developed,
                    developRecipeSHA256: recipe,
                    defectRecipeSHA256: nil
                ),
            ]
        )
        let secondFrame = makeFrame(index: 2)
        var second = LibraryFrameRecord(frame: secondFrame)
        second.exportTracking = LibraryExportTracking(
            coverage: .tracked,
            successfulEvents: [
                LibraryExportEvent(
                    id: duplicateEventID,
                    completedAt: Date(timeIntervalSinceReferenceDate: .nan),
                    primaryOutputPath: "/exports/two.tiff",
                    artifactPaths: [
                        "/exports/two.tiff",
                        "/exports/archive/../two.tiff",
                    ],
                    formatRawValue: " ",
                    renderKind: .rawSource,
                    developRecipeSHA256: recipe,
                    defectRecipeSHA256: "bad"
                ),
            ]
        )
        let legacyFrame = makeFrame(index: 3)
        var legacy = LibraryFrameRecord(frame: legacyFrame)
        legacy.exportTracking = LibraryExportTracking(
            coverage: .legacyUnknown,
            successfulEvents: first.exportTracking.successfulEvents
        )

        let report = inspectRecords([first, second, legacy])

        XCTAssertFalse(report.canOpenSafely)
        XCTAssertTrue(report.issues.contains {
            $0.code == .duplicateExportEventID && $0.exportEventID == duplicateEventID
        })
        XCTAssertTrue(report.issues.contains {
            $0.code == .invalidExportTracking && $0.frameID == second.id
        })
        XCTAssertTrue(report.issues.contains {
            $0.code == .invalidExportTracking && $0.frameID == legacy.id
        })

        let validReport = inspectRecords([first])
        XCTAssertFalse(validReport.issues.contains {
            $0.code == .invalidExportTracking || $0.code == .duplicateExportEventID
        })
    }

    func testDefectReviewTrackingRequiresCompleteMonotonicIdentityTriplets() {
        let recipe = String(repeating: "a", count: 64)
        let source = String(repeating: "b", count: 64)
        let partialFrame = makeFrame(index: 1)
        var partial = LibraryFrameRecord(frame: partialFrame)
        partial.defectReviewTracking = LibraryDefectReviewTracking(
            coverage: .tracked,
            currentRecipeRevision: 1,
            currentRecipeSHA256: recipe,
            currentSourceIdentitySHA256: nil,
            reviewedRecipeRevision: nil,
            reviewedRecipeSHA256: nil,
            reviewedSourceIdentitySHA256: nil
        )
        let futureReviewFrame = makeFrame(index: 2)
        var futureReview = LibraryFrameRecord(frame: futureReviewFrame)
        futureReview.defectReviewTracking = LibraryDefectReviewTracking(
            coverage: .tracked,
            currentRecipeRevision: 1,
            currentRecipeSHA256: recipe,
            currentSourceIdentitySHA256: source,
            reviewedRecipeRevision: 2,
            reviewedRecipeSHA256: recipe,
            reviewedSourceIdentitySHA256: source
        )
        let mismatchedEqualRevisionFrame = makeFrame(index: 3)
        var mismatchedEqualRevision = LibraryFrameRecord(frame: mismatchedEqualRevisionFrame)
        mismatchedEqualRevision.defectReviewTracking = LibraryDefectReviewTracking(
            coverage: .tracked,
            currentRecipeRevision: 2,
            currentRecipeSHA256: recipe,
            currentSourceIdentitySHA256: source,
            reviewedRecipeRevision: 2,
            reviewedRecipeSHA256: String(repeating: "c", count: 64),
            reviewedSourceIdentitySHA256: source
        )

        let report = inspectRecords([partial, futureReview, mismatchedEqualRevision])

        XCTAssertFalse(report.canOpenSafely)
        XCTAssertEqual(
            Set(report.issues.filter { $0.code == .invalidDefectReviewTracking }.compactMap(\.frameID)),
            Set([partial.id, futureReview.id, mismatchedEqualRevision.id])
        )

        let validFrame = makeFrame(index: 4)
        var valid = LibraryFrameRecord(frame: validFrame)
        valid.defectReviewTracking = LibraryDefectReviewTracking(
            coverage: .tracked,
            currentRecipeRevision: 3,
            currentRecipeSHA256: recipe,
            currentSourceIdentitySHA256: source,
            reviewedRecipeRevision: 3,
            reviewedRecipeSHA256: recipe,
            reviewedSourceIdentitySHA256: source
        )
        let validReport = inspectRecords([valid])
        XCTAssertFalse(validReport.issues.contains {
            $0.code == .invalidDefectReviewTracking
        })
    }

    private func inspectMetadata(
        _ metadata: SourceMetadataSnapshot?
    ) -> LibraryCatalogHealthReport {
        let frame = makeFrame(index: 1)
        var record = LibraryFrameRecord(frame: frame)
        record.sourceMetadata = metadata
        return inspectRecords([record])
    }

    private func inspectRecords(
        _ records: [LibraryFrameRecord]
    ) -> LibraryCatalogHealthReport {
        let roll = LibraryRoll.unassigned(
            createdAt: Date(timeIntervalSince1970: 0),
            frameIDs: records.map(\.id)
        )
        return LibraryCatalogHealthInspector.inspect(LibraryCatalog(
            frames: records,
            rolls: [roll]
        ))
    }

    private func makeIPTC(keywords: [String]) -> SourceIPTCMetadata {
        SourceIPTCMetadata(
            title: nil,
            headline: nil,
            caption: nil,
            creators: [],
            credit: nil,
            copyrightNotice: nil,
            rightsUsageTerms: nil,
            source: nil,
            jobIdentifier: nil,
            keywords: keywords,
            city: nil,
            stateProvince: nil,
            country: nil,
            countryCode: nil,
            sublocation: nil
        )
    }

    private func makeXMP(
        title: SourceLocalizedText? = nil,
        rating: Double? = nil
    ) -> SourceXMPMetadata {
        SourceXMPMetadata(
            createDateRaw: nil,
            dateCreatedRaw: nil,
            title: title,
            description: nil,
            creators: [],
            rights: nil,
            usageTerms: nil,
            headline: nil,
            credit: nil,
            jobIdentifier: nil,
            keywords: [],
            city: nil,
            stateProvince: nil,
            country: nil,
            sublocation: nil,
            rating: rating,
            label: nil
        )
    }

    private func makeFrame(index: Int) -> ScanFrame {
        ScanFrame(
            scanIndex: index,
            rawScanURL: URL(fileURLWithPath: "/tmp/health-\(UUID().uuidString).tiff"),
            filmType: .colorNegative
        )
    }

    private func makeQueuedWorkflow(
        kind: ScanJobKind = .full,
        sessionID: UUID = UUID(),
        jobID: UUID = UUID(),
        rollID: UUID = UUID()
    ) throws -> (
        session: ScanSession,
        assignment: LibraryScanRollAssignment,
        jobID: UUID
    ) {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let scannerID = "plugin:test-plugin:device-1"
        var options = kind == .preview
            ? ScanOptions.preview(scannerID: scannerID)
            : ScanOptions.strongDefault(scannerID: scannerID)
        options.requestID = jobID
        options.temporaryOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("health-job-\(jobID.uuidString).tiff")
        let job = try ScanJob(
            id: jobID,
            sessionID: sessionID,
            ordinal: 1,
            kind: kind,
            requestedOptions: options,
            framePublication: kind == .full
                ? try ScanFramePublicationSnapshot(
                    frameID: jobID,
                    scanIndex: 1,
                    initialTransform: .identity,
                    developTarget: .main,
                    storageGroupName: "TestScanner"
                )
                : nil,
            createdAt: createdAt
        )
        let session = try makeSession(id: sessionID, createdAt: createdAt, jobs: [job])
        return (
            session,
            LibraryScanRollAssignment(
                sessionID: sessionID,
                rollID: rollID,
                draftName: "Test Roll",
                filmType: .colorNegative,
                createdAt: createdAt
            ),
            jobID
        )
    }

    private func makeSucceededWorkflow(
        manifestRawURL: URL? = nil,
        frameRawURL: URL = URL(fileURLWithPath: "/relinked/capture.tiff")
    ) throws -> (
        session: ScanSession,
        assignment: LibraryScanRollAssignment,
        roll: LibraryRoll,
        rootRecord: LibraryFrameRecord,
        virtualRecord: LibraryFrameRecord,
        jobID: UUID
    ) {
        let sessionID = UUID()
        let jobID = UUID()
        let rollID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let startedAt = createdAt.addingTimeInterval(1)
        let completedAt = createdAt.addingTimeInterval(2)
        let finishedAt = createdAt.addingTimeInterval(3)
        let scannerID = "plugin:test-plugin:device-1"
        let captureURL: URL
        if let manifestRawURL {
            captureURL = manifestRawURL
        } else {
            captureURL = try makeCaptureFile()
        }
        var options = ScanOptions.strongDefault(scannerID: scannerID)
        options.requestID = jobID
        options.temporaryOutputURL = captureURL
        let result = CaptureResultSnapshot(
            width: 10,
            height: 8,
            resolution: options.resolution,
            bitDepth: options.bitDepth,
            colorSpace: "sRGB",
            hasInfraredChannel: false,
            reportedDuration: 1,
            backendUsed: .plugin
        )
        let pending = try PendingCaptureSnapshot(
            result: result,
            appliedOptionsEvidence: .verified(options),
            captureStartedAt: startedAt,
            captureCompletedAt: completedAt,
            rawFileURL: captureURL
        )
        let queued = try ScanJob(
            id: jobID,
            sessionID: sessionID,
            ordinal: 1,
            kind: .full,
            requestedOptions: options,
            framePublication: try ScanFramePublicationSnapshot(
                frameID: jobID,
                scanIndex: 1,
                initialTransform: .identity,
                developTarget: .main,
                storageGroupName: "TestScanner"
            ),
            createdAt: createdAt
        )
        let finalizing = try queued.started(at: startedAt).finalizing(
            with: pending,
            at: completedAt
        )
        let manifest = try CaptureManifest.build(
            sessionID: sessionID,
            jobID: jobID,
            attempt: 1,
            kind: .full,
            requestedOptions: options,
            pendingCapture: pending
        )
        let succeeded = try finalizing.succeeded(with: manifest, at: finishedAt)
        let session = try makeSession(id: sessionID, createdAt: createdAt, jobs: [succeeded])
        let assignment = LibraryScanRollAssignment(
            sessionID: sessionID,
            rollID: rollID,
            draftName: "Test Roll",
            filmType: .colorNegative,
            createdAt: createdAt
        )
        let root = ScanFrame(
            scanIndex: 1,
            rawScanURL: frameRawURL,
            filmType: .colorNegative,
            sourceKind: .scannerTIFF,
            sourcePixelWidth: result.width,
            sourcePixelHeight: result.height,
            sourceResolutionDPI: result.resolution.dpi,
            sourceBitDepth: result.bitDepth.rawValue,
            scannedAt: completedAt,
            id: jobID
        )
        var rootRecord = LibraryFrameRecord(frame: root)
        rootRecord.scanSessionID = sessionID
        rootRecord.scanJobID = jobID
        let virtual = ScanFrame(
            scanIndex: 1,
            rawScanURL: frameRawURL,
            filmType: .colorNegative,
            sourceKind: .scannerTIFF,
            sourcePixelWidth: result.width,
            sourcePixelHeight: result.height,
            sourceResolutionDPI: result.resolution.dpi,
            sourceBitDepth: result.bitDepth.rawValue,
            scannedAt: completedAt,
            sourceFrameID: root.id,
            sourceFrameDisplayName: "Frame 1",
            virtualCopyNumber: 1
        )
        var virtualRecord = LibraryFrameRecord(frame: virtual)
        virtualRecord.scanSessionID = sessionID
        virtualRecord.scanJobID = jobID
        let roll = try XCTUnwrap(LibraryRoll.physical(
            id: rollID,
            name: assignment.draftName,
            createdAt: createdAt,
            filmType: assignment.filmType,
            frameIDs: [root.id, virtual.id]
        ))
        return (session, assignment, roll, rootRecord, virtualRecord, jobID)
    }

    private func makeSession(
        id: UUID,
        createdAt: Date,
        jobs: [ScanJob]
    ) throws -> ScanSession {
        let scannerID = "plugin:test-plugin:device-1"
        return try ScanSession(
            id: id,
            createdAt: createdAt,
            device: ScannerDescriptor(
                id: scannerID,
                displayName: "Test Scanner",
                vendor: "Test Vendor",
                model: "Test Model",
                backendType: .plugin
            ),
            backend: ScanBackendSnapshot(
                type: .plugin,
                identifier: "external-json",
                pluginIdentifier: "test-plugin"
            ),
            environment: ScanEnvironmentSnapshot(
                applicationName: "negaflow",
                applicationVersion: "1.0",
                operatingSystem: "macOS",
                operatingSystemVersion: "15.0",
                architecture: "arm64"
            ),
            jobs: jobs
        )
    }

    private func makeCaptureFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-health-capture-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("capture.tiff")
        try Data([1, 2, 3, 4]).write(to: url, options: .atomic)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return url
    }
}
