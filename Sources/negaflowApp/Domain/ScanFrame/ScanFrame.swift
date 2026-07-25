import Foundation
import AppKit
import Chromabase
import ScannerKit

struct FilmBaseCacheKey: Equatable, Sendable {
    let filmType: FilmType
    let mode: DevelopParameters.BaseMode
    let manualBaseRGB: SIMD3<Double>?
    let filmStockDminID: String?
    let lightSourceProfileID: String?

    init(filmType: FilmType,
         mode: DevelopParameters.BaseMode,
         manualBaseRGB: SIMD3<Double>?,
         filmStockDminID: String?,
         lightSourceProfileID: String? = nil) {
        self.filmType = filmType
        self.mode = mode
        self.manualBaseRGB = manualBaseRGB
        self.filmStockDminID = filmStockDminID
        self.lightSourceProfileID = lightSourceProfileID
    }
}

// MARK: - FrameSource (프레임 raw 입력의 출처)
//
// 로더가 원본 파일을 어떻게 해석할지 결정한다.
//   scannerTIFF  — 스캐너 산출 TIFF. 임베디드 ICC를 존중하며, 무프로필 16bit는 linear로 로드.
//   importedFile — 사용자가 가져온 RAW/DNG/TIFF/PNG/JPG 등. ImageLoader.load(RAW 데모사이크 +
//                  파일 색공간 보존)로 로드해야 색이 맞는다.
enum FrameSource: Sendable {
    case scannerTIFF
    case importedFile

    var originLabel: String {
        originLabel(language: .system)
    }

    func originLabel(language: AppLanguage) -> String {
        switch self {
        case .scannerTIFF: return AppLocalization.text(AppLocalizedPhrase.scan, language: language)
        case .importedFile: return AppLocalization.text(AppLocalizedPhrase.importSource, language: language)
        }
    }
}

// MARK: - ScanFrame (배치/세션 스캔의 단위)
//
// 한 프레임 = 하나의 raw 스캔 + 그 프레임만의 현상 파라미터/transform/결과.
// FrameStore.frames owns the roll, and selectedFrameID points at the current frame.
// 색감 엔진은 건드리지 않는다 — 프레임은 데이터 보관만 한다.
@MainActor
final class ScanFrame: ObservableObject, Identifiable {
    // 카탈로그 복원 시 저장된 id 를 그대로 쓴다(썸네일 디스크 캐시 파일명이 id 로 결정되므로).
    let id: UUID
    let scanIndex: Int                    // 롤 내 순서 (1-based 표시용)
    // 디스크 저장 폴더 규칙의 출처 폴더명(default / 가져온 폴더명 / 스캐너 축약명).
    let storageGroupName: String?
    // 보존 원본. 현상/결함 편집/export는 별도 recipe와 파생 cache를 쓰며 이 URL의 파일을
    // 덮어쓰지 않는다. URL 자체는 사용자가 명시한 재연결 또는 persistent bookmark 복원에서만
    // 갱신된다.
    @Published private(set) var rawScanURL: URL
    /// 같은 경로로 재연결되는 경우까지 비동기 작업의 원본 세대를 구분하는 런타임 카운터.
    /// 카탈로그에는 저장하지 않으며 updateSourceLocation을 거칠 때마다 증가한다.
    private(set) var sourceLocationRevision: UInt64 = 0
    private(set) var rawScanBookmarkData: Data?
    /// 스캐너 IR(적외선) 채널 TIFF(본 스캔과 같은 해상도/영역). IR 스캔을 켠 프레임만 존재.
    @Published private(set) var infraredScanURL: URL?
    private(set) var infraredScanBookmarkData: Data?
    let sourceKind: FrameSource           // raw 입력 출처(로더 분기용)
    let sourcePixelWidth: Int?
    let sourcePixelHeight: Int?
    let sourceResolutionDPI: Int?
    let sourceBitDepth: Int?
    @Published private(set) var sourceMetadata: SourceMetadataSnapshot?
    @Published private(set) var appMetadataOverlay: AppMetadataOverlay?
    /// 영속 ScannerKit workflow의 캡처 provenance. 가져온 파일·legacy frame·preview는 nil이다.
    /// 가상 사본은 원본과 같은 session/job 참조를 공유한다.
    let scanSessionID: UUID?
    let scanJobID: UUID?
    /// Overview 스캔의 세션 전용 프레임. 카탈로그에 저장하지 않고 본 스캔 성공 시 제거한다.
    let isPreviewScan: Bool
    let scannedAt: Date
    let sourceFrameID: UUID?
    let sourceFrameDisplayName: String?
    let virtualCopyNumber: Int?
    /// 특정 출력 프로파일을 기준으로 만든 비파괴 Proof Copy의 영속 설정.
    /// 원본 래스터는 공유하고 현상 조정은 가상 사본 생성 시점부터 독립된다.
    @Published var proofCopyConfiguration: ProofCopyConfiguration?

