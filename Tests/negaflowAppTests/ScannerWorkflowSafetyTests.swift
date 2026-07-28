import XCTest
import ScannerKit
import Chromabase
@testable import negaflowApp

@MainActor
final class ScannerWorkflowSafetyTests: XCTestCase {
    func testCapabilitiesClampSelectionsAndUnsupportedPreviewDoesNotStart() async {
        let backend = ScannerWorkflowBackend(capabilities: ScannerCapabilities(
            supportedResolutions: [Resolution(2_400)],
            supportedModes: [.gray],
            supportedBitDepths: [.sixteen],
            supportsPreview: false
        ))
        let model = AppModel(scannerDemoBackend: backend)
        model.demoMode = true
        model.resolutionChoice = .r7200
        model.bitDepthChoice = .eight
        model.colorModeChoice = .color

        await model.loadCapabilities()

        XCTAssertEqual(model.resolutionChoice, Resolution(2_400))
        XCTAssertEqual(model.bitDepthChoice, .sixteen)
        XCTAssertEqual(model.colorModeChoice, .gray)
        XCTAssertTrue(model.canScan)
        XCTAssertFalse(model.canPreview)

        await model.runScan(preview: true)
        XCTAssertEqual(backend.previewRequestCount, 0)
        XCTAssertTrue(model.frames.isEmpty)
    }

    /// epson2 평판(Epson V700~V850)은 50dpi부터 12800dpi까지 노출하고 3600dpi가 없다.
    /// 목록의 첫 값을 고르면 기본 해상도가 50dpi로 떨어져 필름 한 컷이 수십 픽셀이 된다.
    func testResolutionFallsBackToTheNearestFilmResolutionInsteadOfTheLowest() async {
        let epsonFlatbedResolutions = [
            50, 60, 72, 75, 100, 150, 200, 300, 400, 600, 800, 1_200,
            1_600, 1_800, 2_400, 3_200, 4_800, 6_400, 9_600, 12_800,
        ].map(Resolution.init)
        let backend = ScannerWorkflowBackend(capabilities: ScannerCapabilities(
            supportedResolutions: epsonFlatbedResolutions,
            supportedModes: [.color, .gray],
            supportedBitDepths: [.eight, .sixteen],
            supportsPreview: true
        ))
        let model = AppModel(scannerDemoBackend: backend)
        model.demoMode = true
        model.resolutionChoice = .r3600

        await model.loadCapabilities()

        XCTAssertEqual(model.resolutionChoice, Resolution(3_200))
    }

    func testNearestResolutionPrefersTheHigherValueOnATie() {
        XCTAssertEqual(
            AppModel.preferredScanResolution(in: [Resolution(3_400), Resolution(3_800)]),
            Resolution(3_800)
        )
        XCTAssertEqual(
            AppModel.preferredScanResolution(in: [Resolution(3_600), Resolution(4_800)]),
            .r3600
        )
        XCTAssertNil(AppModel.preferredScanResolution(in: []))
    }

    func testNeutralScannerHardwareAdjustmentsAreNotSent() {
        let range = ScannerOptionRange(minimum: -100, maximum: 100, step: 1)

        XCTAssertNil(AppModel.scannerHardwareAdjustment(
            0,
            range: range,
            scannerID: "sane-epson2:libusb:000:001",
            bitDepth: .sixteen
        ))
        XCTAssertEqual(AppModel.scannerHardwareAdjustment(
            12,
            range: range,
            scannerID: "sane-epson2:libusb:000:001",
            bitDepth: .eight
        ), 12)
    }

    func testGenesysSixteenBitSilentlyOmitsHardwareToneAdjustments() {
        let range = ScannerOptionRange(minimum: -100, maximum: 100, step: 1)

        XCTAssertNil(AppModel.scannerHardwareAdjustment(
            12,
            range: range,
            scannerID: "sane-genesys:libusb:000:010",
            bitDepth: .sixteen
        ))
        XCTAssertEqual(AppModel.scannerHardwareAdjustment(
            12,
            range: range,
            scannerID: "sane-genesys:libusb:000:010",
            bitDepth: .eight
        ), 12)
    }

    func testFullScanClampsSupportedHardwareScanAreaIntoRequestedOptions() async throws {
        let maximum = ScanArea(widthMM: 36, heightMM: 24)
        let backend = ScannerWorkflowBackend(capabilities: ScannerCapabilities(
            supportedResolutions: [.r3600],
            supportedModes: [.color],
            supportedBitDepths: [.eight, .sixteen],
            supportsPreview: true,
            supportsScanArea: true,
            maxScanArea: maximum,
            minScanArea: ScanArea(widthMM: 4, heightMM: 3),
            scanAreaUnit: .millimeter
        ))
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        model.demoMode = true

        await model.loadCapabilities()

        XCTAssertEqual(model.hardwareScanAreaBounds?.maximum, maximum)
        XCTAssertEqual(model.selectedHardwareScanArea, maximum)

        model.updateHardwareScanArea(ScanArea(widthMM: 100, heightMM: 1))
        XCTAssertEqual(model.selectedHardwareScanArea, ScanArea(widthMM: 36, heightMM: 3))

        await model.runScan(preview: false)

        XCTAssertEqual(
            backend.fullRequests.only?.scanArea,
            ScanArea(widthMM: 36, heightMM: 3)
        )
    }

    func testPositionedFlatbedPreviewCreatesOneFullScanJobPerSelectedRegion() async throws {
        let backend = ScannerWorkflowBackend(capabilities: ScannerCapabilities(
            supportedResolutions: [.r3600],
            supportedModes: [.color],
            supportedBitDepths: [.eight, .sixteen],
            supportsPreview: true,
            supportsTransparency: true,
            supportsScanArea: true,
            supportsPositionedScanArea: true,
            maxScanArea: ScanArea(originXMM: 1, originYMM: 2, widthMM: 200, heightMM: 100),
            minScanArea: ScanArea(originXMM: 1, originYMM: 2, widthMM: 1, heightMM: 1)
        ))
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        model.demoMode = true
        model.nextScanOrientation = ImageTransform(flipHorizontal: true)
        await model.loadCapabilities()

        await model.runScan(preview: true)
        XCTAssertNotNil(model.flatbedPreviewFrame)
        XCTAssertEqual(
            model.flatbedPreviewScanArea,
            ScanArea(originXMM: 1, originYMM: 2, widthMM: 200, heightMM: 100)
        )
        XCTAssertTrue(model.flatbedScanRegions.isEmpty)
        model.addFlatbedScanRegion(unitRect: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.3))
        model.addFlatbedScanRegion(unitRect: CGRect(x: 0.5, y: 0.4, width: 0.25, height: 0.2))
        model.flatbedScanRegions[0].straightenAngle = 1.25
        model.flatbedScanRegions[1].straightenAngle = -0.75

        XCTAssertTrue(model.canStartFullScan)
        await model.scanFrames(count: 12, preview: false)

