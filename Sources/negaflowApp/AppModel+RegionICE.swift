import SwiftUI
import Chromabase
import CoreImage
import AppKit

// 반자동 Region ICE: ROI 사각형 지정 → 그 안 결함을 풀해상도로 검출(빨강 표시) → 결함 아닌 것
// 클릭 제외 → "제거"로 cleaned raw 에 복원. 브러시 ICE(defectStrokes)와 별개 경로지만 cleaned raw
// 저장소는 공유한다(현상 입력은 하나) — 브러시 결과 위에 누적된다. 검출/복원 코어는 SoftwareICE
// (detectComponents/repair) 그대로 — 브러시와 동일 품질.

// 화면 표시용 컴포넌트(base 정규좌표 점). transform 이 바뀌어도 baseUnitToDisplay 로 정합한다.
struct ICEPreviewComponent: Identifiable {
    let id: Int32
    let kind: ICEComponent.Kind
    let points: [CGPoint]   // base 정규(0..1, y-down)
}

extension AppModel {
    private var regionICEParameters: SoftwareICEParameters {
        SoftwareICEParameters(strength: 1, dustSensitivity: 0.6, scratchSensitivity: 0.7, protectDetail: 0.6)
    }

    // MARK: 검출

    /// 표시 정규좌표 ROI(0..1, y-down) 안의 결함을 풀해상도 raw 에서 검출해 빨강 미리보기를 만든다.
    func runRegionDetect(_ frame: ScanFrame, displayROI: CGRect) {
        frame.iceDetectRevision += 1
        let revision = frame.iceDetectRevision
        frame.iceDetectTask?.cancel()
        frame.iceIsDetecting = true
        frame.iceActive = true
        statusMessage = "결함 검출 중"

        let transform = frame.imageTransform
        var params = regionICEParameters
        // 슬라이더(0.7~6.0)를 검출 강도로 매핑. detector 임계는 내부에서 s≤1 로 clamp(그레인 안전 —
        // 실제 필름 그레인 폭발 방지)되고, 여기선 형태 게이트 강도까지 포함해 1.5 까지 전달한다.
        // 슬라이더 우측 절반(3.0~6.0)에서 임계는 그대로 두고 형태 게이트만 더 풀어(aspect↑/최소길이↓/
        // 두께↑/면적↑) 얇고 불규칙한 결함을 grain-safe 하게 추가로 잡는다.
        let s = max(0, min(1.5, (frame.iceSensitivity - 0.7) / (3.0 - 0.7)))
        params.dustSensitivity = s
        params.scratchSensitivity = min(1.5, s + 0.1)
        let preCG = frame.cleanedRawImage
        let preURL = frame.cleanedRawDiskURL
        let rawURL = frame.rawScanURL

        let task = Task.detached(priority: .userInitiated) {
            let computed: RegionDetectResult? = autoreleasepool { () -> RegionDetectResult? in
                guard let raw = Self.loadRegionRaw(preCG: preCG, preURL: preURL, rawURL: rawURL) else { return nil }
                let baseSize = CGSize(width: raw.extent.width, height: raw.extent.height)
                guard baseSize.width > 2, baseSize.height > 2 else { return nil }
                let roiYup = Self.baseROICIyup(displayROI: displayROI, transform: transform, baseSize: baseSize)
                guard roiYup.width >= 2, roiYup.height >= 2 else { return nil }
                if Task.isCancelled { return nil }
                let field = SoftwareICE.detectComponents(in: raw, roi: roiYup, parameters: params)
                let roiX0 = Int(roiYup.minX.rounded())
                let roiTopYDown = Int((baseSize.height - roiYup.maxY).rounded())
                let preview = Self.previewComponents(field: field, baseSize: baseSize,
                                                     roiX0: roiX0, roiTopYDown: roiTopYDown)
                return RegionDetectResult(field: field, baseSize: baseSize, roiX0: roiX0,
                                          roiTopYDown: roiTopYDown, roiYup: roiYup, preview: preview)
            }
            await MainActor.run {
                guard frame.iceDetectRevision == revision else { return }
                frame.iceIsDetecting = false
                frame.iceDetectTask = nil
                guard let computed else {
                    if !Task.isCancelled { self.statusMessage = "결함 검출 실패" }
                    return
                }
                frame.iceLabelField = computed.field
                frame.iceBaseSize = computed.baseSize
                frame.iceROIPixelX0 = computed.roiX0
                frame.iceROIPixelY0 = computed.roiTopYDown
                frame.iceROICIyup = computed.roiYup
                frame.iceExcludedIDs = []
                frame.icePreview = computed.preview
                self.statusMessage = computed.field.isEmpty ? "결함 없음" : "결함 \(computed.field.components.count)개"
            }
        }
        frame.iceDetectTask = task
    }

    private struct RegionDetectResult {
        let field: ICELabelField
        let baseSize: CGSize
        let roiX0: Int
        let roiTopYDown: Int
        let roiYup: CGRect
        let preview: [ICEPreviewComponent]
    }

