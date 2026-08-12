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
              flatbedFrameDetectionMode == .automatic,
              requiredSessionID == nil || activeScanSessionID == requiredSessionID,
              flatbedPreviewFrameID == frameID,
              flatbedPreviewFrame?.id == frameID,
              flatbedScanRegions.isEmpty else { return }
        let regionRevision = flatbedScanRegionRevision
        let sourceURL = frame.rawScanURL
        let requestedFrameFormat = scanFrameFormat
        // 프리뷰가 담은 실제 영역을 알면 36×24mm 가 몇 px인지 계산할 수 있어, 프레임 규격과
        // 이송 피치를 그대로 단서로 쓸 수 있다. 영역을 모르는 경우에만 예전 에지 기반 검출로
        // 물러난다.
        let previewArea = flatbedPreviewScanArea
        let detections = await Task.detached(priority: .userInitiated) { () -> [FlatbedFrameDetection] in
            // 크기 후보는 프리뷰 파일이 스스로 밝히는 값(픽셀 ÷ 해상도)이 먼저다. 스캐너가
            // 보고한 스캔 영역은 값이 비거나 기준이 달라 mm↔px 환산을 어긋나게 할 수 있고,
            // 그러면 36×24mm 가 몇 px 인지가 틀려 아무것도 못 찾는다(실기: 35mm 3슬롯 프리뷰가
            // 파일 해상도 기준으로는 17컷, 다른 크기로는 0컷).
            var physicalSizes: [CGSize] = []
            if let fileSize = FlatbedFrameGridDetector.physicalSizeMM(url: sourceURL) {
                physicalSizes.append(fileSize)
            }
            if let previewArea, previewArea.widthMM > 0, previewArea.heightMM > 0 {
                physicalSizes.append(
                    CGSize(width: previewArea.widthMM, height: previewArea.heightMM)
                )
            }
            for size in physicalSizes {
                let grid = FlatbedFrameGridDetector.detect(
                    url: sourceURL,
                    physicalSize: size,
                    frameFormat: requestedFrameFormat
                )
                if !grid.isEmpty { return grid }
            }
            return (try? FlatbedFrameDetector.detect(
                url: sourceURL,
                frameFormat: requestedFrameFormat
            )) ?? []
        }.value

        // 경계에 걸친 컷은 프리뷰 안으로 잘라 쓰고, 망가진 것만 걸러낸다.
        let usable = detections.compactMap(Self.usableFlatbedFrameDetection)
        guard requiredSessionID == nil || activeScanSessionID == requiredSessionID,
              scanFrameFormat == requestedFrameFormat,
              flatbedPreviewFrameID == frameID,
              flatbedPreviewFrame?.id == frameID,
              flatbedScanRegions.isEmpty,
              flatbedScanRegionRevision == regionRevision,
              !usable.isEmpty,
              Set(usable.map { "\($0.row):\($0.column)" }).count == usable.count
        else { return }

        let regions = usable
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

    /// 찾는 방식을 바꾼다. 이미 놓인 프레임은 건드리지 않는다 — 지우는 일은 새로고침이 한다.
    /// 자동으로 되돌렸는데 프레임이 하나도 없으면 그 자리에서 찾아 준다.
    func setFlatbedFrameDetectionMode(_ mode: FlatbedFrameDetectionMode) async {
        guard flatbedFrameDetectionMode != mode else { return }
        flatbedFrameDetectionMode = mode
        guard mode == .automatic, let preview = flatbedPreviewFrame else { return }
        await detectFlatbedScanRegions(for: preview, requiredSessionID: nil)
    }

    var canRefreshFlatbedScanRegions: Bool {
        usesFlatbedRegionWorkflow && flatbedPreviewFrame != nil
    }

    /// 자동이면 지우고 처음부터 다시 찾는다. 수동이면 지우고 규격 크기 프레임 하나를 놓아
    /// 다시 시작할 자리를 만든다 — 빈 화면만 남기면 손으로 처음부터 그려야 한다.
    func refreshFlatbedScanRegions() async {
        guard let preview = flatbedPreviewFrame else { return }
        flatbedScanRegions = []
        selectedFlatbedScanRegionID = nil
        switch flatbedFrameDetectionMode {
        case .automatic:
            await detectFlatbedScanRegions(for: preview, requiredSessionID: nil)
        case .manual:
            addFlatbedScanRegion()
        }
    }

    var selectedFlatbedScanRegion: FlatbedScanRegion? {
        guard let selectedFlatbedScanRegionID else { return nil }
        return flatbedScanRegions.first { $0.id == selectedFlatbedScanRegionID }
    }

    var canPasteFlatbedScanRegion: Bool {
        usesFlatbedRegionWorkflow
            && flatbedPreviewFrame != nil
            && copiedFlatbedScanRegionSize != nil
    }

    /// 프레임의 크기만 기억한다. 자리는 붙여넣을 때 정해지므로 위치를 함께 들고 있을 이유가 없다.
    func copySelectedFlatbedScanRegion() {
        guard let region = selectedFlatbedScanRegion else { return }
        copiedFlatbedScanRegionSize = region.unitRect.size
    }

    /// 복사한 크기 그대로 다음 칸에 놓는다. 규격 비율로 다시 맞추지 않는다 — 손으로 맞춰 둔
    /// 크기를 그대로 쓰겠다는 것이 복사·붙여넣기의 목적이다.
    func pasteFlatbedScanRegion() {
        guard usesFlatbedRegionWorkflow,
              flatbedPreviewFrame != nil,
              let size = copiedFlatbedScanRegionSize else { return }
        let previewArea = flatbedPreviewScanArea ?? hardwareScanAreaBounds?.maximum
        let proposed = previewArea.flatMap {
            FlatbedScanRegionLayout.proposedRect(
                existing: flatbedScanRegions.map(\.unitRect),
                frameFormat: scanFrameFormat,
                previewArea: $0,
                size: size
            )
        } ?? CGRect(
            x: (1 - size.width) / 2,
            y: (1 - size.height) / 2,
            width: size.width,
            height: size.height
        )
        let region = FlatbedScanRegion(unitRect: proposed)
        flatbedScanRegions.append(region)
        selectedFlatbedScanRegionID = region.id
    }

    /// 선택한 프레임을 크기를 유지한 채 민다. `dx`/`dy` 는 **화면에서 누른 방향**(-1, 0, 1)이다.
    func nudgeSelectedFlatbedScanRegion(dx: CGFloat, dy: CGFloat, coarse: Bool = false) {
        guard let region = selectedFlatbedScanRegion else { return }
        let step = FlatbedScanRegionLayout.nudgeStep(
            previewArea: flatbedPreviewScanArea ?? hardwareScanAreaBounds?.maximum,
            coarse: coarse
        )
        let delta = baseNudgeDelta(displayDX: dx, displayDY: dy, step: step)
        updateFlatbedScanRegion(
            region.id,
            unitRect: region.unitRect.offsetBy(dx: delta.width, dy: delta.height)
        )
    }

    /// 프레임 좌표는 이미지 변환 이전(base)이다. 프리뷰가 180° 돌아 있으면 base 의 +x 는 화면에서
    /// 왼쪽이고, 90°/270° 면 축이 통째로 바뀐다. 화면에서 한 칸 민 점을 base 로 되돌려 그 차이를
    /// 쓰면 회전·반전이 무엇이든 누른 방향 그대로 움직인다.
    private func baseNudgeDelta(
        displayDX: CGFloat,
        displayDY: CGFloat,
        step: CGSize
    ) -> CGSize {
        let fallback = CGSize(width: displayDX * step.width, height: displayDY * step.height)
        guard let frame = flatbedPreviewFrame else { return fallback }
        let transform = frame.imageTransform
        let baseSize = frame.sourcePixelWidth.flatMap { width in
            frame.sourcePixelHeight.map { CGSize(width: width, height: $0) }
        }
        let center = CGPoint(x: 0.5, y: 0.5)
        let displayCenter = transform.baseUnitToDisplay(center, baseSize: baseSize)
        let displayStepped = transform.baseUnitToDisplay(
            CGPoint(x: center.x + step.width, y: center.y + step.height),
            baseSize: baseSize
        )
        // 회전이 축을 바꾸면 화면 x 의 한 칸은 base y 의 한 칸이다 — 크기는 절댓값으로 읽는다.
        let displayStep = CGSize(
            width: abs(displayStepped.x - displayCenter.x),
            height: abs(displayStepped.y - displayCenter.y)
        )
        let moved = transform.displayUnitToBase(
            CGPoint(
                x: displayCenter.x + displayDX * displayStep.width,
                y: displayCenter.y + displayDY * displayStep.height
            ),
            baseSize: baseSize
        )
        let delta = CGSize(width: moved.x - center.x, height: moved.y - center.y)
        return delta.width.isFinite && delta.height.isFinite ? delta : fallback
    }

    func updateFlatbedScanRegion(_ id: UUID, unitRect: CGRect) {
        guard let index = flatbedScanRegions.firstIndex(where: { $0.id == id }) else { return }
        flatbedScanRegions[index].unitRect = clampedUnitRect(unitRect)
        flatbedScanRegions[index].straightenAngle = 0
        flatbedScanRegions[index].source = .manual
        selectedFlatbedScanRegionID = id
    }

    /// 지금 조작 대상이 "프레임이 그려진 프리뷰 스캔"인가. 삭제 단축키가 사진 대신 프레임을
    /// 지워야 하는 상황을 가른다.
    var hasDrawnFlatbedFramesOnActionablePreview: Bool {
        actionableFrame?.isPreviewScan == true && !flatbedScanRegions.isEmpty
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

    /// 검출 하나가 프리뷰 밖으로 조금 삐져나왔다고 나머지까지 버리면 안 된다.
    ///
    /// 필름을 홀더에 어디까지 밀어 넣었느냐에 따라 슬롯의 마지막 컷이 스캔 영역 경계에
    /// 걸치는 것은 정상이다. 예전에는 이 검사를 `allSatisfy` 로 걸어, 마지막 컷이 0.9mm
    /// 넘친 것 하나 때문에 **제대로 찾은 18컷이 통째로 폐기**됐다(실측: 자동 검출이 아무
    /// 프레임도 못 내놓는 증상의 원인). 걸친 컷은 프리뷰 안으로 잘라 넣고, 값 자체가
    /// 망가졌거나 절반도 안 남는 것만 버린다.
    nonisolated static func usableFlatbedFrameDetection(
        _ detection: FlatbedFrameDetection
    ) -> FlatbedFrameDetection? {
        let rect = detection.normalizedRect
        guard rect.minX.isFinite, rect.minY.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0,
              detection.straightenAngle.isFinite,
              abs(detection.straightenAngle) <= 45,
              detection.confidence.isFinite,
              (0...1).contains(detection.confidence),
              detection.row >= 0,
              detection.column >= 0 else { return nil }
        // 안에 온전히 들어오면 그대로 쓴다 — intersection 은 같은 사각형에도 부동소수 오차를
        // 남기므로(0.161 → 0.16099999999999998) 필요할 때만 자른다.
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        guard !unit.contains(rect) else { return detection }
        let clamped = rect.intersection(unit)
        guard !clamped.isNull, !clamped.isEmpty,
              clamped.width >= rect.width * 0.5,
              clamped.height >= rect.height * 0.5 else { return nil }
        return FlatbedFrameDetection(
            normalizedRect: clamped,
            straightenAngle: detection.straightenAngle,
            confidence: detection.confidence,
            row: detection.row,
            column: detection.column
        )
    }
}