        // 첫 요청은 유리판 전체를 뜬 프리뷰고, 그 뒤가 영역별 본 스캔이다.
        XCTAssertEqual(backend.fullRequestCount, 3)
        XCTAssertEqual(
            backend.fullRequests.first?.scanArea,
            ScanArea(originXMM: 1, originYMM: 2, widthMM: 200, heightMM: 100)
        )
        XCTAssertEqual(
            backend.fullRequests.dropFirst().map(\.scanArea),
            [
                ScanArea(originXMM: 21, originYMM: 22, widthMM: 40, heightMM: 30),
                ScanArea(originXMM: 101, originYMM: 42, widthMM: 50, heightMM: 20),
            ]
        )
        XCTAssertEqual(model.scanSessions.only?.jobs.count, 2)
        XCTAssertEqual(
            model.scanSessions.only?.jobs.compactMap {
                $0.framePublication?.initialTransform.straightenAngle
            },
            [-1.25, 0.75]
        )
        XCTAssertTrue(model.scanSessions.only?.jobs.allSatisfy {
            $0.framePublication?.initialTransform.flipHorizontal == true
        } == true)
        XCTAssertEqual(model.frames.count, 2)
        XCTAssertTrue(model.frames.allSatisfy { !$0.isPreviewScan })
        XCTAssertEqual(model.selectedFrameID, model.frames.last?.id)
        XCTAssertEqual(model.actionableFrame?.id, model.frames.last?.id)
        XCTAssertNil(model.flatbedPreviewFrameID)
        XCTAssertNil(model.flatbedPreviewScanArea)
        XCTAssertTrue(model.flatbedScanRegions.isEmpty)
    }

    /// 평판 프리뷰는 그 위에서 필름 영역을 잡는 작업면이다. 기존 25dpi 경로로는
    /// 프레임 자동 검출이 시작조차 못 한다.
    func testFlatbedPreviewRequestsAnExplicitWorkableResolution() async throws {
        let epsonFlatbedResolutions = [
            50, 60, 72, 75, 100, 120, 133, 144, 150, 160, 200, 300, 600,
            1_200, 2_400, 3_200, 4_800, 6_400, 12_800,
        ].map(Resolution.init)
        let backend = ScannerWorkflowBackend(capabilities: ScannerCapabilities(
            supportedResolutions: epsonFlatbedResolutions,
            supportedModes: [.color],
            supportedBitDepths: [.eight, .sixteen],
            supportsPreview: true,
            supportsTransparency: true,
            supportsScanArea: true,
            supportsPositionedScanArea: true,
            maxScanArea: ScanArea(originXMM: 0, originYMM: 0, widthMM: 203.2, heightMM: 254),
            minScanArea: ScanArea(originXMM: 0, originYMM: 0, widthMM: 1, heightMM: 1)
        ))
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        model.demoMode = true
        await model.loadCapabilities()

        await model.runScan(preview: true)

        XCTAssertEqual(backend.previewRequestCount, 0, "해상도를 명시한 프리뷰는 백엔드 프리뷰 경로로 보내지 않는다.")
        XCTAssertEqual(backend.fullRequests.map(\.resolution), [Resolution(300)])
        XCTAssertEqual(backend.fullRequests.first?.bitDepth, .eight)
        XCTAssertEqual(
            backend.fullRequests.first?.outputRawTIFF,
            true,
            "외부 플러그인의 full scan 계약은 TIFF 산출물을 요구한다."
        )
        XCTAssertEqual(
            backend.fullRequests.first?.scanArea,
            ScanArea(originXMM: 0, originYMM: 0, widthMM: 203.2, heightMM: 254),
            "프리뷰는 유리판 전체를 떠야 그 위에서 영역을 잡을 수 있다."
        )
        XCTAssertNotNil(model.flatbedPreviewFrame)
    }

    /// 필름 전용 스캐너는 영역을 잡을 필요가 없으므로 백엔드 프리뷰 경로를 그대로 쓴다.
    func testDedicatedFilmScannerKeepsTheBackendPreviewPath() async throws {
        let backend = ScannerWorkflowBackend(capabilities: ScannerCapabilities(
            supportedResolutions: [.r3600, Resolution(300)],
            supportedModes: [.color],
            supportedBitDepths: [.eight, .sixteen],
            supportsPreview: true,
            supportsTransparency: true
        ))
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        model.demoMode = true
        await model.loadCapabilities()

        await model.runScan(preview: true)

        XCTAssertFalse(model.usesFlatbedRegionWorkflow)
        XCTAssertEqual(backend.previewRequestCount, 1)
        XCTAssertEqual(backend.fullRequestCount, 0)
    }

    func testMockFlatbedFullScansLeaveLastSelectedFrameImmediatelyRenderable() async throws {
        let backend = MockScannerBackend()
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        model.demoMode = true
        model.selectedDeviceID = MockScannerBackend.flatbedScannerID
        await model.loadCapabilities()

        model.updateInteractionScope([])
        await model.runScan(preview: true)
        let previewFrame = try XCTUnwrap(model.flatbedPreviewFrame)
        XCTAssertEqual(model.selectedFrameID, previewFrame.id)
        XCTAssertEqual(model.actionableFrame?.id, previewFrame.id)
        // 첫 썸네일 시드는 백그라운드 디코드다(메인 스레드 무정지) — 완료 후 원본 프리뷰 보장.
        // 참조는 끝나는 즉시 정리되므로(축출된 프레임이 "시드 중"으로 오해되지 않게), 남아 있을
        // 때만 기다린다. 계약은 참조의 수명이 아니라 완료 뒤 rawPreviewImage 가 채워지는 것이다.
        if let seed = previewFrame.initialThumbnailSeedTask { await seed.value }
        XCTAssertNotNil(previewFrame.rawPreviewImage)
        await waitForDevelopedThumbnail(previewFrame)
        XCTAssertNotNil(previewFrame.thumbnailImage)
        XCTAssertFalse(previewFrame.thumbnailImage === previewFrame.rawPreviewImage)
        model.updateInteractionScope([previewFrame.id])
        model.flatbedScanRegions = [
            FlatbedScanRegion(
                unitRect: CGRect(x: 0.12, y: 0.18, width: 0.26, height: 0.42)
            ),
            FlatbedScanRegion(
                unitRect: CGRect(x: 0.56, y: 0.24, width: 0.22, height: 0.36)
            ),
        ]
        await model.runScan(preview: false)

        XCTAssertEqual(model.frames.count, 2)
        XCTAssertEqual(model.scanSessions.only?.jobs.count, 2)
        XCTAssertTrue(model.scanSessions.only?.jobs.allSatisfy { $0.state == .succeeded } == true)
        XCTAssertEqual(Set(model.frames.map(\.rawScanURL)).count, 2)
        for frame in model.frames {
            XCTAssertFalse(frame.isPreviewScan)
            // 첫 썸네일 시드는 백그라운드 디코드로 옮겨졌다(스캔 완료 때 풀 TIFF 디코드가 메인
            // 스레드를 잡지 않도록). 참조는 끝나는 즉시 정리되므로 남아 있을 때만 기다리고,
            // 발행 계약은 완료 후 원본 프리뷰가 반드시 채워지는 것으로 확인한다.
            if let seed = frame.initialThumbnailSeedTask { await seed.value }
            XCTAssertNotNil(frame.rawPreviewImage)
            await waitForDevelopedThumbnail(frame)
            XCTAssertNotNil(frame.thumbnailImage)
            XCTAssertFalse(frame.thumbnailImage === frame.rawPreviewImage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: frame.rawScanURL.path))
        }
        XCTAssertEqual(model.selectedFrameID, model.frames.last?.id)
        XCTAssertEqual(model.actionableFrame?.id, model.frames.last?.id)
    }

    func testMockFlatbedPreviewAutomaticallyDetectsSpecifiedRollFixtures() async throws {
        for includesPerforation in [false, true] {
            let backend = MockScannerBackend()
            backend.setSimulatorIncludesPerforation(includesPerforation)
            let fixture = try await makePersistentFixture(backend: backend)
            defer { fixture.cleanup() }
            let model = fixture.model
            model.demoMode = true
            model.selectedDeviceID = MockScannerBackend.flatbedScannerID
            await model.loadCapabilities()

            await model.runScan(preview: true)

            let expectedRows = includesPerforation ? 3 : 1
            let expectedCount = includesPerforation ? 18 : 6
            XCTAssertEqual(model.flatbedScanRegions.count, expectedCount)
            let rows = Dictionary(grouping: model.flatbedScanRegions) {
                Int(($0.unitRect.midY * 10_000).rounded())
            }
            XCTAssertEqual(rows.count, expectedRows)
            XCTAssertTrue(rows.values.allSatisfy { $0.count == 6 })
            XCTAssertTrue(model.flatbedScanRegions.allSatisfy {
                $0.unitRect.minX >= 0
                    && $0.unitRect.minY >= 0
                    && $0.unitRect.maxX <= 1
                    && $0.unitRect.maxY <= 1
                    && $0.straightenAngle.isFinite
                    && $0.source == .automatic
            })

            let detectedRegions = model.flatbedScanRegions
            await model.runScan(preview: false)

            let session = try XCTUnwrap(model.scanSessions.last)
            XCTAssertEqual(session.jobs.count, expectedCount)
            XCTAssertEqual(
                Set(session.jobs.compactMap {
                    $0.requestedOptions.temporaryOutputURL?.path
                }).count,
                expectedCount
            )
            XCTAssertEqual(
                session.jobs.compactMap {
                    $0.framePublication?.initialTransform.straightenAngle
                },
                detectedRegions.map(\.straightenAngle)
            )
            XCTAssertEqual(model.frames.count, expectedCount)
            XCTAssertTrue(model.frames.allSatisfy { !$0.isPreviewScan })
            XCTAssertEqual(
                model.frames.map(\.imageTransform.straightenAngle),
                detectedRegions.map(\.straightenAngle)
            )
        }
    }

    func testMockFlatbedSelectedFilmFormatsAutomaticallyDetectAndFullScan() async throws {
        let cases: [(format: FilmFrameFormat, expectedCount: Int)] = [
            (.fullFrame35mm, 6),
            (.square35mm, 8),
            (.halfFrame35mm, 11),
            (.medium645, 4),
            (.medium66, 3),
            (.medium67, 2),
            (.medium68, 2),
            (.medium69, 2),
            (.medium612, 1),
            (.medium617, 1),
        ]

        for testCase in cases {
            let backend = MockScannerBackend()
            let fixture = try await makePersistentFixture(backend: backend)
            defer { fixture.cleanup() }
            let model = fixture.model
            model.demoMode = true
            model.selectedDeviceID = MockScannerBackend.flatbedScannerID
            await model.loadCapabilities()
            await model.selectScanFrameFormat(testCase.format)
            model.setScannerSimulatorFrameCount(testCase.expectedCount)

            XCTAssertTrue(model.usesFlatbedRegionWorkflow, testCase.format.displayName)
            XCTAssertEqual(model.scanFrameFormat, testCase.format)
            await model.runScan(preview: true)

            let capabilities: ScannerCapabilities = try XCTUnwrap(
                model.capabilities,
                testCase.format.displayName
            )
            let previewScanArea = try XCTUnwrap(
                model.flatbedPreviewScanArea,
                testCase.format.displayName
            )
            XCTAssertEqual(
                model.flatbedScanRegions.count,
                testCase.expectedCount,
                testCase.format.displayName
            )
            let expectedScanAreas = try model.flatbedScanRegions.map { region in
                try XCTUnwrap(
                    FlatbedScanRegionGeometry.physicalArea(
                        for: region,
                        previewScanArea: previewScanArea,
                        capabilities: capabilities
                    ),
                    testCase.format.displayName
                )
            }
            let detectedRects = model.flatbedScanRegions.map(\.unitRect)
            for index in detectedRects.indices {
                for otherRect in detectedRects.dropFirst(index + 1) {
                    XCTAssertNotEqual(detectedRects[index], otherRect)
                }
            }

            await model.runScan(preview: false)

            let session = try XCTUnwrap(model.scanSessions.last)
            XCTAssertEqual(
                session.jobs.count,
                testCase.expectedCount,
                testCase.format.displayName
            )
            XCTAssertTrue(session.jobs.allSatisfy { $0.state == .succeeded })
            XCTAssertEqual(
                session.jobs.map(\.requestedOptions.scanArea),
                expectedScanAreas,
                testCase.format.displayName
            )
            for (job, expectedScanArea) in zip(session.jobs, expectedScanAreas) {
                let manifest: CaptureManifest = try XCTUnwrap(
                    job.captureManifest,
                    testCase.format.displayName
                )
                guard case .verified(let appliedOptions) = manifest.appliedOptionsEvidence else {
                    XCTFail("\(testCase.format.displayName): 본 스캔 적용 영역 증명 누락")
                    continue
                }
                XCTAssertEqual(
                    appliedOptions.scanArea,
                    expectedScanArea,
                    testCase.format.displayName
                )
            }
            XCTAssertEqual(model.frames.count, testCase.expectedCount)
            XCTAssertTrue(model.frames.allSatisfy { !$0.isPreviewScan })
        }
    }

    func testFilmFrameFormatChoicesAreLimitedByScannerPhysicalArea() async throws {
        let backend = MockScannerBackend()
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        model.demoMode = true
        model.selectedDeviceID = MockScannerBackend.filmScannerID
        await model.loadCapabilities()

        XCTAssertFalse(model.usesFlatbedRegionWorkflow)
        XCTAssertEqual(
            model.availableScanFrameFormats,
            [.fullFrame35mm, .square35mm, .halfFrame35mm]
        )

        await model.selectScanFrameFormat(.halfFrame35mm)

        XCTAssertEqual(model.scanFrameFormat, .halfFrame35mm)
        XCTAssertEqual(
            model.selectedHardwareScanArea,
            ScanArea(originXMM: 9, originYMM: 0, widthMM: 18, heightMM: 24)
        )

        await model.selectScanFrameFormat(.medium66)
        XCTAssertEqual(model.scanFrameFormat, .halfFrame35mm)

        model.selectedDeviceID = MockScannerBackend.flatbedScannerID
        await model.loadCapabilities()

        XCTAssertTrue(model.usesFlatbedRegionWorkflow)
        XCTAssertEqual(model.availableScanFrameFormats, FilmFrameFormat.allCases)
    }

    func testManualFlatbedRegionEditInvalidatesDetectedStraightenAngle() {
        let model = AppModel()
        let region = FlatbedScanRegion(
            unitRect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            straightenAngle: 1.5,
            source: .automatic
        )
        model.flatbedScanRegions = [region]
        let revision = model.flatbedScanRegionRevision

        model.updateFlatbedScanRegion(
            region.id,
            unitRect: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.4)
        )

        XCTAssertEqual(model.flatbedScanRegions.only?.straightenAngle, 0)
        XCTAssertEqual(model.flatbedScanRegions.only?.source, .manual)
        XCTAssertNotEqual(model.flatbedScanRegionRevision, revision)
    }

    func testAutomaticPositionedFlatbedRejectsNonMockOutputWithWrongAspectRatio() async throws {
        let backend = ScannerWorkflowBackend(
            capabilities: ScannerCapabilities(
                supportedResolutions: [.r3600],
                supportedModes: [.color],
                supportedBitDepths: [.eight, .sixteen],
                supportsPreview: true,
                supportsTransparency: true,
                supportsScanArea: true,
                supportsPositionedScanArea: true,
                maxScanArea: ScanArea(widthMM: 200, heightMM: 100),
                minScanArea: ScanArea(widthMM: 1, heightMM: 1)
            ),
            backendType: .imageCaptureCore,
            resultBackendType: .imageCaptureCore,
            distortsFullScanAspect: true
        )
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        model.demoMode = true
        await model.loadCapabilities()

        await model.runScan(preview: true)
        model.flatbedScanRegions = [FlatbedScanRegion(
            unitRect: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.3),
            source: .automatic
        )]
        await model.runScan(preview: false)

        // 평판 프리뷰도 해상도를 명시한 스캔이라 같은 진입점을 쓴다. 영역 스캔은 그 다음 1건.
        XCTAssertEqual(backend.fullRequestCount, 2)
        XCTAssertEqual(model.frames.count, 1)
        XCTAssertTrue(model.frames.only?.isPreviewScan == true)
        XCTAssertNotNil(model.flatbedPreviewFrameID)
        XCTAssertEqual(model.scanSessions.only?.jobs.only?.state, .failed)
        let outputURL = try XCTUnwrap(backend.fullRequests.last?.temporaryOutputURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testManualFlatbedRegionAcceptsNonMockOutputRegardlessOfFrameAspect() async throws {
        let backend = ScannerWorkflowBackend(
            capabilities: ScannerCapabilities(
                supportedResolutions: [.r3600],
                supportedModes: [.color],
                supportedBitDepths: [.eight, .sixteen],
                supportsPreview: true,
                supportsTransparency: true,
                supportsScanArea: true,
                supportsPositionedScanArea: true,
                maxScanArea: ScanArea(widthMM: 200, heightMM: 100),
                minScanArea: ScanArea(widthMM: 1, heightMM: 1)
            ),
            backendType: .imageCaptureCore,
            resultBackendType: .imageCaptureCore,
            distortsFullScanAspect: true
        )
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        model.demoMode = true
        await model.loadCapabilities()

        await model.runScan(preview: true)
        model.addFlatbedScanRegion(
            unitRect: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.3)
        )
        XCTAssertEqual(model.flatbedScanRegions.only?.source, .manual)
        XCTAssertTrue(model.canStartFullScan)
        await model.runScan(preview: false)

        XCTAssertEqual(backend.fullRequestCount, 2)
        XCTAssertEqual(
            model.scanSessions.only?.jobs.only?.state,
            .succeeded,
            String(describing: model.scanSessions.only?.jobs.only?.failure)
        )
        XCTAssertEqual(model.frames.count, 1)
        XCTAssertFalse(model.frames.only?.isPreviewScan == true)
    }

    func testPositionedAreaWithoutPreviewRetainsFixedFrameWorkflow() async throws {
        let backend = ScannerWorkflowBackend(capabilities: ScannerCapabilities(
            supportedResolutions: [.r3600],
            supportedModes: [.color],
            supportedBitDepths: [.eight, .sixteen],
            supportsPreview: false,
            supportsScanArea: true,
            supportsPositionedScanArea: true,
            scanOriginXRange: ScannerOptionRange(minimum: 1, maximum: 201, step: 0.1),
            scanOriginYRange: ScannerOptionRange(minimum: 2, maximum: 102, step: 0.1),
            scanWidthRange: ScannerOptionRange(minimum: 1, maximum: 200, step: 0.1),
            scanHeightRange: ScannerOptionRange(minimum: 1, maximum: 100, step: 0.1),
            maxScanArea: ScanArea(originXMM: 1, originYMM: 2, widthMM: 200, heightMM: 100),
            minScanArea: ScanArea(originXMM: 1, originYMM: 2, widthMM: 1, heightMM: 1)
        ))
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        model.demoMode = true
        await model.loadCapabilities()

        XCTAssertFalse(model.usesFlatbedRegionWorkflow)
        XCTAssertTrue(model.availableScanFrameFormats.isEmpty)
        XCTAssertTrue(model.canStartFullScan)
        await model.runScan(preview: false)

        XCTAssertEqual(backend.fullRequestCount, 1)
        XCTAssertEqual(
            backend.fullRequests.only?.scanArea,
            ScanArea(originXMM: 1, originYMM: 2, widthMM: 200, heightMM: 100)
        )
    }

    func testUnsupportedScannerDoesNotUseStaleHardwareScanAreaSelection() async throws {
        let backend = ScannerWorkflowBackend(capabilities: Self.usableCapabilities)
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        model.demoMode = true

        await model.loadCapabilities()

        XCTAssertNil(model.hardwareScanAreaBounds)
        XCTAssertNil(model.selectedHardwareScanArea)

        model.selectedHardwareScanArea = ScanArea(widthMM: 12, heightMM: 8)
        await model.runScan(preview: false)

        XCTAssertEqual(backend.fullRequests.only?.scanArea, .fullFrame35mm)
    }

    func testLibraryLifecycleGateBlocksScanCapabilityAndDirectEntryPoint() async {
        let backend = ScannerWorkflowBackend(capabilities: Self.usableCapabilities)
        let model = AppModel(scannerDemoBackend: backend)
        model.demoMode = true
        await model.loadCapabilities()
        XCTAssertTrue(model.canScan)

        model.transitionLibraryLifecycle(to: .restoring)
        XCTAssertFalse(model.canScan)
        await model.scanFrames(count: 1, preview: false)
        XCTAssertEqual(backend.fullRequestCount, 0)
        XCTAssertTrue(model.frames.isEmpty)

        model.transitionLibraryLifecycle(to: .blocked)
        XCTAssertFalse(model.canScan)
        await model.runScan(preview: true)
        XCTAssertEqual(backend.previewRequestCount, 0)

        model.transitionLibraryLifecycle(to: .ready)
        XCTAssertTrue(model.canScan)
    }

    func testSuccessfulFullScanReplacesEphemeralPreviewAndKeepsFrameNumber() async {
        let backend = ScannerWorkflowBackend(capabilities: Self.usableCapabilities)
        let fixture: PersistentScannerFixture
        do {
            fixture = try await makePersistentFixture(backend: backend)
        } catch {
            XCTFail("테스트 fixture 생성 실패: \(error)")
            return
        }
        defer { fixture.cleanup() }
        let model = fixture.model
        model.demoMode = true
        await model.loadCapabilities()

        await model.runScan(preview: true)
        let preview = try? XCTUnwrap(model.frames.only)
        XCTAssertEqual(preview?.scanIndex, 1)
        XCTAssertEqual(preview?.isPreviewScan, true)
        XCTAssertNil(model.sourceDeletionPlan(for: preview.map { [$0] } ?? []))

        await model.runScan(preview: false)

        let fullScan = try? XCTUnwrap(model.frames.only)
        XCTAssertEqual(fullScan?.scanIndex, 1)
        XCTAssertEqual(fullScan?.isPreviewScan, false)
        XCTAssertEqual(backend.previewRequestCount, 1)
        XCTAssertEqual(backend.fullRequestCount, 1)
        let session = try? XCTUnwrap(model.scanSessions.only)
        let job = try? XCTUnwrap(session?.jobs.only)
        let assignment = try? XCTUnwrap(model.scanRollAssignments.only)
        XCTAssertEqual(session?.closedAt != nil, true)
        XCTAssertEqual(job?.state, .succeeded)
        XCTAssertEqual(fullScan?.scanSessionID, session?.id)
        XCTAssertEqual(fullScan?.scanJobID, job?.id)
        XCTAssertEqual(job?.requestedOptions.requestID, job?.id)
        XCTAssertEqual(backend.fullRequests.only?.requestID, job?.id)
        XCTAssertEqual(model.rollID(containing: fullScan?.id ?? UUID()), assignment?.rollID)
        XCTAssertEqual(assignment?.draftName, model.text(.untitledFilm))
        XCTAssertEqual(fullScan?.storageGroupName, model.text(.untitledFilm))
        XCTAssertEqual(
            backend.fullRequests.only?.temporaryOutputURL?.deletingLastPathComponent().lastPathComponent,
            model.text(.untitledFilm)
        )
        XCTAssertEqual(
            backend.fullRequests.only?.temporaryOutputURL?
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .lastPathComponent,
            FrameStorageNaming.filmTypeFolderName(model.scanFilmType)
        )

        let catalog = LibraryCatalogFile.loadPrimary(from: fixture.catalogURL)
        XCTAssertEqual(catalog?.frames.map(\.id), fullScan.map { [$0.id] })
        XCTAssertEqual(catalog?.scanSessions.map(\.id), model.scanSessions.map(\.id))
        XCTAssertEqual(
            catalog?.scanSessions.first?.jobs.map { "\($0.id.uuidString):\($0.state.rawValue)" },
            model.scanSessions.first?.jobs.map { "\($0.id.uuidString):\($0.state.rawValue)" }
        )
        XCTAssertEqual(
            catalog?.scanRollAssignments.map {
                "\($0.sessionID.uuidString):\($0.rollID.uuidString)"
            },
            model.scanRollAssignments.map {
                "\($0.sessionID.uuidString):\($0.rollID.uuidString)"
            }
        )
        if let catalog {
            XCTAssertTrue(
                LibraryCatalogHealthInspector.inspect(
                    catalog,
                    defectDirectory: fixture.defectDirectoryURL
                ).canOpenSafely
            )
        }
    }

    func testScanFilmTypeControlsCaptureFolderWhileDevelopProcessCanDiffer() async throws {
        let backend = ScannerWorkflowBackend(capabilities: Self.usableCapabilities)
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        model.demoMode = true
        await model.loadCapabilities()

        model.selectScanFilmType(.colorPositive)
        model.applyDevelopmentProcess(.bwNegative, to: nil)
        await model.runScan(preview: false)

        let request = try XCTUnwrap(backend.fullRequests.only)
        XCTAssertEqual(request.filmType, .colorPositive)
        XCTAssertEqual(
            request.temporaryOutputURL?
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .lastPathComponent,
            "color-slide"
        )
        XCTAssertEqual(model.scanRollAssignments.only?.filmType, .colorPositive)
        XCTAssertEqual(model.scanRollAssignments.only?.developFilmType, .bwNegative)
        XCTAssertEqual(model.frames.only?.filmType, .bwNegative)
        XCTAssertEqual(model.frames.only?.params.filmType, .bwNegative)
    }

    func testEditableScanFolderNameIsSanitizedInsideConfiguredScanRoot() async throws {
        let backend = ScannerWorkflowBackend(capabilities: Self.usableCapabilities)
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        model.demoMode = true
        await model.loadCapabilities()

        model.updateScanFolderName("  Summer/2026  ")
        await model.runScan(preview: false)

        let outputFolder = try XCTUnwrap(
            backend.fullRequests.only?.temporaryOutputURL?.deletingLastPathComponent()
        )
        XCTAssertEqual(outputFolder.lastPathComponent, "Summer2026")
        XCTAssertEqual(outputFolder.deletingLastPathComponent().lastPathComponent, "color-negative")
        XCTAssertTrue(
            outputFolder.standardizedFileURL.path.hasPrefix(
                model.diskStorage.scansURL.standardizedFileURL.path
            )
        )
        XCTAssertEqual(model.scanRollAssignments.only?.draftName, "Summer2026")
    }

    func testDevelopProcessCanChangeBeforeFullScanCompletes() async throws {
        let backend = ScannerWorkflowBackend(
            capabilities: Self.usableCapabilities,
            suspendScans: true
        )
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        model.demoMode = true
        await model.loadCapabilities()

        let scanTask = Task { await model.runScan(preview: false) }
        while !backend.hasPendingScan { await Task.yield() }

        model.applyDevelopmentProcess(.bwPositive, to: nil)
        XCTAssertEqual(model.scanRollAssignments.only?.developFilmType, .bwPositive)
        _ = try backend.completePendingScan(createOutput: true)
        await scanTask.value

        XCTAssertEqual(backend.fullRequests.only?.filmType, .colorNegative)
        XCTAssertEqual(model.frames.only?.filmType, .bwPositive)
        XCTAssertEqual(model.frames.only?.params.filmType, .bwPositive)
        XCTAssertEqual(
            LibraryCatalogFile.loadPrimary(from: fixture.catalogURL)?
                .scanRollAssignments.only?.developFilmType,
            .bwPositive
        )
    }

    func testSelectingScanStorageRootUpdatesDiskSettingsSourceOfTruth() {
        let suiteName = "negaflow.scan-storage-root.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DiskStorageStore(defaults: defaults)
        let model = AppModel(diskStorageStore: store)
        let selected = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-selected-scan-root-\(UUID().uuidString)",
            isDirectory: true
        )

        model.selectScanStorageRoot(selected)

        XCTAssertEqual(store.locationMode, .custom)
        XCTAssertEqual(store.scansURL, selected.standardizedFileURL)
        XCTAssertEqual(DiskStorageStore(defaults: defaults).scansURL, selected.standardizedFileURL)
    }

    func testFullScanUsesMostRecentlyCreatedLibraryFolder() async throws {
        let backend = ScannerWorkflowBackend(capabilities: Self.usableCapabilities)
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        let parent = fixture.root.appendingPathComponent("created-folders", isDirectory: true)
        _ = try XCTUnwrap(model.createLibraryFolder(named: "First Roll", in: parent))
        let latest = try XCTUnwrap(model.createLibraryFolder(named: "Latest Roll", in: parent))
        model.demoMode = true
        await model.loadCapabilities()

        await model.runScan(preview: false)

        let request = try XCTUnwrap(backend.fullRequests.only)
        XCTAssertEqual(
            request.temporaryOutputURL?.deletingLastPathComponent().standardizedFileURL,
            latest
        )
        XCTAssertEqual(model.frames.only?.rawScanURL.deletingLastPathComponent(), latest)
        XCTAssertEqual(model.scanRollAssignments.only?.draftName, "Latest Roll")
    }

    func testEmptyFilmFolderStartsAtFrameOneDespiteExistingLibraryNumbers() async throws {
        let backend = ScannerWorkflowBackend(capabilities: Self.usableCapabilities)
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        let legacyFolder = fixture.root.appendingPathComponent("legacy", isDirectory: true)
        let screenshotFolder = fixture.root.appendingPathComponent("screenshot", isDirectory: true)
        try FileManager.default.createDirectory(
            at: legacyFolder,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: screenshotFolder,
            withIntermediateDirectories: true
        )
        let existingFirst = ScanFrame(
            scanIndex: 1,
            rawScanURL: legacyFolder.appendingPathComponent("first.tiff"),
            filmType: .colorNegative
        )
        let existingFortyEight = ScanFrame(
            scanIndex: 48,
            rawScanURL: screenshotFolder.appendingPathComponent("OpticFilm8100_frame_1.tiff"),
            filmType: .colorNegative
        )
        model.frames = [existingFirst, existingFortyEight]
        let firstLegacyRoll = try XCTUnwrap(LibraryRoll.physical(
            name: "Legacy",
            filmType: .colorNegative,
            frameIDs: [existingFirst.id]
        ))
        let screenshotRoll = try XCTUnwrap(LibraryRoll.physical(
            name: "Screenshot",
            filmType: .colorNegative,
            frameIDs: [existingFortyEight.id]
        ))
        model.replaceRollState(with: RollStoreSnapshot(
            rolls: [firstLegacyRoll, screenshotRoll],
            activeRollID: nil
        ))
        XCTAssertEqual(existingFortyEight.displayName(language: .korean), "사진 1")
        model.demoMode = true
        await model.loadCapabilities()

        await model.runScan(preview: false)

        XCTAssertEqual(model.frames.count, 3)
        let newFrame = try XCTUnwrap(model.frames.last)
        XCTAssertEqual(newFrame.scanIndex, 1)
        XCTAssertEqual(newFrame.displayName(language: .korean), "사진 1")
        XCTAssertEqual(
            newFrame.rawScanURL.deletingLastPathComponent().lastPathComponent,
            model.text(.untitledFilm)
        )
        XCTAssertEqual(model.rollID(containing: newFrame.id), model.activeRollID)
    }

    func testLegacyActiveScannerDateRollDoesNotOverrideUntitledFilmFolder() async throws {
        let backend = ScannerWorkflowBackend(capabilities: Self.usableCapabilities)
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        let scannerAbbreviation = FrameStorageNaming.scannerAbbreviation(
            "Plustek OpticFilm 8200i (Demo)"
        )
        let legacyName = "\(scannerAbbreviation) 20260712"
        let legacyFolder = fixture.root.appendingPathComponent(legacyName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: legacyFolder,
            withIntermediateDirectories: true
        )
        let legacySource = legacyFolder.appendingPathComponent(
            "\(scannerAbbreviation)_frame_1.tiff"
        )
        try Data([0]).write(to: legacySource)
        let legacyFrame = ScanFrame(
            scanIndex: 48,
            rawScanURL: legacySource,
            filmType: .colorNegative
        )
        let legacyRoll = try XCTUnwrap(LibraryRoll.physical(
            name: legacyName,
            filmType: .colorNegative,
            frameIDs: [legacyFrame.id]
        ))
        model.frames = [legacyFrame]
        model.replaceRollState(with: RollStoreSnapshot(
            rolls: [legacyRoll],
            activeRollID: legacyRoll.id
        ))
        model.demoMode = true
        await model.loadCapabilities()

        await model.runScan(preview: false)

        XCTAssertEqual(model.frames.count, 2)
        let newFrame = try XCTUnwrap(model.frames.last)
        XCTAssertEqual(newFrame.storageGroupName, model.text(.untitledFilm))
        XCTAssertEqual(
            newFrame.rawScanURL.deletingLastPathComponent().lastPathComponent,
            model.text(.untitledFilm)
        )
        XCTAssertNotEqual(model.rollID(containing: newFrame.id), legacyRoll.id)
        XCTAssertEqual(model.rollID(containing: newFrame.id), model.activeRollID)
    }

    func testBuiltInMockIdentityMatchesDetectedDescriptor() async throws {
        let descriptors = try await MockScannerBackend().detectScanners()
        XCTAssertEqual(descriptors.count, 2)
        XCTAssertEqual(descriptors[0].id, AppModel.mockDeviceID)
        XCTAssertEqual(descriptors[0].displayName, AppModel.mockDisplayName)
        XCTAssertEqual(descriptors[1].id, AppModel.mockFlatbedDeviceID)
        XCTAssertEqual(descriptors[1].displayName, AppModel.mockFlatbedDisplayName)
    }

    func testBuiltInScannerSimulatorSelectsBetweenFilmAndFlatbedWorkflows() async {
        let backend = MockScannerBackend()
        let model = AppModel(scannerDemoBackend: backend)
        model.demoMode = true

        await model.loadCapabilities()

        XCTAssertEqual(model.selectableScannerDevices.map(\.displayName), [
            "negaflow Scanner",
            "negaflow Flatbed Scanner",
        ])
        XCTAssertEqual(model.effectiveScannerID, AppModel.mockDeviceID)
        XCTAssertFalse(model.usesFlatbedRegionWorkflow)
        XCTAssertEqual(model.capabilities?.supportedResolutions, [.r900, .r1800, .r3600, .r7200])
        model.setScannerSimulatorIncludesPerforation(true)
        XCTAssertTrue(model.scannerSimulatorIncludesPerforation)
        XCTAssertTrue(backend.simulatorIncludesPerforation)

        model.selectedDeviceID = AppModel.mockFlatbedDeviceID
        await model.loadCapabilities()

        XCTAssertEqual(model.effectiveScannerID, AppModel.mockFlatbedDeviceID)
        XCTAssertTrue(model.usesFlatbedRegionWorkflow)
        XCTAssertEqual(
            model.hardwareScanAreaBounds?.maximum,
            ScanArea(widthMM: 210, heightMM: 297)
        )
        model.setScannerSimulatorFrameCount(4)
        model.setScannerSimulatorFrameOrientation(.portrait)
        XCTAssertEqual(model.scannerSimulatorFrameCount, 4)
        XCTAssertEqual(model.scannerSimulatorFrameOrientation, .portrait)
        XCTAssertEqual(backend.simulatorFrameCount, 4)
        XCTAssertEqual(backend.simulatorFrameOrientation, .portrait)
    }

    func testFlatbedScannerSimulatorHandlesMixedOrientationsAndMissingSlots() async throws {
        let backend = MockScannerBackend()
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        model.demoMode = true
        model.selectedDeviceID = MockScannerBackend.flatbedScannerID
        await model.loadCapabilities()
        await model.selectScanFrameFormat(.medium67)
        backend.setSimulatorFrameLayout(
            orientations: [.landscape, .portrait, .landscape, .portrait, .landscape, .portrait],
            missingFrameIndices: [1, 4]
        )

        await model.runScan(preview: true)

        XCTAssertEqual(model.flatbedScanRegions.count, 4)
        XCTAssertTrue(model.flatbedScanRegions.allSatisfy { $0.source == .automatic })
        let previewFrame = try XCTUnwrap(model.flatbedPreviewFrame)
        let previewWidth = Double(try XCTUnwrap(previewFrame.sourcePixelWidth))
        let previewHeight = Double(try XCTUnwrap(previewFrame.sourcePixelHeight))
        let aspects: [Double] = model.flatbedScanRegions.map { region in
            let pixelWidth = Double(region.unitRect.width) * previewWidth
            let pixelHeight = Double(region.unitRect.height) * previewHeight
            return pixelWidth / pixelHeight
        }
        XCTAssertTrue(aspects.contains {
            abs($0 / FilmFrameOrientation.landscape.aspect(for: .medium67) - 1) <= 0.12
        })
        XCTAssertTrue(aspects.contains {
            abs($0 / FilmFrameOrientation.portrait.aspect(for: .medium67) - 1) <= 0.12
        })

        await model.runScan(preview: false)

        XCTAssertEqual(model.scanSessions.only?.jobs.count, 4)
        XCTAssertTrue(model.scanSessions.only?.jobs.allSatisfy { $0.state == .succeeded } == true)
        XCTAssertEqual(model.frames.count, 4)
    }

    func testFlatbedScannerSimulatorUniformControlsClearCustomMissingLayout() {
        let backend = MockScannerBackend()
        backend.setSimulatorFrameLayout(
            orientations: [.landscape, .portrait, .landscape, .portrait],
            missingFrameIndices: [1, 3]
        )

        backend.setSimulatorFrameCount(6)

        XCTAssertEqual(backend.simulatorFrameCount, 6)
        XCTAssertNil(backend.simulatorFrameOrientations)
        XCTAssertTrue(backend.simulatorMissingFrameIndices.isEmpty)

        backend.setSimulatorFrameLayout(
            orientations: [.portrait, .landscape, .portrait],
            missingFrameIndices: [0]
        )
        backend.setSimulatorFrameOrientation(.landscape)

        XCTAssertEqual(backend.simulatorFrameOrientation, .landscape)
        XCTAssertNil(backend.simulatorFrameOrientations)
        XCTAssertTrue(backend.simulatorMissingFrameIndices.isEmpty)
    }

    func testRestoreMarksRunningInterruptedAndDoesNotAutoRunQueuedHardware() async throws {
        let backend = ScannerWorkflowBackend(capabilities: Self.usableCapabilities)
        let fixture = try await makePersistentFixture(backend: backend, restore: false)
        defer { fixture.cleanup() }
        let sessionID = UUID()
        let firstJobID = UUID()
        let secondJobID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let startedAt = createdAt.addingTimeInterval(1)
        let first = try makeQueuedWorkflowJob(
            sessionID: sessionID,
            jobID: firstJobID,
            ordinal: 1,
            scanIndex: 11,
            createdAt: createdAt,
            outputURL: fixture.root.appendingPathComponent("running.tiff")
        ).started(at: startedAt)
        let second = try makeQueuedWorkflowJob(
            sessionID: sessionID,
            jobID: secondJobID,
            ordinal: 2,
            scanIndex: 12,
            createdAt: createdAt,
            outputURL: fixture.root.appendingPathComponent("queued.tiff")
        )
        let session = try makeMockSession(
            id: sessionID,
            createdAt: createdAt,
            jobs: [first, second]
        )
        let assignment = makeAssignment(sessionID: sessionID, createdAt: createdAt)
        try writeCatalog(
            LibraryCatalog(
                rolls: [],
                scanSessions: [session],
                scanRollAssignments: [assignment]
            ),
            to: fixture.catalogURL
        )

        await fixture.model.restoreLibraryOnLaunch()

        let restored = try XCTUnwrap(fixture.model.scanSessions.only)
        XCTAssertEqual(restored.jobs[0].state, .failed)
        XCTAssertEqual(restored.jobs[0].failure?.code, .interrupted)
        XCTAssertNil(restored.jobs[0].pendingCapture)
        XCTAssertEqual(restored.jobs[1].state, .queued)
        XCTAssertNil(restored.closedAt)
        XCTAssertEqual(backend.fullRequestCount, 0)
        XCTAssertTrue(fixture.model.frames.isEmpty)
        let persisted = try XCTUnwrap(
            LibraryCatalogFile.loadPrimary(from: fixture.catalogURL)?.scanSessions.only
        )
        XCTAssertEqual(persisted.jobs[0].failure?.code, .interrupted)
        XCTAssertEqual(persisted.jobs[1].state, .queued)
    }

    func testRestoreFinalizesDurableReceiptWithoutCallingHardware() async throws {
        let backend = ScannerWorkflowBackend(capabilities: Self.usableCapabilities)
        let fixture = try await makePersistentFixture(backend: backend, restore: false)
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        let rawURL = fixture.root.appendingPathComponent("captured.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 8, height: 6, to: rawURL)
        let sessionID = UUID()
        let jobID = UUID()
        let frameID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_100)
        let startedAt = createdAt.addingTimeInterval(1)
        let completedAt = createdAt.addingTimeInterval(2)
        var options = ScanOptions.strongDefault(scannerID: "mock-plustek-8200i")
        options.requestID = jobID
        options.temporaryOutputURL = rawURL
        let publication = try ScanFramePublicationSnapshot(
            frameID: frameID,
            scanIndex: 42,
            initialTransform: ImageTransform(rotation: .deg90, flipHorizontal: true),
            developTarget: .rescue,
            scannerProfileID: "test-profile",
            presetID: "neutral",
            storageGroupName: "RecoveryScanner"
        )
        let result = ScanResult(
            rawFileURL: rawURL,
            width: 8,
            height: 6,
            resolution: options.resolution,
            bitDepth: options.bitDepth,
            backendUsed: .mock,
            appliedOptionsEvidence: .verified(options)
        )
        let pending = try PendingCaptureSnapshot(
            scanResult: result,
            captureStartedAt: startedAt,
            captureCompletedAt: completedAt
        )
        let finalizing = try ScanJob(
            id: jobID,
            sessionID: sessionID,
            ordinal: 1,
            kind: .full,
            requestedOptions: options,
            framePublication: publication,
            createdAt: createdAt
        ).started(at: startedAt).finalizing(with: pending, at: completedAt)
        let session = try makeMockSession(
            id: sessionID,
            createdAt: createdAt,
            jobs: [finalizing]
        )
        let assignment = makeAssignment(sessionID: sessionID, createdAt: createdAt)
        try writeCatalog(
            LibraryCatalog(
                rolls: [],
                scanSessions: [session],
                scanRollAssignments: [assignment]
            ),
            to: fixture.catalogURL
        )

        await fixture.model.restoreLibraryOnLaunch()

        XCTAssertEqual(backend.fullRequestCount, 0)
        let frame = try XCTUnwrap(fixture.model.frames.only)
        XCTAssertEqual(frame.id, frameID)
        XCTAssertEqual(frame.scanIndex, 42)
        XCTAssertEqual(frame.scanSessionID, sessionID)
        XCTAssertEqual(frame.scanJobID, jobID)
        XCTAssertEqual(frame.imageTransform, publication.initialTransform)
        XCTAssertEqual(frame.params.developTarget, .rescue)
        XCTAssertEqual(frame.params.scannerProfileID, "test-profile")
        XCTAssertEqual(frame.storageGroupName, "RecoveryScanner")
        XCTAssertEqual(frame.scannedAt, completedAt)
        let restoredSession = try XCTUnwrap(fixture.model.scanSessions.only)
        XCTAssertEqual(restoredSession.jobs.only?.state, .succeeded)
        XCTAssertNotNil(restoredSession.closedAt)
        XCTAssertEqual(fixture.model.rollID(containing: frameID), assignment.rollID)
        let catalog = try XCTUnwrap(LibraryCatalogFile.loadPrimary(from: fixture.catalogURL))
        XCTAssertTrue(
            LibraryCatalogHealthInspector.inspect(
                catalog,
                defectDirectory: fixture.defectDirectoryURL
            ).canOpenSafely
        )
    }

    func testRestoreDoesNotAutoRetryFailedFinalizationReceipt() async throws {
        let backend = ScannerWorkflowBackend(capabilities: Self.usableCapabilities)
        let fixture = try await makePersistentFixture(backend: backend, restore: false)
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        let rawURL = fixture.root.appendingPathComponent("failed-finalization.tiff")
        try Data("receipt".utf8).write(to: rawURL)
        let sessionID = UUID()
        let jobID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_200)
        let startedAt = createdAt.addingTimeInterval(1)
        let completedAt = createdAt.addingTimeInterval(2)
        var options = ScanOptions.strongDefault(scannerID: "mock-plustek-8200i")
        options.requestID = jobID
        options.temporaryOutputURL = rawURL
        let pending = try PendingCaptureSnapshot(
            scanResult: ScanResult(
                rawFileURL: rawURL,
                width: 4,
                height: 3,
                resolution: options.resolution,
                bitDepth: options.bitDepth,
                backendUsed: .mock,
                appliedOptionsEvidence: .verified(options)
            ),
            captureStartedAt: startedAt,
            captureCompletedAt: completedAt
        )
        let queued = try makeQueuedWorkflowJob(
            sessionID: sessionID,
            jobID: jobID,
            ordinal: 1,
            scanIndex: 7,
            createdAt: createdAt,
            outputURL: rawURL
        )
        let failed = try queued.started(at: startedAt)
            .finalizing(with: pending, at: completedAt)
            .failed(with: ScannerError(.ioFailure, "hash failed"), at: completedAt.addingTimeInterval(1))
        let session = try makeMockSession(
            id: sessionID,
            createdAt: createdAt,
            jobs: [failed]
        )
        let assignment = makeAssignment(sessionID: sessionID, createdAt: createdAt)
        try writeCatalog(
            LibraryCatalog(
                rolls: [],
                scanSessions: [session],
                scanRollAssignments: [assignment]
            ),
            to: fixture.catalogURL
        )

        await fixture.model.restoreLibraryOnLaunch()

        let restored = try XCTUnwrap(fixture.model.scanSessions.only?.jobs.only)
        XCTAssertEqual(restored.state, .failed)
        XCTAssertEqual(restored.attempt, 1)
        XCTAssertEqual(restored.pendingCapture, pending)
        XCTAssertTrue(fixture.model.frames.isEmpty)
        XCTAssertEqual(backend.fullRequestCount, 0)
    }

    func testQueuedCatalogCommitFailurePreventsHardwareStart() async throws {
        let backend = ScannerWorkflowBackend(capabilities: Self.usableCapabilities)
        let fixture = try await makePersistentFixture(backend: backend, restore: false)
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(
            at: fixture.root,
            withIntermediateDirectories: true
        )
        try Data("not a directory".utf8).write(
            to: fixture.catalogURL.deletingLastPathComponent(),
            options: .atomic
        )
        fixture.model.libraryPersistenceEnabled = true
        fixture.model.demoMode = true
        await fixture.model.loadCapabilities()

        await fixture.model.runScan(preview: false)

        XCTAssertEqual(backend.fullRequestCount, 0)
        XCTAssertTrue(fixture.model.scanSessions.isEmpty)
        XCTAssertTrue(fixture.model.scanRollAssignments.isEmpty)
        XCTAssertTrue(fixture.model.frames.isEmpty)
        XCTAssertEqual(fixture.model.scanPhase, .error)
    }

    func testCancelRejectsLateResultAndRemovesUncommittedOutput() async throws {
        let backend = ScannerWorkflowBackend(
            capabilities: Self.usableCapabilities,
            suspendScans: true
        )
        let model = AppModel(scannerDemoBackend: backend)
        model.demoMode = true
        await model.loadCapabilities()

        let scanTask = Task { await model.runScan(preview: true) }
        while !backend.hasPendingScan { await Task.yield() }

        model.demoMode = false
        await model.cancelScan()
        let outputURL = try backend.completePendingScan(createOutput: true)
        await scanTask.value

        XCTAssertTrue(model.frames.isEmpty)
        XCTAssertFalse(model.isScanning)
        XCTAssertNil(model.activeScanSessionID)
        XCTAssertEqual(model.statusMessage, model.text(.scanCanceled))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(backend.cancelRequestCount, 1)
    }

    func testFullBatchReservesUniqueJobsOutputsAndPublishesInOrdinalOrder() async throws {
        let backend = ScannerWorkflowBackend(capabilities: Self.usableCapabilities)
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        model.demoMode = true
        await model.loadCapabilities()

        await model.scanFrames(count: 3, preview: false)

        let session = try XCTUnwrap(model.scanSessions.only)
        XCTAssertEqual(session.jobs.map(\.ordinal), [1, 2, 3])
        XCTAssertEqual(session.jobs.map(\.state), [.succeeded, .succeeded, .succeeded])
        XCTAssertEqual(session.jobs.map(\.id), backend.fullRequests.compactMap(\.requestID))
        XCTAssertEqual(Set(session.jobs.map(\.id)).count, 3)
        XCTAssertEqual(
            Set(session.jobs.compactMap(\.requestedOptions.temporaryOutputURL?.path)).count,
            3
        )
        XCTAssertEqual(model.frames.map(\.scanIndex), [1, 2, 3])
        XCTAssertEqual(model.frames.map(\.scanJobID), session.jobs.map { Optional($0.id) })
        XCTAssertEqual(Set(model.frames.compactMap { model.rollID(containing: $0.id) }).count, 1)
        let catalog = try XCTUnwrap(LibraryCatalogFile.loadPrimary(from: fixture.catalogURL))
        XCTAssertTrue(
            LibraryCatalogHealthInspector.inspect(
                catalog,
                defectDirectory: fixture.defectDirectoryURL
            ).canOpenSafely
        )
    }

    func testFullCancelPersistsRunningAndQueuedAsCancelledWithoutPublishingLateResult() async throws {
        let backend = ScannerWorkflowBackend(
            capabilities: Self.usableCapabilities,
            suspendScans: true
        )
        let fixture = try await makePersistentFixture(backend: backend)
        defer { fixture.cleanup() }
        let model = fixture.model
        model.demoMode = true
        await model.loadCapabilities()
        let scanTask = Task { await model.scanFrames(count: 2, preview: false) }
        while !backend.hasPendingScan { await Task.yield() }

        model.demoMode = false
        await model.cancelScan()
        let outputURL = try backend.completePendingScan(createOutput: true)
        await scanTask.value

        XCTAssertEqual(backend.cancelRequestCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertTrue(model.frames.isEmpty)
        let session = try XCTUnwrap(model.scanSessions.only)
        XCTAssertEqual(session.jobs.map(\.state), [.cancelled, .cancelled])
        XCTAssertNotNil(session.closedAt)
        let persisted = try XCTUnwrap(
            LibraryCatalogFile.loadPrimary(from: fixture.catalogURL)?.scanSessions.only
        )
        XCTAssertEqual(persisted.jobs.map(\.state), [.cancelled, .cancelled])
        XCTAssertNotNil(persisted.closedAt)
    }

    func testLatestCapabilityRequestWinsWhenEarlierResponseFinishesLate() async {
        let backend = DeferredCapabilitiesBackend()
        let model = AppModel(scannerDemoBackend: backend)
        model.demoMode = true
        let older = ScannerCapabilities(
            supportedResolutions: [.r900],
            supportedModes: [.gray],
            supportedBitDepths: [.eight]
        )
        let newer = ScannerCapabilities(
            supportedResolutions: [.r3600],
            supportedModes: [.color],
            supportedBitDepths: [.sixteen]
        )

        let firstTask = Task { await model.loadCapabilities() }
        await waitForCapabilityRequests(1, backend: backend)
        let secondTask = Task { await model.loadCapabilities() }
        await waitForCapabilityRequests(2, backend: backend)

        backend.completeRequest(at: 1, with: newer)
        await secondTask.value
        XCTAssertEqual(model.capabilities, newer)

        backend.completeRequest(at: 0, with: older)
        await firstTask.value
        XCTAssertEqual(model.capabilities, newer)
    }

    func testCapabilityResponseIsIgnoredAfterDeviceIdentityChanges() async {
        let backend = DeferredCapabilitiesBackend()
        let model = AppModel(scannerDemoBackend: backend)
        model.demoMode = true
        let requestTask = Task { await model.loadCapabilities() }
        await waitForCapabilityRequests(1, backend: backend)

        // 새 요청이 없어도 응답 적용 직전에 장치와 backend identity를 다시 확인해야 한다.
        model.demoMode = false
        backend.completeRequest(at: 0, with: Self.usableCapabilities)
        await requestTask.value

        XCTAssertNil(model.capabilities)
    }

    func testBackendDoesNotFallBackToPluginThatDoesNotOwnSelectedDevice() {
        let model = AppModel()
        let selectedID = "plugin:owner:device"
        model.devices = [ScannerDescriptor(
            id: selectedID,
            displayName: "Selected Scanner",
            vendor: "Test",
            model: "Selected",
            backendType: .plugin
        )]
        model.selectedDeviceID = selectedID
        let manifest = ScannerPluginManifest(
            schemaVersion: 1,
            id: "other",
            name: "Other Plugin",
            executable: "other"
        )
        model.pluginBackends = [ExternalScannerBackend(plugin: InstalledScannerPlugin(
            manifest: manifest,
            manifestURL: URL(fileURLWithPath: "/tmp/other-manifest.json"),
            executableURL: URL(fileURLWithPath: "/usr/bin/true")
        ))]

        XCTAssertNil(model.backend)
    }

    private func waitForCapabilityRequests(
        _ count: Int,
        backend: DeferredCapabilitiesBackend
    ) async {
        for _ in 0..<1_000 {
            if backend.requestCount >= count { return }
            await Task.yield()
        }
        XCTFail("capability 요청 \(count)개가 시작되지 않았습니다")
    }

    private static let usableCapabilities = ScannerCapabilities(
        supportedResolutions: [.r3600],
        supportedModes: [.color],
        supportedBitDepths: [.eight, .sixteen],
        supportsPreview: true
    )

    private func makeQueuedWorkflowJob(
        sessionID: UUID,
        jobID: UUID,
        ordinal: Int,
        scanIndex: Int,
        createdAt: Date,
        outputURL: URL
    ) throws -> ScanJob {
        var options = ScanOptions.strongDefault(scannerID: "mock-plustek-8200i")
        options.requestID = jobID
        options.temporaryOutputURL = outputURL
        return try ScanJob(
            id: jobID,
            sessionID: sessionID,
            ordinal: ordinal,
            kind: .full,
            requestedOptions: options,
            framePublication: try ScanFramePublicationSnapshot(
                frameID: jobID,
                scanIndex: scanIndex,
                initialTransform: .identity,
                developTarget: .main,
                storageGroupName: "RecoveryScanner"
            ),
            createdAt: createdAt
        )
    }

    private func makeMockSession(
        id: UUID,
        createdAt: Date,
        jobs: [ScanJob]
    ) throws -> ScanSession {
        try ScanSession(
            id: id,
            createdAt: createdAt,
            device: ScannerDescriptor(
                id: "mock-plustek-8200i",
                displayName: "Plustek OpticFilm 8200i (Demo)",
                vendor: "Plustek",
                model: "OpticFilm 8200i",
                backendType: .mock,
                connectionType: .internalBus,
                verifiedStatus: .verified,
                driverVersion: "test"
            ),
            backend: ScanBackendSnapshot(
                type: .mock,
                identifier: "builtin.mock",
                version: "test"
            ),
            environment: ScanEnvironmentSnapshot(
                applicationName: "negaflow",
                applicationVersion: "test",
                operatingSystem: "macOS",
                operatingSystemVersion: "test",
                architecture: "arm64"
            ),
            jobs: jobs
        )
    }

    private func makeAssignment(
        sessionID: UUID,
        createdAt: Date
    ) -> LibraryScanRollAssignment {
        LibraryScanRollAssignment(
            sessionID: sessionID,
            rollID: UUID(),
            draftName: "Recovery Roll",
            filmType: .colorNegative,
            createdAt: createdAt
        )
    }

    private func writeCatalog(_ catalog: LibraryCatalog, to url: URL) throws {
        let data = try XCTUnwrap(LibraryCatalogFile.encode(catalog))
        XCTAssertTrue(LibraryCatalogFile.writeSync(data, to: url))
    }

    private func waitForDevelopedThumbnail(_ frame: ScanFrame, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while frame.thumbnailImage == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func makePersistentFixture(
        backend: ScannerBackend,
        restore: Bool = true
    ) async throws -> PersistentScannerFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-scanner-workflow-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        let support = root.appendingPathComponent("support", isDirectory: true)
        let defaultsName = "negaflow.scanner-workflow-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let diskStorage = DiskStorageStore(defaults: defaults)
        diskStorage.locationMode = .custom
        diskStorage.rootPath = root.appendingPathComponent("storage", isDirectory: true).path
        diskStorage.scansPath = root.appendingPathComponent("storage/Scans", isDirectory: true).path
        diskStorage.scanPreviewsPath = root.appendingPathComponent("storage/Scan Previews", isDirectory: true).path
        let catalogURL = support.appendingPathComponent("library.json")
        let defectDirectoryURL = support.appendingPathComponent("defects", isDirectory: true)
        let backupDirectoryURL = support.appendingPathComponent("Backups", isDirectory: true)
        let model = AppModel(
            diskStorageStore: diskStorage,
            scannerDemoBackend: backend,
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: defectDirectoryURL,
            libraryBackupDirectoryURL: backupDirectoryURL
        )
        if restore { await model.restoreLibraryOnLaunch() }
        return PersistentScannerFixture(
            model: model,
            root: root,
            defaultsName: defaultsName,
            catalogURL: catalogURL,
            defectDirectoryURL: defectDirectoryURL
        )
    }
}

