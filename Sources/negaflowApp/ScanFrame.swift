import Foundation
import AppKit
import Chromabase
import ScannerKit

struct FilmBaseCacheKey: Equatable, Sendable {
    let filmType: FilmType
    let mode: DevelopParameters.BaseMode
    let manualBaseRGB: SIMD3<Double>?
    let filmStockDminID: String?
}

// MARK: - ScanFrame (배치/세션 스캔의 단위)
//
// 한 프레임 = 하나의 raw 스캔 + 그 프레임만의 현상 파라미터/transform/결과.
// AppModel.frames: [ScanFrame] 이 롤을 구성하고, selectedFrameID 가 현재 보는 프레임.
// 색감 엔진은 건드리지 않는다 — 프레임은 데이터 보관만 한다.
@MainActor
final class ScanFrame: ObservableObject, Identifiable {
    let id: UUID = UUID()
    let scanIndex: Int                    // 롤 내 순서 (1-based 표시용)
    let rawScanURL: URL
    let scannedAt: Date
    let sourceFrameID: UUID?
    let sourceFrameDisplayName: String?
    let virtualCopyNumber: Int?

    @Published var filmType: FilmType
    @Published var preset: LookPreset?
    @Published var params: DevelopParameters
    @Published var imageTransform: ImageTransform
    @Published var baseRGB: SIMD3<Double>?
    @Published var rating: Int = 0
    @Published var pickState: FramePickState = .unflagged
    @Published var developHistory: [DevelopHistoryEntry] = []
    @Published var developSnapshots: [DevelopSnapshot] = []

    @Published var rawPreviewImage: NSImage?
    // 무보정 현상본(Before 비교용) — Target=main, 스캐너 프로파일 없음, 인스펙터 조정 전부 기본값.
    // 사용자가 슬라이더로 만든 결과(After)와 대비되는 "현상만 된 기준본"이다.
    @Published var neutralPreviewImage: NSImage?
    @Published var developedImage: NSImage?
    // 필름스트립용 경량 썸네일(긴 변 ~360px). developedImage 와 달리 비활성 프레임에서도 유지된다
    // (메모리 FIFO 제거 대상이 아님) — 풀해상도 버퍼를 내려놓아도 썸네일은 남아 스트립이 비지 않는다.
    @Published var thumbnailImage: NSImage?
    // 한 번이라도 현상이 완료됐는지. developedImage 가 메모리 압박으로 내려갈 수 있으므로,
    // "현상됨" 여부(내보내기 가능/상태 표시)는 이 플래그로 판단한다.
    @Published var hasDevelopedOnce: Bool = false
    @Published var showDeveloped: Bool = true
    @Published var isDeveloping: Bool = false
    // 결함 제거(ICE) 재생성 중 여부. 현상(isDeveloping)과 분리해, 값만 바꿔 재현상할 때
    // "결함 제거" 버튼이 스피너로 보이지 않게 한다(ICE 재실행 오해 방지).
    @Published var isRemovingDefects: Bool = false
    @Published var debugOverlayEnabled: Bool = false
    @Published var debugOverlayStage: DevelopDebugStage = .afterInversion
    @Published var debugPreviewImages: [DevelopDebugStage: NSImage] = [:]
    @Published var debugMetrics: [DevelopDebugStage: DevelopDebugMetrics] = [:]

    var rawPreviewTransform: ImageTransform?
    // 무보정 프리뷰 캐시 무효화 키. transform/baseKey가 바뀔 때만 재현상한다(슬라이더 조정엔 불변).
    var neutralPreviewTransform: ImageTransform?
    var neutralPreviewBaseKey: FilmBaseCacheKey?
    var developRevision: Int = 0
    var cachedBaseKey: FilmBaseCacheKey?
    var cachedBase: FilmBase?

    // 변형(회전/플립/크롭) 전 display-proxy 결과. 변형은 순수 기하 연산이라 전체 현상
    // 파이프라인을 다시 돌릴 필요 없이 이 캐시에 ImageTransformStage만 다시 적용하면 된다.
    // 입력 raw가 cleaned raw이므로 결함 제거(ICE)도 이 결과에 이미 포함된다.
    var cachedDevelopedBase: CGImage?
    var cachedRawBase: CGImage?
    var cachedNeutralBase: CGImage?

    // 적용된 결함 제거 편집(브러시 + 반자동 통합, 순서 보존). 모든 현상/변형/export에서 유지된다.
    // cleaned raw = 원본 raw + defectEdits 순차 적용 → 브러시·반자동이 서로 되살아나지 않는다.
    @Published var defectEdits: [DefectEdit] = []
    // Undo 스택: 각 "결함 제거" 적용 직전 defectEdits 스냅샷. ⌘Z로 다단계 복구.
    var defectEditUndoStack: [[DefectEdit]] = []
    var canUndoDefects: Bool { !defectEditUndoStack.isEmpty }