    // MARK: 클릭 제외/포함

    /// 화면 정규좌표 클릭 위치의 컴포넌트를 제외↔포함 토글한다(재검출 없음). 미리보기만 갱신.
    func toggleRegionComponent(_ frame: ScanFrame, atDisplay p: CGPoint) {
        guard let field = frame.iceLabelField, let baseSize = frame.iceBaseSize else { return }
        let basePt = frame.imageTransform.displayUnitToBase(p, baseSize: baseSize)
        let lx = Int((basePt.x * baseSize.width).rounded()) - frame.iceROIPixelX0
        let ly = Int((basePt.y * baseSize.height).rounded()) - frame.iceROIPixelY0
        let radius = max(3, field.width / 100)
        guard let id = field.nearestComponentID(atX: lx, y: ly, radius: radius) else { return }
        if frame.iceExcludedIDs.contains(id) { frame.iceExcludedIDs.remove(id) }
        else { frame.iceExcludedIDs.insert(id) }
    }

    /// 민감도 슬라이더 변경 → 같은 ROI 재검출(제외는 초기화; 위치 보존은 후속 과제).
    func redetectRegion(_ frame: ScanFrame) {
        guard let roiYup = frame.iceROICIyup, let baseSize = frame.iceBaseSize else { return }
        // base ROI(y-up) → 표시 정규 ROI 로 역산해 runRegionDetect 재사용.
        let roiTopYDown = Double(frame.iceROIPixelY0)
        let by0 = roiTopYDown / baseSize.height
        let by1 = by0 + Double(roiYup.height) / baseSize.height
        let bx0 = Double(frame.iceROIPixelX0) / baseSize.width
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
    /// (appendDefectEdit)로 cleaned raw 에 누적한다 — 브러시·반자동이 서로 되살아나지 않는다. 무거운
    /// ICELabelField 대신 렌더된 마스크(Data)만 보관해 메모리에 가볍다. 세션을 닫는다.
    func commitRegionICE(_ frame: ScanFrame) {
        guard let field = frame.iceLabelField, let roiYup = frame.iceROICIyup, !field.isEmpty else {
            cancelRegionICE(frame); return
        }
        let excluded = frame.iceExcludedIDs
        guard field.components.contains(where: { !excluded.contains($0.id) }) else { cancelRegionICE(frame); return }
        let maskBytes = SoftwareICE.componentMaskBytes(field: field, excluded: excluded)
        let edit = DefectEdit.region(mask: Data(maskBytes), roi: roiYup,
                                     width: field.width, height: field.height)
        // 세션은 바로 닫지 않는다 — 빌드 동안 "제거" 버튼에 작은 프로그래스바를 보이고, 빌드
        // (isRemovingDefects) 종료 시 오버레이 onChange 가 clearRegionICESession 으로 닫는다.
        frame.iceIsRemoving = true
        appendDefectEdit(edit, to: frame)    // 통합 빌드(brush·region 누적)
    }

    func cancelRegionICE(_ frame: ScanFrame) {
        frame.iceDetectTask?.cancel()
        frame.iceDetectTask = nil
        frame.iceIsDetecting = false
        clearRegionICESession(frame)
    }

    func clearRegionICESession(_ frame: ScanFrame) {
        frame.iceActive = false
        frame.iceIsRemoving = false
        frame.iceLabelField = nil
        frame.iceBaseSize = nil
        frame.iceROICIyup = nil
        frame.iceExcludedIDs = []
        frame.icePreview = []
    }

    // MARK: helpers (백그라운드 — frame 비접근)

    private nonisolated static func loadRegionRaw(preCG: CGImage?, preURL: URL?, rawURL: URL) -> CIImage? {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        if let pre = preCG { return CIImage(cgImage: pre, options: [.colorSpace: linear]) }
        if let url = preURL, let ci = ImageLoader.loadScannerTIFF(url) { return ci }
        return ChromabaseEngine().loadScannerImage(rawURL)
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
    private nonisolated static func previewComponents(field: ICELabelField, baseSize: CGSize,
                                          roiX0: Int, roiTopYDown: Int) -> [ICEPreviewComponent] {
        let maxPoints = 800
        let w = field.width, bw = baseSize.width, bh = baseSize.height
        return field.components.map { comp in
            let stride = max(1, comp.pixels.count / maxPoints)
            var pts: [CGPoint] = []
            pts.reserveCapacity(min(comp.pixels.count, maxPoints) + 1)
            var i = 0
            while i < comp.pixels.count {
                let p = comp.pixels[i]
                let lx = p % w, ly = p / w
                pts.append(CGPoint(x: Double(roiX0 + lx) / bw, y: Double(roiTopYDown + ly) / bh))
                i += stride
            }
            return ICEPreviewComponent(id: comp.id, kind: comp.kind, points: pts)
        }
    }
}