    @Published var filmType: FilmType
    @Published var preset: LookPreset?
    @Published var params: DevelopParameters
    @Published var imageTransform: ImageTransform
    @Published var baseRGB: SIMD3<Double>?
    @Published private(set) var rating: Int = 0
    @Published var pickState: FramePickState = .unflagged
    @Published var customDisplayName: String?
    @Published var developHistory: [DevelopHistoryEntry] = []
    @Published var developSnapshots: [DevelopSnapshot] = []
    @Published var libraryWorkflowTrackingState: LibraryFrameWorkflowTrackingState?
    var libraryDevelopRecipeFingerprintCacheKey: LibraryDevelopRecipeFingerprintCacheKey?
    var libraryDevelopRecipeFingerprintCacheSHA256: String?

    @Published var rawPreviewImage: NSImage?
    // 무보정 현상본(Before 비교용) — Target=main, 스캐너 프로파일 없음, 인스펙터 조정 전부 기본값.
    // 사용자가 슬라이더로 만든 결과(After)와 대비되는 "현상만 된 기준본"이다.
    @Published var neutralPreviewImage: NSImage?
    // 현재 조정을 유지하고 현상 타깃만 MAIN으로 바꾼 비교본.
    @Published var mainPreviewImage: NSImage?
    @Published var developedImage: NSImage?
    /// 현상 출력에서 0/1 경계에 닿은 RGB 채널만 표시하는 투명 캔버스 레이어.
    /// 현상 픽셀·썸네일·export에는 합성하지 않습니다.
    @Published var clippingOverlayImage: NSImage?
    /// 선택한 출력 ICC의 실제 ColorSync gamut-check 결과. 채널 클리핑과 별도 레이어이며
    /// 현상 픽셀·썸네일·export에는 합성하지 않습니다.
    @Published var destinationGamutOverlayImage: NSImage?
    // 필름스트립용 경량 썸네일(긴 변 ~360px). developedImage 와 달리 비활성 프레임에서도 유지된다
    // (메모리 FIFO 제거 대상이 아님) — 풀해상도 버퍼를 내려놓아도 썸네일은 남아 스트립이 비지 않는다.
    @Published var thumbnailImage: NSImage?
    // 한 번이라도 현상이 완료됐는지. developedImage 가 메모리 압박으로 내려갈 수 있으므로,
    // "현상됨" 여부(내보내기 가능/상태 표시)는 이 플래그로 판단한다.
    @Published var hasDevelopedOnce: Bool = false
    @Published var showDeveloped: Bool = true
    @Published var isDeveloping: Bool = false
    // 결함 제거 재생성 중 여부. 현상(isDeveloping)과 분리해, 값만 바꿔 재현상할 때
    // "결함 제거" 버튼이 스피너로 보이지 않게 한다(결함 제거 재실행 오해 방지).
    @Published var isRemovingDefects: Bool = false
    @Published var debugOverlayEnabled: Bool = false
    @Published var debugOverlayStage: DevelopDebugStage = .afterInversion
    @Published var debugPreviewImages: [DevelopDebugStage: NSImage] = [:]
    @Published var debugMetrics: [DevelopDebugStage: DevelopDebugMetrics] = [:]

    var developedPreviewTransform: ImageTransform?
    var rawPreviewTransform: ImageTransform?
    // 무보정 프리뷰 캐시 무효화 키. transform/baseKey가 바뀔 때만 재현상한다(슬라이더 조정엔 불변).
    var neutralPreviewTransform: ImageTransform?
    var neutralPreviewBaseKey: FilmBaseCacheKey?
    var mainPreviewTransform: ImageTransform?
    var mainPreviewDevelopRevision: Int = -1
    var developRevision: Int = 0
    var cachedBaseKey: FilmBaseCacheKey?
    var cachedBase: FilmBase?