@MainActor
private struct PersistentScannerFixture {
    let model: AppModel
    let root: URL
    let defaultsName: String
    let catalogURL: URL
    let defectDirectoryURL: URL

    func cleanup() {
        model.libraryPersistenceEnabled = false
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        UserDefaults.standard.removePersistentDomain(forName: defaultsName)
        try? FileManager.default.removeItem(at: root)
    }
}

private final class DeferredCapabilitiesBackend: ScannerBackend, @unchecked Sendable {
    let backendType: BackendType = .mock
    private let lock = NSLock()
    private var requests: [CheckedContinuation<ScannerCapabilities, Error>?] = []

    var requestCount: Int { locked { requests.count } }

    func detectScanners() async throws -> [ScannerDescriptor] {
        [ScannerDescriptor(
            id: "mock-plustek-8200i",
            displayName: "Plustek OpticFilm 8200i (Demo)",
            vendor: "Plustek",
            model: "OpticFilm 8200i",
            backendType: .mock,
            connectionType: .internalBus,
            verifiedStatus: .verified,
            driverVersion: "test"
        )]
    }

    func getCapabilities(scannerID: String) async throws -> ScannerCapabilities {
        try await withCheckedThrowingContinuation { continuation in
            locked { requests.append(continuation) }
        }
    }