    // ICE를 적용한 raw 스캔. 현상·export는 이 cleaned raw를 입력으로 써서 어떤 파라미터(Target/
    // Profile/Film/Mode/인스펙터 전 항목)를 바꿔도 결함 제거가 유지되고 재계산되지 않는다.
    // cleanedRawImage = 메모리 적재본(16bit linear CGImage). 활성 프레임 소수만 FIFO로 적재하고
    //   다른 프레임으로 이동하면 내려놓는다 → 동시 메모리 점유를 제한한다.
    // cleanedRawDiskURL = 디스크 백킹(LZW TIFF). 메모리에서 내려놓아도 유지되어, 재진입 시
    //   ICE 재계산 없이 즉시 복원한다. 앱 시작 시 청소되어 공간을 남기지 않는다.
    var cleanedRawImage: CGImage?
    var cleanedRawDiskURL: URL?
    var cleanedRawEditCount: Int = 0   // 현재 cleaned raw 가 담은 defectEdits 개수(증분 빌드 기준)
    var cleanRawRevision: Int = 0
    var cleanRawTask: Task<Void, Never>?

    // MARK: Region ICE(반자동) 세션 — "제거" 전까지 휘발. 브러시(defectStrokes)와 완전히 별개의
    // 경로지만 결과는 같은 cleaned raw 저장소에 누적된다(현상 입력은 하나).
    @Published var iceActive: Bool = false           // 검출 결과(빨강)를 표시 중
    @Published var iceIsDetecting: Bool = false
    @Published var iceIsRemoving: Bool = false
    @Published var iceSensitivity: Double = 1.85   // 슬라이더 0.7~3.0 의 정중앙(기본)
    @Published var iceExcludedIDs: Set<Int32> = []   // 클릭으로 제외한 컴포넌트
    @Published var icePreview: [ICEPreviewComponent] = []   // 화면 표시용(base 정규 점)
    var iceLabelField: ICELabelField?                // base ROI 로컬 라벨맵
    var iceBaseSize: CGSize?                          // raw 픽셀 크기(좌표 변환용)
    var iceROIPixelX0: Int = 0                        // base ROI left (y-down px)
    var iceROIPixelY0: Int = 0                        // base ROI top  (y-down px)
    var iceROICIyup: CGRect?                          // 검출/복원에 쓴 CIImage(y-up) ROI
    var iceDetectRevision: Int = 0
    var iceDetectTask: Task<Void, Never>?
    var hasRegionICEPreview: Bool { iceActive && !icePreview.isEmpty }

    init(
        scanIndex: Int,
        rawScanURL: URL,
        filmType: FilmType,
        initialTransform: ImageTransform = .identity,
        scannedAt: Date = Date(),
        sourceFrameID: UUID? = nil,
        sourceFrameDisplayName: String? = nil,
        virtualCopyNumber: Int? = nil
    ) {
        self.scanIndex = scanIndex
        self.rawScanURL = rawScanURL
        self.scannedAt = scannedAt
        self.sourceFrameID = sourceFrameID
        self.sourceFrameDisplayName = sourceFrameDisplayName
        self.virtualCopyNumber = virtualCopyNumber
        self.filmType = filmType
        self.params = DevelopParameters()
        self.imageTransform = initialTransform
    }

    /// 표시용 이름.
    var displayName: String {
        guard let virtualCopyNumber else { return "Frame \(scanIndex)" }
        return "Frame \(scanIndex) Copy \(virtualCopyNumber)"
    }

    var compactDisplayName: String {
        guard let virtualCopyNumber else { return displayName }
        return "Frame \(scanIndex) C\(virtualCopyNumber)"
    }

    var isVirtualCopy: Bool { virtualCopyNumber != nil }

    var rootFrameID: UUID { sourceFrameID ?? id }

    var rootFrameDisplayName: String { sourceFrameDisplayName ?? "Frame \(scanIndex)" }

    var selectionSummary: String {
        let ratingText = rating > 0 ? "\(rating) star" : "Unrated"
        let stateText: String
        switch pickState {
        case .unflagged: stateText = "Unflagged"
        case .picked: stateText = "Pick"
        case .rejected: stateText = "Reject"
        }
        return "\(ratingText) · \(stateText)"
    }

    var sidecarVirtualCopyInfo: Sidecar.VirtualCopyInfo? {
        guard let virtualCopyNumber else { return nil }
        return Sidecar.VirtualCopyInfo(
            sourceFrameID: rootFrameID.uuidString,
            sourceFrameName: rootFrameDisplayName,
            copyNumber: virtualCopyNumber
        )
    }

    func updateParams(_ body: (inout DevelopParameters) -> Void) {
        var next = params
        body(&next)
        params = next
    }

    func setRating(_ value: Int) {
        rating = min(max(value, 0), 5)
    }

    func clearSelection() {
        rating = 0
        pickState = .unflagged
    }

    func updateTransform(_ body: (inout ImageTransform) -> Void) {
        var next = imageTransform
        body(&next)
        imageTransform = next
    }
}

extension ScanFrame: Hashable {
    nonisolated static func == (lhs: ScanFrame, rhs: ScanFrame) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