    // 변형(회전/플립/크롭) 전 display-proxy 결과. 변형은 순수 기하 연산이라 전체 현상
    // 파이프라인을 다시 돌릴 필요 없이 이 캐시에 ImageTransformStage만 다시 적용하면 된다.
    // 입력 raw가 cleaned raw이므로 결함 제거도 이 결과에 이미 포함된다.
    var cachedDevelopedBase: CGImage?
    var cachedClippingOverlayBase: CGImage?
    var cachedDestinationGamutOverlayBase: CGImage?
    /// 프루프가 적용되지 않은 작은 변형 전 썸네일 베이스. 프루프 표시 픽셀이 영속 썸네일로
    /// 새지 않도록 회전·크롭 fast path도 이 캐시에서 썸네일을 만든다.
    var cachedThumbnailBase: CGImage?
    var cachedRawBase: CGImage?
    var cachedNeutralBase: CGImage?
    var cachedMainBase: CGImage?
    var cachedInteractivePreviewRaw: DevelopFramePreviewRaw?
    var cachedInteractivePreviewRawRevision: Int = -1
    // 인터랙티브 raw 프록시를 만들 때 요청한 긴 변(px). 캔버스 표시 크기에 따라 달라지므로
    // 리비전과 함께 일치할 때만 캐시를 재사용한다.
    var cachedInteractivePreviewRawDimension: CGFloat = 0
    var cachedSettledPreviewRaw: DevelopFramePreviewRaw?
    var cachedSettledPreviewRawRevision: Int = -1
    // 캔버스 레이아웃 기준 픽셀 크기(정착/변형 결과 기준). 인터랙티브 프록시는 반올림 때문에
    // 종횡비가 미세하게(<0.5%) 달라질 수 있는데, 그 차이로 fitted frame이 서브픽셀 이동하며
    // "떨림"이 보이므로 레이아웃은 이 안정화된 크기만 사용한다. 실제 기하가 바뀌는 변형(회전/
    // 크롭/수평보정)은 authoritative 경로가 항상 갱신한다.
    var displayPixelSize: CGSize?
    var transformRevision: Int = 0
    /// 현재 developedImage/프루프 오버레이가 반영한 전역 프루프 설정 세대.
    var displayedSoftProofRevision: UInt64?
    var transformTask: Task<Void, Never>?
    // 가져오기/스캔 직후 첫 썸네일 시드(백그라운드 디코드). developFrameAfterFastPreview 가
    // 시드 → 현상 순서를 보존하기 위해 await 한다.
    var initialThumbnailSeedTask: Task<Void, Never>?

    // 적용된 결함 제거 편집(브러시 + 가이드 통합, 순서 보존). 모든 현상/변형/export에서 유지된다.
    // cleaned raw = 원본 raw + defectEdits(켜진 항목만) 순차 적용 → 브러시·가이드가 서로 되살아나지
    // 않는다. v2: 각 항목은 Defect Layer(켜기/끄기·강도·삭제 가능한 복원 레이어)로 다뤄진다.
    @Published var defectEdits: [DefectEditItem] = []
    /// 현재 authoritative defect recipe의 의미 identity. presentation-only 문자열과 패치 캐시는
    /// 포함하지 않는다. sourceIdentity가 nil이면 recipe는 보존되지만 cleaned-raw 캐시는 신뢰하지 않는다.
    @Published var defectRecipeIdentity: DefectRecipeIdentity?
    var defectRecipeRevision: UInt64 = 0
    // 카탈로그 복원 직후 사이드카가 아직 로드되지 않은 짧은 구간을 표시한다. 선택/편집 전에
    // 동기 복원해 비동기 로드와 새 편집이 서로 덮어쓰지 않게 한다.
    var defectEditsNeedRestore = false
    // Undo 스택: 각 "결함 제거" 적용 직전 defectEdits 스냅샷. ⌘Z로 다단계 복구.
    // 런타임 CGImage 패치 캐시는 제외하고 명령 객체(스트로크/마스크)만 COW로 공유한다.
    var defectEditUndoStack: [[DefectEditItem]] = []

