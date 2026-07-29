import Chromabase
import CoreGraphics
import Foundation
import ScannerKit

extension AppModel {
    var availableScanFrameFormats: [FilmFrameFormat] {
        guard let capabilities,
              capabilities.supportsPositionedScanArea != true
                || capabilities.supportsPreview,
              let maximum = hardwareScanAreaBounds?.maximum else { return [] }
        return FilmFrameFormat.allCases.filter { format in
            let standard = format.stripWidthMM <= maximum.widthMM
                && format.stripHeightMM <= maximum.heightMM
            let rotated = format.stripHeightMM <= maximum.widthMM
                && format.stripWidthMM <= maximum.heightMM
            return standard || rotated
        }
    }

    var usesFlatbedRegionWorkflow: Bool {
        guard let capabilities else { return false }
        return capabilities.supportsPositionedScanArea == true
            && capabilities.supportsPreview
            && capabilities.physicalScanAreaBounds != nil
    }

    var flatbedPreviewFrame: ScanFrame? {
        guard let flatbedPreviewFrameID else { return nil }
        return frames.first(where: { $0.id == flatbedPreviewFrameID && $0.isPreviewScan })
    }

    var canStartFullScan: Bool {
        canScan && (!usesFlatbedRegionWorkflow || (
            flatbedPreviewFrame != nil
                && flatbedPreviewScanArea != nil
                && !flatbedScanRegions.isEmpty
        ))
    }

    func resetFlatbedPreviewState() {
        flatbedScanRegions = []
        selectedFlatbedScanRegionID = nil
        flatbedPreviewFrameID = nil
        flatbedPreviewScanArea = nil
    }

    func selectScanFrameFormat(_ frameFormat: FilmFrameFormat) async {
        guard !isScanning,
              availableScanFrameFormats.contains(frameFormat),
              scanFrameFormat != frameFormat else { return }
        let existingPreview = flatbedPreviewFrame
        scanFrameFormat = frameFormat
        if !frameFormat.is35mm {
            scannerSimulatorIncludesPerforation = false
            (mockBackend as? MockScannerBackend)?.setSimulatorIncludesPerforation(false)
        }
        (mockBackend as? MockScannerBackend)?.setSimulatorFrameFormat(frameFormat)

        if usesFlatbedRegionWorkflow {
            flatbedScanRegions = []
            selectedFlatbedScanRegionID = nil
            if demoMode, existingPreview != nil {
                flatbedPreviewFrameID = nil
                flatbedPreviewScanArea = nil
                await runScan(preview: true)
            } else if let existingPreview {
                await detectFlatbedScanRegions(
                    for: existingPreview,
                    requiredSessionID: nil
                )
            }
        } else if capabilities?.supportsPositionedScanArea != true {
            applyFixedScannerArea(for: frameFormat)
        }
    }

    func clampScanFrameFormatSelection() {
        let formats = availableScanFrameFormats
        guard let selected = formats.contains(scanFrameFormat)
            ? scanFrameFormat
            : formats.first else { return }
        scanFrameFormat = selected
        (mockBackend as? MockScannerBackend)?.setSimulatorFrameFormat(selected)
        if capabilities?.supportsPositionedScanArea != true {
            applyFixedScannerArea(for: selected)
        }
    }

    private func applyFixedScannerArea(for frameFormat: FilmFrameFormat) {
        guard let capabilities,
              capabilities.supportsPositionedScanArea != true,
              let maximum = capabilities.physicalScanAreaBounds?.maximum else { return }
        let area = ScanArea(
            originXMM: maximum.originXMM
                + max(0, (maximum.widthMM - frameFormat.stripWidthMM) / 2),
            originYMM: maximum.originYMM
                + max(0, (maximum.heightMM - frameFormat.stripHeightMM) / 2),
            widthMM: frameFormat.stripWidthMM,
            heightMM: frameFormat.stripHeightMM
        )
        selectedHardwareScanArea = capabilities.clampedPhysicalScanArea(area)
    }

    func prepareFlatbedPreview(_ frame: ScanFrame, scanArea: ScanArea?) {
        guard usesFlatbedRegionWorkflow,
              frame.isPreviewScan,
              let scanArea,
              scanArea.originXMM.isFinite,
              scanArea.originYMM.isFinite,
              scanArea.widthMM.isFinite,
              scanArea.heightMM.isFinite,
              scanArea.widthMM > 0,
              scanArea.heightMM > 0 else { return }
        flatbedPreviewFrameID = frame.id
        flatbedPreviewScanArea = scanArea
        flatbedScanRegions = []
        selectedFlatbedScanRegionID = nil
    }

