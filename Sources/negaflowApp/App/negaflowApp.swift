import AppKit
import Chromabase
import Combine
import CoreImage
import ScannerKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    // 기존 demo catalog/shortcut 호환을 위해 8200i 계열 내부 ID를 기본값으로 유지한다.
    static let mockDeviceID = MockScannerBackend.filmScannerID
    static let mockFlatbedDeviceID = MockScannerBackend.flatbedScannerID
    static let mockDisplayName = "Negaflow Scanner"
    static let mockFlatbedDisplayName = "Negaflow Flatbed Scanner"

    let mockBackend: ScannerBackend
    var pluginBackends: [ExternalScannerBackend] = []
    let scannerPluginTrustStore: ScannerPluginTrustStore?

    @Published var demoMode = false
    @Published var devices: [ScannerDescriptor] = []
    @Published var installedScannerPlugins: [InstalledScannerPlugin] = []
    @Published var showScannerControls = false
    @Published var selectedDeviceID: String?
    @Published var isDetecting = false
    var didRunStartupScannerCheck = false

    @Published var scanPhase: ScanPhase = .idle
    @Published var scanFraction: Double = 0
    /// 상태 메시지 전용 발행 경계 — 읽는 뷰(상태바/스캔 오버레이)만 이 객체를 관찰한다.
    let statusCenter = StatusMessageCenter()
    /// 최근 오류 기록 — 상태바 빨간 점(클릭/호버)과 진단 리포트가 읽는다. statusMessage 토스트가
    /// 사라진 뒤에도 "무엇이 실패했는지"를 유지한다.
    let errorLog = AppErrorLog()
    /// 기존 대입 지점(150여 곳)을 유지하는 facade. @Published 가 아니므로 메시지 갱신이
    /// AppModel 전역 무효화를 일으키지 않는다(ObservationBoundaryTests 가 발화 0회를 고정).
    var statusMessage: String {
        get { statusCenter.message }
        set { statusCenter.message = newValue }
    }
    @Published var isScanning = false
    @Published var isScanFinalizationInProgress = false
    @Published var batchTotal = 0
    @Published var batchIndex = 0
    let exportBatchStore = ExportBatchStore()
    let exportAvailabilityStore = ExportAvailabilityStore()
    @Published var selectedExportRecipeID: UUID?
    @Published var isPrintPackageExporting = false
    @Published var activeWorkspaceModule: WorkspaceModule = .develop {
        didSet {
            guard activeWorkspaceModule != oldValue else { return }
            softProofConfigurationRevision &+= 1
            refreshSoftProofPreviewIfNeeded()
        }
    }
    @Published var libraryCullingMode = LibraryCullingMode.grid

    let frameStore = FrameStore()
    let rollStore = RollStore()
    let stackStore = StackStore()
    @Published var selectedFrameIDs: Set<UUID> = []
    @Published var interactionScopeFrameIDs: [UUID]?
    var frameSelectionAnchorID: UUID?
    let frameCacheManager = FrameCacheManager()
    private var memoryPressureMonitor: MemoryPressureMonitor?
    let pixelSamplerStore = PixelSamplerStore()
    let developController = DevelopController()
    var selectedFrameDevelopTask: Task<Void, Never>?

    @Published var libraryFolders: [LibraryFolder] = []
    @Published var isSourceMoveInProgress = false
    @Published var sourceAvailabilityRevision: UInt64 = 0
    @Published var libraryQueryGeneration: UInt64 = 0
    var libraryQueryContextCache: LibraryQueryContext?
    var libraryBrowserProjectionCache: LibraryBrowserProjectionCache?
    var libraryFrameIDsSnapshot: [UUID] = []
    var libraryFramesByIDCache: [UUID: ScanFrame] = [:]
    var libraryFolderProjectionRevision: UInt64 = 0
    var libraryFolderSectionsCache: [LibraryFolderSection]?
    var libraryFolderTreeProjectionCache: LibraryFolderTreeProjectionCache?
    var librarySourceAvailabilityCache: [UUID: LibrarySourceAvailability]?
    var libraryFolderAvailabilityCache: [UUID: Bool] = [:]
    var frameQueryObservations: [UUID: LibraryFrameQueryObservation] = [:]
    var sourceAvailabilityRefreshTask: Task<Void, Never>?
    var sourceAvailabilityRefreshID = UUID()
    var folderAvailabilityRefreshTask: Task<Void, Never>?
    var folderAvailabilityRefreshID = UUID()

    let exportSettingsStore: ExportSettingsStore
    let exportRecipeStore: ExportRecipeStore
    let printWorkspaceSettingsStore: PrintWorkspaceSettingsStore
    let printLayoutTemplateStore: PrintLayoutTemplateStore
    let presentationPreferencesStore: PresentationPreferencesStore
    let workflowShortcutStore: WorkflowShortcutStore
    /// 프루프/목적지 색역 표시 설정이 바뀔 때 증가한다. 비동기 렌더가 이전 설정의 결과를
    /// 새 프리뷰에 적용하지 못하게 하고, 비활성 프레임의 stale 프루프를 재선택 시 감지한다.
    var softProofConfigurationRevision: UInt64 = 0
    let diskStorage: DiskStorageStore
    let backupDestinationStore: LibraryBackupDestinationStore
    let backupScheduleStore: LibraryBackupScheduleStore
    private var storeCancellables: Set<AnyCancellable> = []

    let thumbnailDiskCache = ThumbnailDiskCache()
    let libraryCatalogURL: URL
    let libraryDefectDirectoryURL: URL
    let libraryBackupDirectoryURL: URL
    var libraryProcessLock: LibraryProcessLock?
    var libraryPersistenceEnabled = false
    var libraryCatalogBlockReason: LibraryCatalogOpenFailure?
    @Published var ambiguousExportCommitTransactionIDs: [UUID] = []
    @Published var preservableExportCommitTransactionIDs: [UUID] = []
    @Published var libraryLifecycleState: LibraryLifecycleState = .idle
    // 저장 세대 카운터는 모델 내부 로직 전용(뷰/구독 읽기 없음) — @Published 로 두면
    // 현상 슬라이더 틱마다(frame 변경 → scheduleLibrarySave → markDirty) 앱 전역이
    // 무효화된다. 반응형 소비자가 생기면 그때 전용 store 로 분리한다(ObservationBoundaryTests).
    var libraryCatalogDirtyGeneration: UInt64 = 0
    var libraryCatalogPersistedGeneration: UInt64 = 0
    @Published var libraryCatalogPersistenceError: LibraryCatalogPersistenceError?
    @Published var scanSessions: [ScanSession] = []
    @Published var scanRollAssignments: [LibraryScanRollAssignment] = []
    @Published var manualCollections: [LibraryManualCollection] = []
    @Published var smartCollections: [LibrarySmartCollection] = []
    @Published var savedSearches: [LibrarySavedSearch] = []
    @Published var libraryPendingRestoreMarker: LibraryPendingRestoreMarker?
    @Published var isLibraryMaintenanceInProgress = false
    var didRestoreLibrary = false
    var librarySaveTask: Task<Void, Never>?
    var isAcknowledgedLibraryTransactionActive = false
    var librarySaveRequestedDuringTransaction = false
    var isLibraryTerminationSaveInProgress = false
    var libraryTerminationAttemptGeneration: UInt64?
    var frameObservations: [UUID: AnyCancellable] = [:]
    var libraryFrameRecordCache: [UUID: LibraryFrameRecord] = [:]
    var dirtyLibraryFrameRecordIDs: Set<UUID> = []
    weak var catalogUndoManager: UndoManager?

    @Published var copiedDevelopSettings: DevelopSettingsSnapshot?
    @Published var snapshotCompareState: SnapshotCompareState?
    @Published var userDevelopPresets: [DevelopUserPreset] = [] {
        didSet { saveUserDevelopPresets() }
    }

    /// 현상 파이프라인이 현재 사용할 프로세스 계열. 스캐너의 원본 필름 분류와 독립적으로 바꿀 수 있다.
    @Published var filmType: FilmType = .colorNegative
    /// 스캐너 요청과 스캔 원본 폴더 분류에 사용하는 물리 필름 종류.
    @Published var scanFilmType: FilmType = .colorNegative
    /// 스캔 결과에 처음 적용할 현상 프로세스. 기본값은 `scanFilmType`과 함께 움직인다.
    @Published var scanDevelopFilmType: FilmType = .colorNegative
    /// nil이면 현재 앱 언어의 `untitledFilm`을 표시하고 실제 폴더명에도 사용한다.
    @Published var scanFolderNameDraft: String?
    @Published var developTarget: DevelopTarget = .main
    @Published var scannerProfileID: String?
    @Published var resolutionChoice: Resolution = .r3600
    @Published var bitDepthChoice: BitDepth = .sixteen
    @Published var colorModeChoice: ColorMode = .color
    @Published var multiExposureEnabled = false
    @Published var scannerBrightness: Double = 0
    @Published var scannerContrast: Double = 0
    @Published var scanFrameFormat: FilmFrameFormat = .fullFrame35mm
    @Published var scannerSimulatorIncludesPerforation = false
    @Published var selectedHardwareScanArea: ScanArea?
    var flatbedScanRegionRevision: UInt64 = 0
    @Published var flatbedScanRegions: [FlatbedScanRegion] = [] {
        didSet { flatbedScanRegionRevision &+= 1 }
    }
    @Published var selectedFlatbedScanRegionID: UUID?
    @Published var flatbedPreviewFrameID: UUID?
    @Published var flatbedPreviewScanArea: ScanArea?
    @Published var infraredEnabled = false
    @Published var nextScanOrientation: ImageTransform = .identity
    @Published var beforeAfterCompareActive = false
    @Published var beforeAfterMainCompareActive = false
    @Published var beforeAfterToggleRequest = 0
    var pendingDevelopToolShortcutAction: WorkflowShortcutAction?
    @Published var developToolShortcutRequest = 0
    var canvasDisplayTargetPixels: CGFloat = 0
    @Published var capabilities: ScannerCapabilities?
    /// 진단 리포트 전용 스토어 — 팝오버가 이 객체를 관찰한다(AppModel 전역 무효화 없음).
    let diagnosticsCenter = DiagnosticsCenter()

    @Published var exportWriteSidecar = false
    let presets: [LookPreset] = PresetRegistry.loadAll()
    let scannerProfiles: [ScannerProfile] = ScannerProfileRegistry.loadAll()
    var lastProgressUpdateAt: Date = .distantPast
    var lastProgressFraction: Double = -1
    var lastProgressPhase: ScanPhase = .idle
    var lastProgressMessage = ""
    var capabilityRequestID: UUID?
    var activeScanSessionID: UUID?
    var activeScannerBackend: ScannerBackend?
    var reservedExportArtifactPaths: Set<String> = []
    var activeExportBatchPlans: [ExportBatchPlan] = []

    init(
        exportSettingsStore: ExportSettingsStore? = nil,
        exportRecipeStore: ExportRecipeStore? = nil,
        printWorkspaceSettingsStore: PrintWorkspaceSettingsStore? = nil,
        printLayoutTemplateStore: PrintLayoutTemplateStore? = nil,
        presentationPreferencesStore: PresentationPreferencesStore? = nil,
        workflowShortcutStore: WorkflowShortcutStore? = nil,
        diskStorageStore: DiskStorageStore? = nil,
        backupDestinationStore: LibraryBackupDestinationStore? = nil,
        backupScheduleStore: LibraryBackupScheduleStore? = nil,
        scannerDemoBackend: ScannerBackend? = nil,
        scannerPluginTrustStore: ScannerPluginTrustStore? = ScannerPluginTrustStore.default,
        libraryCatalogURL: URL? = nil,
        libraryDefectDirectoryURL: URL? = nil,
        libraryBackupDirectoryURL: URL? = nil
    ) {
        self.mockBackend = scannerDemoBackend ?? MockScannerBackend()
        self.scannerPluginTrustStore = scannerPluginTrustStore
        self.exportSettingsStore = exportSettingsStore ?? ExportSettingsStore()
        self.exportRecipeStore = exportRecipeStore ?? ExportRecipeStore()
        self.printWorkspaceSettingsStore = printWorkspaceSettingsStore ?? PrintWorkspaceSettingsStore()
        self.printLayoutTemplateStore = printLayoutTemplateStore ?? PrintLayoutTemplateStore()
        self.presentationPreferencesStore = presentationPreferencesStore ?? PresentationPreferencesStore()
        self.workflowShortcutStore = workflowShortcutStore ?? WorkflowShortcutStore()
        self.diskStorage = diskStorageStore ?? DiskStorageStore()
        self.backupDestinationStore = backupDestinationStore ?? LibraryBackupDestinationStore()
        self.backupScheduleStore = backupScheduleStore ?? LibraryBackupScheduleStore()
        self.libraryCatalogURL = libraryCatalogURL ?? LibraryCatalogFile.defaultURL()
        self.libraryDefectDirectoryURL = libraryDefectDirectoryURL
            ?? DefectSidecarFile.defaultDirectoryURL()
        self.libraryBackupDirectoryURL = libraryBackupDirectoryURL
            ?? LibraryBackupStore.defaultDirectoryURL()
        frameStore.objectWillChange.sink { [objectWillChange] _ in objectWillChange.send() }
            .store(in: &storeCancellables)
        rollStore.objectWillChange.sink { [objectWillChange] _ in objectWillChange.send() }
            .store(in: &storeCancellables)
        stackStore.objectWillChange.sink { [objectWillChange] _ in objectWillChange.send() }
            .store(in: &storeCancellables)
        self.diskStorage.objectWillChange.sink { [objectWillChange] _ in objectWillChange.send() }
            .store(in: &storeCancellables)
        self.backupDestinationStore.objectWillChange.sink { [objectWillChange] _ in objectWillChange.send() }
            .store(in: &storeCancellables)
        self.backupScheduleStore.objectWillChange.sink { [objectWillChange] _ in objectWillChange.send() }
            .store(in: &storeCancellables)
        self.exportSettingsStore.objectWillChange.sink { [objectWillChange] _ in objectWillChange.send() }
            .store(in: &storeCancellables)
        self.exportRecipeStore.objectWillChange.sink { [objectWillChange] _ in objectWillChange.send() }
            .store(in: &storeCancellables)
        self.printWorkspaceSettingsStore.objectWillChange.sink { [objectWillChange] _ in
            objectWillChange.send()
        }
        .store(in: &storeCancellables)
        self.printLayoutTemplateStore.objectWillChange.sink { [objectWillChange] _ in
            objectWillChange.send()
        }
        .store(in: &storeCancellables)
        // 선택적 브리지(관찰 경계 축소 2단계): 배치 아이템 상태 틱은 프레임당 2회 발행되는
        // 최고 빈도 스트림인데 읽는 뷰(ExportBatchProgressView)가 store 를 직접 관찰하므로
        // 앱 전역으로 중계하지 않는다. AppModel 파생 상태(canExportSelection 의
        // exportBatchStore.isRunning 의존)가 필요로 하는 isRunning 전이만 발행한다(배치당 2회).
        exportBatchStore.$isRunning.removeDuplicates().dropFirst()
            .sink { [objectWillChange] _ in objectWillChange.send() }
            .store(in: &storeCancellables)
        self.presentationPreferencesStore.objectWillChange.sink { [objectWillChange] _ in objectWillChange.send() }
            .store(in: &storeCancellables)
        self.workflowShortcutStore.objectWillChange.sink { [objectWillChange] _ in objectWillChange.send() }
            .store(in: &storeCancellables)

        userDevelopPresets = loadUserDevelopPresets()
        frameStore.$frames.sink { [weak self] frames in
            guard let self else { return }
            MainActor.assumeIsolated { self.frameListDidChange(frames) }
        }
        .store(in: &storeCancellables)
        rollStore.$rolls.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.scheduleLibrarySave()
                self.invalidateLibraryQueryContext()
            }
        }
        .store(in: &storeCancellables)
        rollStore.$activeRollID.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.scheduleLibrarySave()
                self.invalidateLibraryQueryContext()
            }
        }
        .store(in: &storeCancellables)
        stackStore.$stacks.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.scheduleLibrarySave() }
        }
        .store(in: &storeCancellables)
        $scanSessions.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.scheduleLibrarySave()
                self.invalidateLibraryQueryContext()
            }
        }
        .store(in: &storeCancellables)
        $libraryFolders.dropFirst().sink { [weak self] folders in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.scheduleLibraryFolderAvailabilitySnapshot(folders)
                self.invalidateLibraryFolderProjection()
                self.invalidateLibraryQueryContext()
            }
        }
        .store(in: &storeCancellables)
        $scanRollAssignments.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.scheduleLibrarySave() }
        }
        .store(in: &storeCancellables)
        $manualCollections.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.scheduleLibrarySave()
                self.invalidateLibraryQueryContext()
            }
        }
        .store(in: &storeCancellables)
        $smartCollections.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.scheduleLibrarySave() }
        }
        .store(in: &storeCancellables)
        $savedSearches.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.scheduleLibrarySave() }
        }
        .store(in: &storeCancellables)

        let defectTempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-defects", isDirectory: true)
        try? FileManager.default.removeItem(at: defectTempDirectory)

        memoryPressureMonitor = MemoryPressureMonitor { [weak self] pressure in
            Task { @MainActor [weak self] in
                self?.applyFrameCachePressure(pressure)
            }
        }
    }
}