    func makeDefectEditUndoSnapshot() -> [DefectEditItem] {
        var snapshot = defectEdits
        for index in snapshot.indices { snapshot[index].cachedPatches = nil }
        return snapshot
    }

    /// 증분 append와 마지막 레이어 조절에 필요한 최신 패치만 남긴다. 큰 ROI 패치를 레이어마다
    /// 누적하면 RGBA16 CGImage가 반복 횟수에 비례해 상주해 메모리 압박을 일으킨다.
    func retainOnlyDefectPatchCache(for editID: UUID?) {
        for index in defectEdits.indices where defectEdits[index].id != editID {
            defectEdits[index].cachedPatches = nil
        }
        for snapshotIndex in defectEditUndoStack.indices {
            for itemIndex in defectEditUndoStack[snapshotIndex].indices {
                defectEditUndoStack[snapshotIndex][itemIndex].cachedPatches = nil
            }
        }
    }

    /// 축출 시 패치 캐시(CGImage — 무거움)를 편집 리스트/undo 스택 전체에서 내려놓는다.
    /// 패치는 재빌드 때 재계산되므로 결과는 동일하다(RAM 만 회수).
    func stripDefectPatchCaches() {
        for i in defectEdits.indices where defectEdits[i].cachedPatches != nil {
            defectEdits[i].cachedPatches = nil
        }
        for s in defectEditUndoStack.indices {
            for i in defectEditUndoStack[s].indices where defectEditUndoStack[s][i].cachedPatches != nil {
                defectEditUndoStack[s][i].cachedPatches = nil
            }
        }
    }
    var canUndoDefects: Bool { !defectEditUndoStack.isEmpty }
    // Defect Layer 마스크 오버레이 표시 대상(nil=끔, 항목 id=그 레이어만 표시).
    @Published var defectMaskPreviewID: UUID?

    // 결함 제거를 적용한 raw 스캔. 현상·export는 이 cleaned raw를 입력으로 써서 어떤 파라미터(Target/
    // Profile/Film/Mode/인스펙터 전 항목)를 바꿔도 결함 제거가 유지되고 재계산되지 않는다.
    // cleanedRawImage = 메모리 적재본(16bit linear CGImage). 활성 프레임 소수만 FIFO로 적재한다.
    // cleanedRawDiskURL = 재생성 가능한 캐시 TIFF. 원본과 편집 recipe(sidecar)는 별도로 보존하므로
    // 캐시를 지워도 다음 선택 때 원본+recipe로 동일하게 재빌드할 수 있다.
    var cleanedRawImage: CGImage?
    // 증분 합성 캔버스(풀해상도 픽셀 상주). 커밋 픽셀(cleanedRawImage)은 이 캔버스의 CoW
    // 스냅샷이다 — 편집마다 패치 rect 만 블릿한다. 축출 시 픽셀과 함께 내려놓는다.
    var cleanedRawCanvas: CleanedRawCanvas?
    // 새 cleaned raw(cleanRawRevision)를 소비한 렌더가 화면에 발행된 마지막 revision.
    // 제거 스피너/세션 종료가 "결함 제거가 보이는 시점"을 기다리는 신호다.
    var displayedCleanRawRevision: Int = -1
    var cleanedRawDiskURL: URL?
    var cleanedRawMemoryIdentity: DefectRecipeIdentity?
    var cleanedRawDiskIdentity: DefectRecipeIdentity?
    var cleanedRawEditCount: Int = 0   // 현재 cleaned raw 가 담은 defectEdits 개수(증분 빌드 기준)
    // cleanedRawImage 가 담은 편집들의 (id, enabled, strength) 스탬프. 새 편집 append 시 현재
    // 리스트의 접두(prefix)와 그대로 일치하면 빌드 진행 여부와 무관하게 이 베이스 위에 나머지
    // 편집만 증분 적용할 수 있다(연속 브러시/가이드가 원본 재디코드 없이 쌓인다).
    var cleanedRawAppliedStamps: [DefectAppliedStamp] = []
    var cleanRawRevision: Int = 0
    var cleanRawTask: Task<Void, Never>?
    // 디스크 백킹(TIFF) 저장 태스크 — 빌드 태스크와 분리해 다음 편집이 인코딩을 기다리지 않는다.
    // 연속 편집 버스트 동안 이전 예약을 취소하고 마지막 상태만 기록한다(코얼레싱).
    var cleanedRawPersistTask: Task<Void, Never>?
    // "마지막 레이어 직전"까지의 cleaned raw(메모리 전용). 마지막 레이어의 강도/켜기 조절을
    // 원본 디코드·전체 재적용 없이 이 베이스 + 캐시 패치 합성만으로 끝내는 즉시 반응 경로.
    // 유효 조건: cleanedRawPreviousEditCount == defectEdits.count - 1. 앞선 레이어가 바뀌면 무효.
    var cleanedRawPreviousImage: CGImage?
    var cleanedRawPreviousEditCount: Int = -1
    var cleanedRawPreviousIdentity: DefectRecipeIdentity?
    // 강도 슬라이더 제스처 동안 undo 를 시작 시 1회만 푸시하기 위한 플래그.
    var defectGestureUndoPushed = false
    var defectGestureRecipeAdvanced = false
    // live strength tick은 큰 region/IR mask fingerprint를 MainActor에서 매번 다시
    // 계산하지 않고 최신 상태만 debounce한다. generation은 취소된 계산이
    // 늦게 돌아와 새 identity/build를 덮어쓰지 못하게 한다.
    var defectRecipeRefreshGeneration: UInt64 = 0
    var defectRecipeRefreshTask: Task<Void, Never>?
    var defectRecipeRefreshWorkerID: UUID?
    var defectRecipeRefreshChangedEditID: UUID?
    var defectGestureSourceIdentity: DefectSourceIdentity?