    func completeRequest(at index: Int, with capabilities: ScannerCapabilities) {
        let continuation = locked { () -> CheckedContinuation<ScannerCapabilities, Error>? in
            guard requests.indices.contains(index) else { return nil }
            defer { requests[index] = nil }
            return requests[index]
        }
        continuation?.resume(returning: capabilities)
    }

    func startPreviewScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        throw ScannerError(.unsupportedOption, "test backend")
    }

    func startFullScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        throw ScannerError(.unsupportedOption, "test backend")
    }

    func cancelScan() async {}
    func getLastError() -> ScannerError? { nil }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

private final class ScannerWorkflowBackend: ScannerBackend, @unchecked Sendable {
    let backendType: BackendType
    let capabilities: ScannerCapabilities
    let suspendScans: Bool
    let resultBackendType: BackendType
    let distortsFullScanAspect: Bool

    private let lock = NSLock()
    private var pending: (CheckedContinuation<ScanResult, Error>, ScanOptions)?
    private(set) var previewRequestCount = 0
    private(set) var fullRequestCount = 0
    private(set) var fullRequests: [ScanOptions] = []
    private(set) var cancelRequestCount = 0

    init(
        capabilities: ScannerCapabilities,
        suspendScans: Bool = false,
        backendType: BackendType = .mock,
        resultBackendType: BackendType = .mock,
        distortsFullScanAspect: Bool = false
    ) {
        self.capabilities = capabilities
        self.suspendScans = suspendScans
        self.backendType = backendType
        self.resultBackendType = resultBackendType
        self.distortsFullScanAspect = distortsFullScanAspect
    }

