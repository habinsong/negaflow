import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    // MARK: scan (단일 + 배치)
    func runScan(preview: Bool) async {
        await scanFrames(count: 1, preview: preview)
    }

    /// N프레임 연속 스캔. 한 번에 하나만(currentProcess 단일 슬롯).
    /// 배치 진행률 = (frameIndex + frameFraction) / totalFrames 로 리매핑.
    func scanFrames(count: Int, preview: Bool) async {
        guard allowsLibraryMutation, count > 0, !isScanning else { return }
        guard let id = effectiveScannerID, let backend = backend else {
            statusMessage = text(AppLocalizedPhrase.noScannerUseDemoStatus)
            return
        }
        guard let capabilities else {
            statusMessage = text(AppLocalizedPhrase.capabilityWaiting)
            return
        }
        if preview {
            guard capabilities.supportsPreview else {
                statusMessage = text(AppLocalizedPhrase.capabilityUnavailable)
                return
            }
        } else {
            guard resolutionChoice.dpi > 0,
                  capabilities.supports(resolution: resolutionChoice),
                  capabilities.supports(depth: bitDepthChoice),
                  capabilities.supports(mode: colorModeChoice) else {
                statusMessage = text(AppLocalizedPhrase.capabilityUnavailable)
                return
            }
        }
        let flatbedRegions = (!preview && usesFlatbedRegionWorkflow)
            ? flatbedScanRegions
            : []
        let selectedFlatbedPreviewArea = (!preview && usesFlatbedRegionWorkflow)
            ? flatbedPreviewScanArea
            : nil
        let effectiveCount = flatbedRegions.isEmpty ? count : flatbedRegions.count
        if !preview, usesFlatbedRegionWorkflow {
            guard flatbedPreviewFrame != nil,
                  selectedFlatbedPreviewArea != nil,
                  !flatbedRegions.isEmpty,
                  flatbedRegions.allSatisfy({
                      FlatbedScanRegionGeometry.physicalArea(
                          for: $0,
                          previewScanArea: selectedFlatbedPreviewArea,
                          capabilities: capabilities
                      ) != nil
                  }) else {
                statusMessage = text(AppLocalizedPhrase.flatbedPreviewRequired)
                return
            }
        }
        let sessionID = UUID()
        activeScanSessionID = sessionID
        activeScannerBackend = backend
        batchTotal = effectiveCount
        isScanning = true
        scanFraction = 0
        lastProgressFraction = 0
        lastProgressPhase = .idle
        lastProgressMessage = ""
        lastProgressUpdateAt = Date()
        let previewCarryover = preview ? nil : previewCarryoverFromSelectedPreviewFrame()
        if !preview {
            await scanFullFrames(
                count: effectiveCount,
                scannerID: id,
                backend: backend,
                capabilities: capabilities,
                sessionID: sessionID,
                previewCarryover: previewCarryover,
                flatbedRegions: flatbedRegions,
                flatbedPreviewScanArea: selectedFlatbedPreviewArea
            )
            return
        }
        for i in 0..<count {
            batchIndex = i
            scanFraction = 0
            var opts: ScanOptions
            if preview {
                opts = ScanOptions.preview(scannerID: id, filmType: scanFilmType)
                // 프리뷰도 본 스캔과 같은 현상 경로를 탄다. 프로필 없는 8bit TIFF는 감마 인코딩으로
                // 해석되므로, 선형 raw를 내보내는 백엔드(예: epson2 gamma=1.0)에서는 프리뷰가 흰색으로
                // 붕뜬다. 16bit를 먼저 요청해 "무프로필 16bit = linear" 규칙 안에 머무르게 한다.
                opts.bitDepth = capabilities.supports(depth: .sixteen)
                    ? .sixteen
                    : (capabilities.supports(depth: .eight) ? .eight : bitDepthChoice)
                opts.colorMode = capabilities.supports(mode: .color) ? .color : colorModeChoice
                if let bounds = capabilities.physicalScanAreaBounds {
                    opts.scanArea = bounds.maximum
                }
                // 평판 프리뷰는 그 위에서 필름 영역을 잡는 작업면이라 해상도를 장치 기본값에
                // 맡길 수 없다. 25dpi로 동작하던 기존 경로의 크기로는 프레임 자동 검출이
                // 시작조차 못 한다. 필름 전용 스캐너 프리뷰는 훑어보기라 지금처럼 백엔드
                // 프리뷰 경로를 그대로 쓴다.
                if usesFlatbedRegionWorkflow,
                   let previewResolution = Self.preferredFlatbedPreviewResolution(
                       in: capabilities.supportedResolutions
                   ) {
                    opts.resolution = previewResolution
                    // 외부 플러그인 계약상 양수 dpi는 full scan 요청이며 TIFF 산출물이
                    // 필수다. 앱에서는 결과만 프리뷰로 취급한다.
                    opts.outputRawTIFF = true
                }
            } else {
                opts = ScanOptions.strongDefault(scannerID: id)
                opts.resolution = resolutionChoice
                opts.bitDepth = bitDepthChoice
                opts.colorMode = colorModeChoice
                opts.filmType = scanFilmType
                opts.multiExposureEnabled = false
                opts.infraredEnabled = infraredEnabled
                    && capabilities.supportsInfrared
                    && InfraredFilmCompatibility(filmType: scanFilmType).allowsAutomaticCorrection
            }
            opts.brightnessAdjustment = Self.scannerHardwareAdjustment(
                scannerBrightness,
                range: capabilities.brightnessRange,
                scannerID: opts.scannerID,
                bitDepth: opts.bitDepth
            )
            opts.contrastAdjustment = Self.scannerHardwareAdjustment(
                scannerContrast,
                range: capabilities.contrastRange,
                scannerID: opts.scannerID,
                bitDepth: opts.bitDepth
            )
            let scannerAbbrev = FrameStorageNaming.scannerAbbreviation(activeScannerDisplayName)
            if preview {
                // 프리뷰 스캔은 본 스캔으로 대체되는 휘발 산출물 — 임시 폴더에 남긴다.
                opts.temporaryOutputURL = ScanTempFile.makeURL(
                    prefix: "negaflow_preview",
                    suffix: ".tiff",
                    in: diskStorage.scanPreviewsURL
                )
            } else {
                // 본 스캔 원본: <스캔 폴더>/<오늘 날짜>/<필름 타입>/<스캐너 축약>_frame_<번호>.tiff
                // (임시 폴더의 negaflow_app_<UUID> 명명 대체 — 라이브러리 영속화의 원본이 된다.)
                let folder = DiskStorageStore.ensureDirectory(
                    diskStorage.scansURL
                        .appendingPathComponent(FrameStorageNaming.dateFolderName(), isDirectory: true)
                        .appendingPathComponent(
                            FrameStorageNaming.filmTypeFolderName(scanFilmType),
                            isDirectory: true
                        )
                )
                let number = FrameStorageNaming.nextFrameNumber(in: folder, prefix: scannerAbbrev)
                opts.temporaryOutputURL = folder.appendingPathComponent(
                    FrameStorageNaming.scanFileBaseName(prefix: scannerAbbrev, number: number) + ".tiff"
                )
            }
            scanPhase = preview ? .previewScanning : .scanningRGB
            statusMessage = preview ? text(AppLocalizedPhrase.previewScanPreparing) : text(AppLocalizedPhrase.filmScanPreparing)
            do {
                // 해상도를 명시한 프리뷰는 백엔드 프리뷰 경로(해상도 미지정 계약)로 보낼 수
                // 없다. 저해상도 본 스캔으로 뜨고, 프레임만 프리뷰로 다룬다.
                let result = opts.resolution == .preview
                    ? try await backend.startPreviewScan(opts, progress: { [weak self] p in
                        Task { @MainActor in self?.update(p, sessionID: sessionID) }
                    })
                    : try await backend.startFullScan(opts, progress: { [weak self] p in
                        Task { @MainActor in self?.update(p, sessionID: sessionID) }
                    })
                guard activeScanSessionID == sessionID, allowsLibraryMutation else {
                    Self.removeUncommittedScanOutput(
                        result.rawFileURL,
                        infraredURL: result.infraredFileURL,
                        requestedURL: opts.temporaryOutputURL
                    )
                    if activeScanSessionID == sessionID {
                        activeScanSessionID = nil
                        batchTotal = 0
                        batchIndex = 0
                        isScanning = false
                        scanPhase = .idle
                        scanFraction = 0
                    }
                    return
                }
                var appliedFlatbedPreviewArea: ScanArea?
                if preview, usesFlatbedRegionWorkflow {
                    guard case .verified(let appliedOptions) = result.appliedOptionsEvidence else {
                        Self.removeUncommittedScanOutput(
                            result.rawFileURL,
                            infraredURL: result.infraredFileURL,
                            requestedURL: opts.temporaryOutputURL
                        )
                        throw ScannerError(
                            .ioFailure,
                            text(AppLocalizedPhrase.flatbedGeometryMismatch)
                        )
                    }
                    appliedFlatbedPreviewArea = appliedOptions.scanArea
                    if !FlatbedScanRegionGeometry.outputMatchesPhysicalAspect(
                           width: result.width,
                           height: result.height,
                           scanArea: appliedOptions.scanArea,
                           relativeTolerance: 0.02,
                           minimumPixelTolerance: 3
                       ) {
                        Self.removeUncommittedScanOutput(
                            result.rawFileURL,
                            infraredURL: result.infraredFileURL,
                            requestedURL: opts.temporaryOutputURL
                        )
                        throw ScannerError(
                            .ioFailure,
                            text(AppLocalizedPhrase.flatbedGeometryMismatch)
                                + " "
                                + FlatbedScanRegionGeometry.outputAspectDiagnostic(
                                    width: result.width,
                                    height: result.height,
                                    scanArea: appliedOptions.scanArea,
                                    requestedScanArea: opts.scanArea
                                )
                        )
                    }
                }
                scanFraction = 1
                let frame = ScanFrame(
                    scanIndex: nextScanIndex,
                    rawScanURL: result.rawFileURL,
                    filmType: scanDevelopFilmType,
                    infraredScanURL: preview ? nil : result.infraredFileURL,
                    sourcePixelWidth: result.width,
                    sourcePixelHeight: result.height,
                    sourceResolutionDPI: result.resolution.dpi,
                    sourceBitDepth: result.bitDepth.rawValue,
                    sourceMetadata: SourceMetadataReader.read(from: result.rawFileURL),
                    isPreviewScan: preview,
                    initialTransform: Self.scannerInitialTransform(
                        carryover: (!preview && i == 0) ? previewCarryover?.transform : nil,
                        template: nextScanOrientation,
                        defaultRotation: defaultScanRotation
                    ),
                    storageGroupName: scannerAbbrev
                )
                seedInitialThumbnail(for: frame, from: result.rawFileURL)
                frame.preset = presets.first(where: { $0.id == "neutral" })
                frame.updateParams {
                    $0.filmType = scanDevelopFilmType
                    $0.developTarget = developTarget
                    $0.scannerProfileID = scannerProfileID
                }
                frame.establishLibraryWorkflowBaselineIfNeeded()
                frames.append(frame)
                includeFrameInInteractionScopeIfNeeded(frame.id)
                selectedFrameID = frame.id
                removeEphemeralPreviewFrames(keeping: preview ? frame.id : nil)
                if preview {
                    prepareFlatbedPreview(frame, scanArea: appliedFlatbedPreviewArea)
                    await detectFlatbedScanRegions(for: frame, sessionID: sessionID)
                    guard activeScanSessionID == sessionID else { return }
                    guard allowsLibraryMutation else {
                        activeScanSessionID = nil
                        activeScannerBackend = nil
                        batchTotal = 0
                        batchIndex = 0
                        isScanning = false
                        scanPhase = .idle
                        scanFraction = 0
                        return
                    }
                }
                let dpiText = result.resolution.dpi > 0 ? " @ \(result.resolution.dpi)dpi" : ""
                statusMessage = text(AppLocalizedPhrase.frameScanCompleteFormat, frame.scanIndex, result.width, result.height, dpiText)
                if !preview, i == 0, let previewCarryover, let roi = previewCarryover.defectDisplayROI {
                    frame.defectGuidedSensitivity = previewCarryover.defectSensitivity
                    runRegionDetect(frame, displayROI: roi)
                }
                // 현상을 await하지 않고 백그라운드로 띄운다 → 스캐너가 현상 동안 유휴하지 않고
                // 다음 프레임 하드웨어 스캔을 곧바로 시작한다(배치 처리량↑). 품질/해상도는 불변.
                // 현상 진행은 프레임 썸네일 스피너 + 하단 processing 상태로 표시된다.
                // IR 채널이 함께 스캔됐으면 자동으로 IR 결함 제거를 돌린다(백그라운드).
                // 결과는 Defect Layer 로 쌓여 cleaned raw 에 반영되고 재현상으로 화면에 나타난다.
                developAfterScan(frame)
            } catch {
                guard activeScanSessionID == sessionID else { return }
                reportError(text(AppLocalizedPhrase.frameScanErrorFormat, i + 1, error.localizedDescription))
                break
            }
        }
        guard activeScanSessionID == sessionID else { return }
        activeScanSessionID = nil
        activeScannerBackend = nil
        batchTotal = 0
        batchIndex = 0
        isScanning = false
        if scanPhase != .error {
            scanPhase = .complete
            scanFraction = 1
            statusMessage = text(AppLocalizedPhrase.framesScanCompleteFormat, count)
        }
    }


}
