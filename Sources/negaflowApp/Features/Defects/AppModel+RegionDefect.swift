import SwiftUI
import Chromabase
import CoreImage
import AppKit

// 가이드 영역 결함 제거: ROI 사각형 지정 → 그 안 결함을 풀해상도로 검출(빨강 표시) → 결함 아닌 것
// 클릭 제외 → "제거"로 cleaned raw 에 복원. 브러시 결함 제거(defectStrokes)와 별개 경로지만 cleaned raw
// 저장소는 공유한다(현상 입력은 하나) — 브러시 결과 위에 누적된다. 검출/복원 코어는 SoftwareDefectRemoval
// (detectComponents/repair) 그대로 — 브러시와 동일 품질.

// 화면 표시용 컴포넌트(base 정규좌표 점). transform 이 바뀌어도 baseUnitToDisplay 로 정합한다.
// Equatable: 오버레이 캔버스가 무관한 상태 변화에 재드로잉되지 않도록 값 비교에 쓴다.
struct DefectPreviewComponent: Identifiable, Equatable {
    let id: Int32
    let kind: DefectComponent.Kind
    let classification: DefectClass   // v2: 물리 분류(색/라벨 표시)
    let confidence: Double               // v2: 검출 확신(0~1)
    let points: [CGPoint]   // base 정규(0..1, y-down)
}