    var hasPendingScan: Bool { locked { pending != nil } }

    func detectScanners() async throws -> [ScannerDescriptor] {
        [ScannerDescriptor(
            id: "mock-plustek-8200i",
            displayName: "Plustek OpticFilm 8200i (Demo)",
            vendor: "Plustek",
            model: "OpticFilm 8200i",
            backendType: backendType,
            connectionType: .internalBus,
            verifiedStatus: .verified,
            driverVersion: "test"
        )]
    }

    func getCapabilities(scannerID: String) async throws -> ScannerCapabilities { capabilities }

    func startPreviewScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        locked { previewRequestCount += 1 }
        return try await result(for: options, progress: progress)
    }

    func startFullScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        locked {
            fullRequestCount += 1
            fullRequests.append(options)
        }
        return try await result(for: options, progress: progress)
    }

    func cancelScan() async { locked { cancelRequestCount += 1 } }

    func getLastError() -> ScannerError? { nil }

    func completePendingScan(createOutput: Bool) throws -> URL {
        let work = locked { () -> (CheckedContinuation<ScanResult, Error>, ScanOptions)? in
            defer { pending = nil }
            return pending
        }
        guard let (continuation, options) = work,
              let outputURL = options.temporaryOutputURL else {
            throw ScannerError(.unknown, "No pending scan")
        }
        if createOutput {
            try Data("late scan".utf8).write(to: outputURL, options: .atomic)
        }
        continuation.resume(returning: makeResult(options))
        return outputURL
    }

    private func result(
        for options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        if suspendScans {
            return try await withCheckedThrowingContinuation { continuation in
                locked { pending = (continuation, options) }
            }
        }
        let outputURL = options.temporaryOutputURL
            ?? ScanTempFile.makeURL(prefix: "negaflow_test_scan", suffix: ".tiff")
        try Data("test scan".utf8).write(to: outputURL, options: .atomic)
        progress(ScanProgress(phase: .complete, fraction: 1))
        return makeResult(options)
    }

    private func makeResult(_ options: ScanOptions) -> ScanResult {
        let rawFileURL = options.temporaryOutputURL
            ?? ScanTempFile.makeURL(prefix: "negaflow_test_scan", suffix: ".tiff")
        var appliedOptions = options
        appliedOptions.temporaryOutputURL = rawFileURL
        let size: (width: Int, height: Int)
        if distortsFullScanAspect,
           resultBackendType != .mock,
           options.scanArea != capabilities.maxScanArea {
            size = (1_600, 1_600)
        } else {
            let longestSide = resultBackendType == .mock ? 32 : 1_600
            let ratio = options.scanArea.widthMM / options.scanArea.heightMM
            if ratio >= 1 {
                size = (longestSide, max(1, Int((Double(longestSide) / ratio).rounded())))
            } else {
                size = (max(1, Int((Double(longestSide) * ratio).rounded())), longestSide)
            }
        }
        return ScanResult(
            rawFileURL: rawFileURL,
            width: size.width,
            height: size.height,
            resolution: options.resolution,
            bitDepth: options.bitDepth,
            reportedResolution: resultBackendType != .mock ? options.resolution : nil,
            reportedBitDepth: resultBackendType != .mock ? options.bitDepth : nil,
            backendUsed: resultBackendType,
            appliedOptionsEvidence: .verified(appliedOptions)
        )
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