    // MARK: 영역 결함 제거(가이드) 세션 — "제거" 전까지 휘발. 브러시(defectStrokes)와 완전히 별개의
    // 경로지만 결과는 같은 cleaned raw 저장소에 누적된다(현상 입력은 하나).
    @Published var defectActive: Bool = false           // 검출 결과(빨강)를 표시 중
    @Published var defectIsDetecting: Bool = false
    @Published var defectIsRemoving: Bool = false
    @Published var defectSensitivity: Double = 0.7    // FILM-R 자동 안전 기준 기본값. 6.0은 사용자 선택 최대
    @Published var defectMicroSpecks: Bool = false      // 미세 입자는 오검출 위험이 있어 명시적으로 켠다
    // 자동/가이드 구분: true면 진입 즉시 전체 프레임을 검출(ROI 드래그 없음), false면 ROI 드래그.
    // 두 모드는 같은 검출 오버레이(RegionDefectOverlay)·세션 저장소를 공유한다.
    @Published var defectAutoMode: Bool = false
    @Published var defectExcludedIDs: Set<Int32> = []   // 클릭으로 제외한 컴포넌트
    @Published var defectPreview: [DefectPreviewComponent] = []   // 화면 표시용(base 정규 점)
    var defectLabelField: DefectLabelField?                // base ROI 로컬 라벨맵
    var defectBaseSize: CGSize?                          // raw 픽셀 크기(좌표 변환용)
    var defectROIPixelX0: Int = 0                        // base ROI left (y-down px)
    var defectROIPixelY0: Int = 0                        // base ROI top  (y-down px)
    var defectROICIyup: CGRect?                          // 검출/복원에 쓴 CIImage(y-up) ROI
    var defectDetectRevision: Int = 0
    var defectDetectTask: Task<Void, Never>?
    // 세션 검출 입력 캐시: 디스크 소스(cleaned raw 백킹/원본)는 검출 렌더마다 풀 TIFF를 다시
    // 디코드하므로 첫 검출에서 한 번만 풀해상도로 굳혀 세션 동안 재사용한다. 세션 종료 시 해제.
    var defectSessionRaw: CGImage?
    var defectSessionRawRevision: Int = -1
    // 세션 raw 전체 굳히기 백그라운드 태스크(첫 검출은 ROI 만 굳혀 먼저 반환).
    var defectSessionSolidifyTask: Task<Void, Never>?
    var hasRegionDefectPreview: Bool { defectActive && !defectPreview.isEmpty }