extension AppModel {
    private var regionDefectParameters: SoftwareDefectParameters {
        SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6, scratchSensitivity: 0.7, protectDetail: 0.6)
    }

    // MARK: 검출

    /// 표시 정규좌표 ROI(0..1, y-down) 안의 결함을 풀해상도 raw 에서 검출해 빨강 미리보기를 만든다.
    func runRegionDetect(_ frame: ScanFrame, displayROI: CGRect) {
        let trace = AppDiagnostics.start(.regionDefect, category: .defects)
        frame.defectDetectRevision += 1
        let revision = frame.defectDetectRevision
        frame.defectDetectTask?.cancel()
        frame.defectIsDetecting = true
        frame.defectActive = true
        statusMessage = text(AppLocalizedPhrase.detectingDefectsStatus)

        let transform = frame.imageTransform
        var params = regionDefectParameters
        // 슬라이더 전체 범위(0.7~6.0)를 detector가 정의한 0~1 민감도에 선형 매핑한다.
        // 3.0에서 이미 최대를 넘기던 이전 매핑은 6.0을 1.5로 전달해 형태 게이트와
        // 먼지 면적 상한을 의도보다 과도하게 풀었다. 자동 기본값은 검증된 보수 하한 0.7이다.
        let s = max(0, min(1, (frame.defectSensitivity - 0.7) / (6.0 - 0.7)))
        params.dustSensitivity = s
        params.scratchSensitivity = min(1, s + 0.1)
        params.detectMicroSpecks = frame.defectMicroSpecks
        // 자동 모드: 0..1 ROI 가 변환/반올림으로 extent 와 1px 어긋나도 전역 자동 계약(보수 검출 +
        // 구조선 격자 배제)을 강제한다 — 이게 없으면 부분 ROI로 오판돼 오검출이 폭증한다.
        let wholeFrameAuto = frame.defectAutoMode
        let preCG = frame.cleanedRawImage
        // 프레임 선택만으로 full-size cleaned raw를 RAM에 중복 적재하지 않는다. 영역 결함 제거를 실제로
        // 시작한 시점에만 검증된 디스크 백킹을 CIImage로 열어 필요한 ROI를 읽는다.
        let preURL = frame.identityMatchedCleanedRawDiskURL
        let rawURL = frame.rawScanURL
        let sourceKind = frame.sourceKind
        // 디스크 소스는 검출 렌더마다 풀 TIFF를 다시 디코드하므로, 세션 첫 검출에서 한 번만
        // 풀해상도로 굳혀 두고 같은 세션의 재드래그/민감도 재검출에 재사용한다.
        let cleanRevision = frame.cleanRawRevision
        let cachedSessionRaw = frame.defectSessionRawRevision == cleanRevision
            ? frame.defectSessionRaw
            : nil

        let task = Task.detached(priority: .userInitiated) {
            var needsSessionSolidify = false
            let computed: RegionDetectResult? = autoreleasepool { () -> RegionDetectResult? in
                let raw: CIImage
                if let preCG {
                    raw = CIImage(cgImage: preCG, options: [.colorSpace: linearColorSpace])
                } else if let cachedSessionRaw {
                    raw = CIImage(cgImage: cachedSessionRaw, options: [.colorSpace: linearColorSpace])
                } else if let lazy = Self.loadRegionSource(
                    preURL: preURL, rawURL: rawURL, sourceKind: sourceKind
                ) {
                    // 세션 첫 검출: ROI 영역만 굳혀 바로 검출한다 — 예전처럼 풀프레임 RGBA16
                    // 디코드/렌더가 끝나길 기다리지 않는다(작은 ROI 의 첫 검출이 이미지 크기와
                    // 무관해진다). 전체 굳히기(재검출·커밋 재사용용 세션 캐시)는 결과 반영 후
                    // 백그라운드로 예약한다. ROI 밖은 검출이 읽지 않으므로 검정 상수로 채워
                    // extent(물리 먼지 스케일 기준)만 원본 크기를 유지한다.
                    let fullExtent = lazy.extent
                    let lazyBase = CGSize(width: fullExtent.width, height: fullExtent.height)
                    guard lazyBase.width > 2, lazyBase.height > 2 else { return nil }
                    let lazyROI = Self.baseROICIyup(
                        displayROI: displayROI, transform: transform, baseSize: lazyBase
                    ).intersection(fullExtent).integral
                    guard lazyROI.width >= 2, lazyROI.height >= 2 else { return nil }
                    guard let roiCG = cleanedRawContext.createCGImage(
                        lazy, from: lazyROI, format: .RGBA16, colorSpace: linearColorSpace
                    ) else { return nil }
                    raw = CIImage(cgImage: roiCG, options: [.colorSpace: linearColorSpace])
                        .transformed(by: CGAffineTransform(translationX: lazyROI.minX, y: lazyROI.minY))
                        .composited(over: CIImage(color: CIColor(red: 0, green: 0, blue: 0))
                            .cropped(to: fullExtent))
                    needsSessionSolidify = true
                } else { return nil }
                let baseSize = CGSize(width: raw.extent.width, height: raw.extent.height)
                guard baseSize.width > 2, baseSize.height > 2 else { return nil }
                let roiYup = Self.baseROICIyup(displayROI: displayROI, transform: transform, baseSize: baseSize)
                guard roiYup.width >= 2, roiYup.height >= 2 else { return nil }
                if Task.isCancelled { return nil }
                let field = SoftwareDefectRemoval.detectComponents(
                    in: raw,
                    roi: roiYup,
                    parameters: params,
                    wholeFrameAuto: wholeFrameAuto,
                    shouldCancel: { Task.isCancelled }
                )
                if Task.isCancelled { return nil }
                let roiX0 = Int(roiYup.minX.rounded())
                let roiTopYDown = Int((baseSize.height - roiYup.maxY).rounded())
                let preview = Self.previewComponents(field: field, baseSize: baseSize,
                                                     roiX0: roiX0, roiTopYDown: roiTopYDown)
                return RegionDetectResult(field: field, baseSize: baseSize, roiX0: roiX0,
                                          roiTopYDown: roiTopYDown, roiYup: roiYup, preview: preview)
            }
            if computed != nil || Task.isCancelled {
                trace.finish()
            } else {
                trace.fail(code: "region_detection_failed")
            }
            let solidifyNeeded = needsSessionSolidify
            await MainActor.run {
                if solidifyNeeded, !Task.isCancelled {
                    self.scheduleRegionSessionSolidify(
                        frame, preURL: preURL, rawURL: rawURL,
                        sourceKind: sourceKind, cleanRevision: cleanRevision
                    )
                }
                guard self.ownsFrame(frame), frame.defectDetectRevision == revision else { return }
                frame.defectIsDetecting = false
                frame.defectDetectTask = nil
                // 검출 중 cleaned raw가 다시 빌드되면 결과의 입력 revision이 이미 낡았다. 다른
                // 프레임/세션의 라벨을 현재 이미지에 적용하지 않고 다음 드래그에서 새로 검출한다.
                guard frame.cleanRawRevision == cleanRevision else {
                    self.clearRegionDefectSession(frame)
                    return
                }
                guard let computed else {
                    if !Task.isCancelled { self.statusMessage = self.text(AppLocalizedPhrase.detectingDefectsFailedStatus) }
                    return
                }
                frame.defectLabelField = computed.field
                frame.defectBaseSize = computed.baseSize
                frame.defectROIPixelX0 = computed.roiX0
                frame.defectROIPixelY0 = computed.roiTopYDown
                frame.defectROICIyup = computed.roiYup
                frame.defectExcludedIDs = []
                frame.defectPreview = computed.preview
                if computed.field.automaticSafetySuppressed {
                    self.statusMessage = self.text(AppLocalizedPhrase.automaticDefectSafetyStoppedStatus)
                } else {
                    self.statusMessage = computed.field.isEmpty
                        ? self.text(AppLocalizedPhrase.noDefectsStatus)
                        : self.text(AppLocalizedPhrase.defectsCountFormat, computed.field.components.count)
                }
            }
        }
        frame.defectDetectTask = task
    }

    private struct RegionDetectResult {
        let field: DefectLabelField
        let baseSize: CGSize
        let roiX0: Int
        let roiTopYDown: Int
        let roiYup: CGRect
        let preview: [DefectPreviewComponent]
    }

    // MARK: 종류별 일괄 제외/신뢰도 요약 (HUD 칩)

    /// 검출된 결함 종류별 요약(개수·평균 신뢰도·전체 제외 여부). 화면 칩 렌더용.
    struct DefectClassSummary: Identifiable {
        let classification: DefectClass
        var id: DefectClass { classification }
        let count: Int
        let meanConfidence: Double
        let allExcluded: Bool
    }

    /// 현재 미리보기의 종류별 요약을 DefectClass 정의 순서로 낸다(자동/가이드 공통).
    func defectClassSummaries(_ frame: ScanFrame) -> [DefectClassSummary] {
        let preview = frame.defectPreview
        guard !preview.isEmpty else { return [] }
        var byClass: [DefectClass: [DefectPreviewComponent]] = [:]
        for c in preview { byClass[c.classification, default: []].append(c) }
        return DefectClass.allCases.compactMap { cls in
            guard let comps = byClass[cls], !comps.isEmpty else { return nil }
            let meanConf = comps.reduce(0.0) { $0 + $1.confidence } / Double(comps.count)
            let allExcluded = comps.allSatisfy { frame.defectExcludedIDs.contains($0.id) }
            return DefectClassSummary(classification: cls, count: comps.count,
                                      meanConfidence: meanConf, allExcluded: allExcluded)
        }
    }

    /// 한 종류 전체를 제외↔포함 토글한다(개별 클릭 제외와 같은 defectExcludedIDs 를 공유). 재검출 없음.
    func toggleRegionClass(_ frame: ScanFrame, classification: DefectClass) {
        let ids = frame.defectPreview.filter { $0.classification == classification }.map(\.id)
        guard !ids.isEmpty else { return }
        if ids.allSatisfy({ frame.defectExcludedIDs.contains($0) }) {
            for id in ids { frame.defectExcludedIDs.remove(id) }   // 전체 다시 포함
        } else {
            for id in ids { frame.defectExcludedIDs.insert(id) }   // 전체 제외
        }
    }

    // MARK: 클릭 제외/포함

    /// 화면 정규좌표 클릭 위치의 컴포넌트를 제외↔포함 토글한다(재검출 없음). 미리보기만 갱신.
    func toggleRegionComponent(_ frame: ScanFrame, atDisplay p: CGPoint) {
        guard let field = frame.defectLabelField, let baseSize = frame.defectBaseSize else { return }
        let basePt = frame.imageTransform.displayUnitToBase(p, baseSize: baseSize)
        let lx = Int((basePt.x * baseSize.width).rounded()) - frame.defectROIPixelX0
        let ly = Int((basePt.y * baseSize.height).rounded()) - frame.defectROIPixelY0
        let radius = max(3, field.width / 100)
        guard let id = field.nearestComponentID(atX: lx, y: ly, radius: radius) else { return }
        if frame.defectExcludedIDs.contains(id) { frame.defectExcludedIDs.remove(id) }
        else { frame.defectExcludedIDs.insert(id) }
    }

    /// 민감도 슬라이더 변경 → 같은 ROI 재검출(제외는 초기화; 위치 보존은 후속 과제).
    func redetectRegion(_ frame: ScanFrame) {
        guard let roiYup = frame.defectROICIyup, let baseSize = frame.defectBaseSize else { return }
        // base ROI(y-up) → 표시 정규 ROI 로 역산해 runRegionDetect 재사용.
        let roiTopYDown = Double(frame.defectROIPixelY0)
        let by0 = roiTopYDown / baseSize.height
        let by1 = by0 + Double(roiYup.height) / baseSize.height
        let bx0 = Double(frame.defectROIPixelX0) / baseSize.width
        let bx1 = bx0 + Double(roiYup.width) / baseSize.width
        let t = frame.imageTransform
        let corners = [CGPoint(x: bx0, y: by0), CGPoint(x: bx1, y: by0),
                       CGPoint(x: bx0, y: by1), CGPoint(x: bx1, y: by1)]
            .map { t.baseUnitToDisplay($0, baseSize: baseSize) }
        let xs = corners.map { $0.x }, ys = corners.map { $0.y }
        let roi = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        runRegionDetect(frame, displayROI: roi)
    }

    // MARK: 제거(commit)

    /// 살아남은 컴포넌트를 마스크로 렌더해 region 편집으로 만들고, 브러시와 같은 통합 빌드 경로
    /// (appendDefectEdit)로 cleaned raw 에 누적한다 — 브러시·가이드가 서로 되살아나지 않는다. 무거운
    /// DefectLabelField 대신 렌더된 마스크(Data)만 보관해 메모리에 가볍다. 세션을 닫는다.
    /// 마스크 렌더와 zlib 압축은 ROI 크기에 비례하므로 백그라운드에서 수행한다(메인 스레드 무정지).
    func commitRegionDefect(_ frame: ScanFrame) {
        guard let field = frame.defectLabelField, let roiYup = frame.defectROICIyup, !field.isEmpty else {
            cancelRegionDefect(frame); return
        }
        let excluded = frame.defectExcludedIDs
        guard field.components.contains(where: { !excluded.contains($0.id) }) else { cancelRegionDefect(frame); return }
        // 세션은 바로 닫지 않는다 — 빌드 동안 "제거" 버튼에 작은 프로그래스바를 보이고,
        // cleaned raw 재현상까지 끝난 뒤 빌드 경로가 세션을 닫는다.
        frame.defectIsRemoving = true
        frame.isRemovingDefects = true
        let detectRevision = frame.defectDetectRevision
        let baseSize = frame.defectBaseSize
        let defectPreview = frame.defectPreview
        let language = appLanguage
        Task.detached(priority: .userInitiated) { [weak self, weak frame] in
            let survivors = field.components.filter { !excluded.contains($0.id) }
            // 마스크를 "생존 결함 bbox + 팽창 + 복원 문맥 여백" 창에만 직접 렌더해 저장한다.
            // 여백(repairContextRadius)이 복원 샘플링 도달 거리보다 넓으므로 창 ROI 복원 결과는
            // 전체 ROI 와 픽셀 동일하고, 전체 필드 크기 RGBA8 버퍼(큰 ROI 에서 수십~수백 MB)를
            // 아예 만들지 않는다 — 커밋 비용이 검출 ROI 면적이 아니라 결함 크기에 비례한다.
            let edit: DefectEdit = autoreleasepool {
                let dilate = max(2, 3)   // renderMask 의 dustDilate 기본 2, scratchDilate 요청값 3
                let pad = SoftwareDefectRemoval.repairContextRadius + dilate
                var minX = field.width, minY = field.height, maxX = -1, maxY = -1
                for component in survivors {
                    minX = min(minX, component.minX); maxX = max(maxX, component.maxX)
                    minY = min(minY, component.minY); maxY = max(maxY, component.maxY)
                }
                guard maxX >= minX, maxY >= minY else {
                    // 방어: 생존 컴포넌트가 비면(호출측 가드가 이미 배제) 전체 창으로 렌더.
                    let rendered = SoftwareDefectRemoval.componentMaskBytes(
                        field: field, excluded: excluded, scratchDilate: 3
                    )
                    return DefectEdit.region(
                        mask: DefectCompressedData.raw(Data(rendered)).compressed(),
                        roi: roiYup, width: field.width, height: field.height
                    )
                }
                let x0 = max(0, minX - pad), x1 = min(field.width, maxX + 1 + pad)
                let y0 = max(0, minY - pad), y1 = min(field.height, maxY + 1 + pad)
                let bytes = SoftwareDefectRemoval.componentMaskBytes(
                    field: field, excluded: excluded, scratchDilate: 3,
                    windowX: x0, windowY: y0, windowWidth: x1 - x0, windowHeight: y1 - y0
                )
                // y-down 창 [y0, y1) → y-up ROI: 창 아래쪽 여백(field.height - y1)만큼 위로.
                let roi = CGRect(x: roiYup.minX + CGFloat(x0),
                                 y: roiYup.minY + CGFloat(field.height - y1),
                                 width: CGFloat(x1 - x0), height: CGFloat(y1 - y0))
                return DefectEdit.region(
                    mask: DefectCompressedData.raw(Data(bytes)).compressed(),
                    roi: roi, width: x1 - x0, height: y1 - y0
                )
            }
            // Defect Layer 메타데이터: 분류별 개수 + 평균 confidence 요약, 마스크 오버레이용 미리보기 점.
            var counts: [DefectClass: Int] = [:]
            var confidenceSum = 0.0
            for c in survivors {
                counts[c.classification, default: 0] += 1
                confidenceSum += c.confidence
            }
            let classSummary = DefectClass.allCases
                .compactMap { cls in counts[cls].map { "\(cls.displayName(language: language)) \($0)" } }
                .joined(separator: " · ")
            let meanConfidence = survivors.isEmpty ? 0 : confidenceSum / Double(survivors.count)
            let preview = defectPreview
                .filter { !excluded.contains($0.id) }
                .map { DefectMaskPreviewComponent(classification: $0.classification,
                                                  confidence: $0.confidence, points: $0.points) }
            await MainActor.run { [weak self, weak frame] in
                guard let frame else { return }
                guard let self, self.ownsFrame(frame) else {
                    frame.defectIsRemoving = false
                    frame.isRemovingDefects = false
                    return
                }
                guard frame.defectDetectRevision == detectRevision, frame.defectIsRemoving else {
                    frame.defectIsRemoving = false
                    frame.isRemovingDefects = false
                    return
                }
                let summary = self.text(
                    AppLocalizedPhrase.confidenceSummaryFormat, classSummary, meanConfidence * 100
                )
                let titlePhrase: AppLocalizedPhrase = frame.defectAutoMode
                    ? .grainMendAutoEditTitleFormat
                    : .grainMendGuidedEditTitleFormat
                let item = DefectEditItem(
                    edit: edit,
                    title: self.text(titlePhrase, survivors.count),
                    summary: summary, preview: preview, baseSize: baseSize
                )
                if !self.appendDefectEdit(item, to: frame) {
                    // recipe 검증 실패 시 검출 결과는 유지하고 버튼만 다시 활성화한다.
                    frame.defectIsRemoving = false
                    frame.isRemovingDefects = false
                }
            }
        }
    }

    func cancelRegionDefect(_ frame: ScanFrame) {
        // Task 취소는 협력적이므로 이미 MainActor 반환 직전인 이전 작업을 revision으로도 무효화한다.
        frame.defectDetectRevision += 1
        frame.defectDetectTask?.cancel()
        frame.defectDetectTask = nil
        frame.defectIsDetecting = false
        clearRegionDefectSession(frame)
    }

    func clearRegionDefectSession(_ frame: ScanFrame) {
        frame.defectActive = false
        frame.defectIsRemoving = false
        frame.defectLabelField = nil
        frame.defectBaseSize = nil
        frame.defectROICIyup = nil
        frame.defectExcludedIDs = []
        frame.defectPreview = []
        frame.defectSessionRaw = nil
        frame.defectSessionRawRevision = -1
        frame.defectSessionSolidifyTask?.cancel()
        frame.defectSessionSolidifyTask = nil
    }

    /// 세션 raw 전체 굳히기를 백그라운드로 예약한다(첫 검출은 ROI 만 굳혀 먼저 반환).
    /// 완료 후에도 세션·revision 이 그대로일 때만 세션 캐시에 넣는다 — 재검출과 첫 "제거"가
    /// 원본 재디코드 없이 이 캐시를 쓴다.
    func scheduleRegionSessionSolidify(
        _ frame: ScanFrame, preURL: URL?, rawURL: URL,
        sourceKind: FrameSource, cleanRevision: Int
    ) {
        guard frame.defectSessionSolidifyTask == nil,
              frame.defectSessionRaw == nil,
              frame.cleanRawRevision == cleanRevision,
              frame.defectActive || frame.defectIsDetecting else { return }
        frame.defectSessionSolidifyTask = Task.detached(priority: .utility) { [weak self, weak frame] in
            let decoded = Self.decodeRegionSessionRaw(
                preURL: preURL, rawURL: rawURL, sourceKind: sourceKind
            )
            await MainActor.run { [weak self, weak frame] in
                guard let frame else { return }
                frame.defectSessionSolidifyTask = nil
                guard let self, self.ownsFrame(frame),
                      let decoded,
                      !Task.isCancelled,
                      frame.cleanRawRevision == cleanRevision,
                      frame.defectSessionRaw == nil,
                      frame.defectActive || frame.defectIsDetecting else { return }
                frame.defectSessionRaw = decoded
                frame.defectSessionRawRevision = cleanRevision
            }
        }
    }

    // MARK: helpers (백그라운드 — frame 비접근)

    /// 디스크 소스(검증된 cleaned raw 백킹 → 원본 raw)의 CIImage 로더. 가져온 파일은 develop 과
    /// 동일 로더로 읽어 방향(EXIF)·색 해석을 일치시킨다. 렌더(굳히기)는 호출측이 결정한다.
    private nonisolated static func loadRegionSource(
        preURL: URL?, rawURL: URL, sourceKind: FrameSource
    ) -> CIImage? {
        if let url = preURL, let loaded = ImageLoader.loadScannerTIFF(url) {
            return loaded
        }
        switch sourceKind {
        case .scannerTIFF:  return ChromabaseEngine().loadScannerImage(rawURL)
        case .importedFile: return ChromabaseEngine().loadImportedImage(rawURL)
        }
    }

    /// 디스크 소스를 한 번에 풀해상도 CGImage 로 굳힌다(세션 캐시/커밋 베이스용).
    private nonisolated static func decodeRegionSessionRaw(
        preURL: URL?, rawURL: URL, sourceKind: FrameSource
    ) -> CGImage? {
        autoreleasepool {
            guard let ci = loadRegionSource(preURL: preURL, rawURL: rawURL, sourceKind: sourceKind) else {
                return nil
            }
            return cleanedRawContext.createCGImage(
                ci, from: ci.extent, format: .RGBA16, colorSpace: linearColorSpace
            )
        }
    }

    /// 표시 정규 ROI → base raw 의 CIImage(y-up) 픽셀 ROI. 회전/플립/회전보정/크롭을 displayUnitToBase
    /// 로 역매핑한 네 꼭짓점의 bbox 를 base 픽셀로 환산한다.
    private nonisolated static func baseROICIyup(displayROI: CGRect, transform: ImageTransform, baseSize: CGSize) -> CGRect {
        let corners = [
            CGPoint(x: displayROI.minX, y: displayROI.minY),
            CGPoint(x: displayROI.maxX, y: displayROI.minY),
            CGPoint(x: displayROI.minX, y: displayROI.maxY),
            CGPoint(x: displayROI.maxX, y: displayROI.maxY),
        ].map { transform.displayUnitToBase($0, baseSize: baseSize) }
        let xs = corners.map { Double($0.x) }, ys = corners.map { Double($0.y) }
        let bx0 = max(0, xs.min()!), bx1 = min(1, xs.max()!)
        let by0 = max(0, ys.min()!), by1 = min(1, ys.max()!)   // y-down 정규
        let pxX0 = bx0 * baseSize.width, pxX1 = bx1 * baseSize.width
        let pyTop = by0 * baseSize.height, pyBot = by1 * baseSize.height   // y-down px
        let yup = baseSize.height - pyBot
        return CGRect(x: pxX0, y: yup, width: pxX1 - pxX0, height: pyBot - pyTop).integral
    }

    /// 컴포넌트 픽셀(ROI 로컬, y-down) → base 정규 점. 화면 과밀/비용을 막으려 컴포넌트당 상한으로 다운샘플.
    private nonisolated static func previewComponents(field: DefectLabelField, baseSize: CGSize,
                                          roiX0: Int, roiTopYDown: Int) -> [DefectPreviewComponent] {
        let totalPointBudget = 24_000
        let maxPoints = max(1, min(800, totalPointBudget / max(1, field.components.count)))
        let w = field.width, bw = baseSize.width, bh = baseSize.height
        return field.components.map { comp in
            let samplingStride = max(1, (comp.pixels.count + maxPoints - 1) / maxPoints)
            var pts: [CGPoint] = []
            pts.reserveCapacity(min(comp.pixels.count, maxPoints))
            var i = 0
            while i < comp.pixels.count {
                let p = comp.pixels[i]
                let lx = p % w, ly = p / w
                pts.append(CGPoint(x: Double(roiX0 + lx) / bw, y: Double(roiTopYDown + ly) / bh))
                i += samplingStride
            }
            return DefectPreviewComponent(id: comp.id, kind: comp.kind,
                                       classification: comp.classification,
                                       confidence: comp.confidence, points: pts)
        }
    }
}