    func detectFlatbedScanRegions(
        for frame: ScanFrame,
        sessionID: UUID
    ) async {
        await detectFlatbedScanRegions(
            for: frame,
            requiredSessionID: sessionID
        )
    }

    private func detectFlatbedScanRegions(
        for frame: ScanFrame,
        requiredSessionID: UUID?
    ) async {
        let frameID = frame.id
        guard usesFlatbedRegionWorkflow,
              requiredSessionID == nil || activeScanSessionID == requiredSessionID,
              flatbedPreviewFrameID == frameID,
              flatbedPreviewFrame?.id == frameID,
              flatbedScanRegions.isEmpty else { return }
        let regionRevision = flatbedScanRegionRevision
        let sourceURL = frame.rawScanURL
        let requestedFrameFormat = scanFrameFormat
        let detections = await Task.detached(priority: .userInitiated) {
            (try? FlatbedFrameDetector.detect(
                url: sourceURL,
                frameFormat: requestedFrameFormat
            )) ?? []
        }.value

        guard requiredSessionID == nil || activeScanSessionID == requiredSessionID,
              scanFrameFormat == requestedFrameFormat,
              flatbedPreviewFrameID == frameID,
              flatbedPreviewFrame?.id == frameID,
              flatbedScanRegions.isEmpty,
              flatbedScanRegionRevision == regionRevision,
              !detections.isEmpty,
              detections.allSatisfy(Self.isValidFlatbedFrameDetection),
              Set(detections.map { "\($0.row):\($0.column)" }).count == detections.count
        else { return }

        let regions = detections
            .sorted {
                ($0.row, $0.column) < ($1.row, $1.column)
            }
            .map {
                FlatbedScanRegion(
                    unitRect: $0.normalizedRect,
                    straightenAngle: $0.straightenAngle,
                    source: .automatic
                )
            }
        flatbedScanRegions = regions
        selectedFlatbedScanRegionID = regions.first?.id
    }

    func addFlatbedScanRegion(unitRect: CGRect? = nil) {
        guard usesFlatbedRegionWorkflow, flatbedPreviewFrame != nil else { return }
        // 프레임 좌표는 프리뷰로 실제로 훑은 영역을 기준으로 한다(FlatbedScanRegionGeometry).
        // 최대 영역으로 계산하면 하드웨어 스캔 영역을 좁혀둔 프리뷰에서 규격 치수가 어긋난다.
        let previewArea = flatbedPreviewScanArea ?? hardwareScanAreaBounds?.maximum
        let proposed = unitRect
            ?? previewArea.flatMap {
                FlatbedScanRegionLayout.proposedRect(
                    existing: flatbedScanRegions.map(\.unitRect),
                    frameFormat: scanFrameFormat,
                    previewArea: $0
                )
            }
            ?? CGRect(x: 0.25, y: 0.3, width: 0.5, height: 0.4)
        let region = FlatbedScanRegion(unitRect: proposed)
        flatbedScanRegions.append(region)
        selectedFlatbedScanRegionID = region.id
    }

    func selectFlatbedScanRegion(_ id: UUID) {
        guard flatbedScanRegions.contains(where: { $0.id == id }) else { return }
        selectedFlatbedScanRegionID = id
    }

    func updateFlatbedScanRegion(_ id: UUID, unitRect: CGRect) {
        guard let index = flatbedScanRegions.firstIndex(where: { $0.id == id }) else { return }
        flatbedScanRegions[index].unitRect = clampedUnitRect(unitRect)
        flatbedScanRegions[index].straightenAngle = 0
        flatbedScanRegions[index].source = .manual
        selectedFlatbedScanRegionID = id
    }

    func deleteSelectedFlatbedScanRegion() {
        guard let selectedFlatbedScanRegionID,
              let index = flatbedScanRegions.firstIndex(where: {
                  $0.id == selectedFlatbedScanRegionID
              }) else { return }
        flatbedScanRegions.remove(at: index)
        self.selectedFlatbedScanRegionID = flatbedScanRegions.indices.contains(index)
            ? flatbedScanRegions[index].id
            : flatbedScanRegions.last?.id
    }

    private nonisolated static func isValidFlatbedFrameDetection(
        _ detection: FlatbedFrameDetection
    ) -> Bool {
        let rect = detection.normalizedRect
        return rect.minX.isFinite
            && rect.minY.isFinite
            && rect.width.isFinite
            && rect.height.isFinite
            && rect.minX >= 0
            && rect.minY >= 0
            && rect.maxX <= 1
            && rect.maxY <= 1
            && rect.width > 0
            && rect.height > 0
            && detection.straightenAngle.isFinite
            && abs(detection.straightenAngle) <= 45
            && detection.confidence.isFinite
            && (0...1).contains(detection.confidence)
            && detection.row >= 0
            && detection.column >= 0
    }
}