    init(
        scanIndex: Int,
        rawScanURL: URL,
        filmType: FilmType,
        infraredScanURL: URL? = nil,
        rawScanBookmarkData: Data? = nil,
        infraredScanBookmarkData: Data? = nil,
        sourceKind: FrameSource = .scannerTIFF,
        sourcePixelWidth: Int? = nil,
        sourcePixelHeight: Int? = nil,
        sourceResolutionDPI: Int? = nil,
        sourceBitDepth: Int? = nil,
        sourceMetadata: SourceMetadataSnapshot? = nil,
        appMetadataOverlay: AppMetadataOverlay? = nil,
        scanSessionID: UUID? = nil,
        scanJobID: UUID? = nil,
        isPreviewScan: Bool = false,
        initialTransform: ImageTransform = .identity,
        scannedAt: Date = Date(),
        sourceFrameID: UUID? = nil,
        sourceFrameDisplayName: String? = nil,
        virtualCopyNumber: Int? = nil,
        id: UUID = UUID(),
        storageGroupName: String? = nil
    ) {
        self.id = id
        self.storageGroupName = storageGroupName
        self.scanIndex = scanIndex
        let rawLocation = SourceBookmark.resolve(rawScanBookmarkData, fallbackURL: rawScanURL)
        self.rawScanURL = rawLocation.url
        self.rawScanBookmarkData = rawLocation.bookmarkData
        if let infraredScanURL {
            let infraredLocation = SourceBookmark.resolve(
                infraredScanBookmarkData,
                fallbackURL: infraredScanURL
            )
            self.infraredScanURL = infraredLocation.url
            self.infraredScanBookmarkData = infraredLocation.bookmarkData
        } else {
            self.infraredScanURL = nil
            self.infraredScanBookmarkData = nil
        }
        self.sourceKind = sourceKind
        self.sourcePixelWidth = sourcePixelWidth.flatMap { $0 > 0 ? $0 : nil }
        self.sourcePixelHeight = sourcePixelHeight.flatMap { $0 > 0 ? $0 : nil }
        self.sourceResolutionDPI = sourceResolutionDPI.flatMap { $0 > 0 ? $0 : nil }
        self.sourceBitDepth = sourceBitDepth.flatMap { $0 > 0 ? $0 : nil }
        self.sourceMetadata = sourceMetadata
        self.appMetadataOverlay = appMetadataOverlay
        self.scanSessionID = scanSessionID
        self.scanJobID = scanJobID
        self.isPreviewScan = isPreviewScan
        self.scannedAt = scannedAt
        self.sourceFrameID = sourceFrameID
        self.sourceFrameDisplayName = sourceFrameDisplayName
        self.virtualCopyNumber = virtualCopyNumber
        self.filmType = filmType
        self.params = DevelopParameters()
        self.imageTransform = initialTransform
    }

    /// 원본 픽셀을 수정하지 않고 카탈로그가 참조하는 위치만 바꾼다. 호출자는 진행 중 작업과
    /// 파생 캐시를 먼저 무효화해야 한다.
    func updateSourceLocation(
        rawURL: URL,
        infraredURL: URL?,
        sourceMetadata: SourceMetadataSnapshot?
    ) {
        sourceLocationRevision &+= 1
        let raw = rawURL.standardizedFileURL
        rawScanURL = raw
        rawScanBookmarkData = SourceBookmark.create(for: raw)
        if let infraredURL {
            let infrared = infraredURL.standardizedFileURL
            infraredScanURL = infrared
            infraredScanBookmarkData = SourceBookmark.create(for: infrared)
        } else {
            infraredScanURL = nil
            infraredScanBookmarkData = nil
        }
        self.sourceMetadata = sourceMetadata
    }

    func setAppMetadataOverlay(_ overlay: AppMetadataOverlay?) {
        appMetadataOverlay = overlay
    }

    func setRating(_ value: Int) {
        rating = min(max(value, 0), 5)
    }

    func toggleRating(_ value: Int) {
        let clampedValue = min(max(value, 1), 5)
        rating = rating == clampedValue ? 0 : clampedValue
    }

    func clearSelection() {
        rating = 0
        pickState = .unflagged
    }
}
