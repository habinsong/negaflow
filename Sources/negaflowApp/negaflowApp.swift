import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

// MARK: - negaflow SwiftUI App
//
// 순정 macOS 앱 톤(Apple Photos / Image Capture 느낌).
// NavigationSplitView = 자동 Liquid Glass. AI SaaS/대시보드 냄새 금지.
// 엔진(색감)은 건드리지 않는다 — UI/UX만.
@main
struct negaflowApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1400, minHeight: 720)
                .environmentObject(model)
                .preferredColorScheme(model.appearanceMode.colorScheme)
        }
    }
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

// MARK: - Canvas background (사용자 선택, 우클릭 메뉴)
enum CanvasBackground: String, CaseIterable, Identifiable {
    case black, gray, white
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .black: return Color(white: 0.07)
        case .gray:  return Color(white: 0.5)
        case .white: return Color(white: 0.97)
        }
    }
    var label: String {
        switch self {
        case .black: return "검정"
        case .gray:  return "회색"
        case .white: return "흰색"
        }
    }
}

// MARK: - AppModel
@MainActor
final class AppModel: ObservableObject {
    static let mockDeviceID = "mock"
    static let mockDisplayName = "Plustek OpticFilm 8200i (Demo)"
    private static let canvasBackgroundKey = "canvasBackground"
    private static let appearanceModeKey = "appearanceMode"

    let saneBackend = SANEBackend()
    let mockBackend = MockScannerBackend()

    @Published var demoMode: Bool = false
    @Published var devices: [ScannerDescriptor] = []
    @Published var selectedDeviceID: String?
    @Published var isDetecting: Bool = false

    // 진행/상태(전역)
    @Published var scanPhase: ScanPhase = .idle
    @Published var scanFraction: Double = 0
    @Published var statusMessage: String = "Idle"
    @Published var isScanning: Bool = false
    @Published var batchTotal: Int = 0
    @Published var batchIndex: Int = 0
    // 현상 처리 상태(스캔과 분리). 슬라이더/선택/배치 현상이 진행 중일 때 하단 상태바에 상세를 표시한다.
    // 과거엔 현상이 전역 scanPhase 를 .processingNegative/.complete 로 매 호출마다 덮어써(slider 한 틱마다)
    // 상태바가 깜빡이고 스캔 진행률과 동기화가 깨졌다. 현상은 이 전용 필드로만 보고한다.
    @Published var processingActive: Bool = false
    @Published var processingDetail: String = ""
    var developInFlight: Int = 0
    // 슬라이더 드래그 중 현상 렌더 레이트 상한(throttle). 과거엔 매 틱마다 리비전을 올려 진행 중
    // 루프가 상한 없이 연속 렌더 → createCGImage/IOSurface 누적으로 GPU 압박, 간헐적 블랭크 렌더가
    // 발생했다(SamplingContextPool 주석에 기록된 "이미지가 사라짐" 실패 모드). 리딩+트레일링 throttle로
    // ~22fps 라이브 상한을 둬 GPU 부하를 제한하면서 즉각 반응은 유지한다.
    var developThrottleLast: Date = .distantPast
    var developThrottleTask: Task<Void, Never>?
    static let developThrottleInterval: TimeInterval = 0.045

    // 롤/프레임
    @Published var frames: [ScanFrame] = []
    @Published var selectedFrameID: UUID? {
        didSet {
            guard selectedFrameID != oldValue else { return }
            // 이전 프레임의 Region ICE 세션(미리보기 라벨맵·점·진행 중 검출)을 내려놓는다 — 세션은
            // 휘발이므로 다른 프레임으로 이동하면 메모리에 둘 이유가 없다(다 쓴 메모리 즉시 해제).
            if let prev = frames.first(where: { $0.id == oldValue }), prev.iceActive || prev.iceIsDetecting {
                cancelRegionICE(prev)
            }
            guard let frame = selectedFrame else { return }
            ensureCleanedRawResident(frame)   // 선택 프레임의 cleaned raw를 메모리에 적재(FIFO)
            markDevelopedResident(frame)       // 풀해상도 발색 버퍼 FIFO 갱신(선택 프레임은 항상 유지)
            // 메모리 압박으로 풀해상도 버퍼가 내려간 프레임으로 재진입하면 즉시 재현상해 채운다.
            if frame.developedImage == nil, frame.hasDevelopedOnce, !isScanning {
                Task { await developFrame(frame) }
            }
        }
    }

    // cleaned raw 메모리 캐시 FIFO. 활성 프레임 소수만 적재해 동시 메모리 점유를 제한한다.
    var residentCleanedRawIDs: [UUID] = []
    let maxResidentCleanedRaw = 2

    // 발색 결과(풀해상도 NSImage + 변형-전 CGImage base)도 FIFO로 제한한다. 과거엔 모든 프레임이
    // developed/raw/neutral NSImage + 3개 CGImage base 를 영구 보존해, 롤이 커지면 프레임당 수십 MB가
    // 누적돼 메모리가 폭증했다(36컷이면 GB 단위). 최근 본 소수 프레임만 풀해상도를 유지하고, 나머지는
    // 풀해상도 버퍼를 내려놓되 경량 썸네일(thumbnailImage)은 남겨 필름스트립이 비지 않게 한다.
    // 재진입 시 raw(또는 cleaned raw)에서 즉시 재현상한다.
    var residentDevelopedIDs: [UUID] = []
    let maxResidentDeveloped = 3
    @Published var copiedDevelopSettings: DevelopSettingsSnapshot?
    @Published var snapshotCompareState: SnapshotCompareState?
    @Published var userDevelopPresets: [DevelopUserPreset] = [] {
        didSet { saveUserDevelopPresets() }
    }

    // 스캔 옵션(다음 스캔에 적용)
    @Published var filmType: FilmType = .colorNegative
    @Published var developTarget: DevelopTarget = .main
    @Published var scannerProfileID: String?
    @Published var resolutionChoice: Resolution = .r3600
    @Published var bitDepthChoice: BitDepth = .sixteen
    @Published var colorModeChoice: ColorMode = .color
    @Published var multiExposureEnabled: Bool = false
    @Published var nextScanOrientation: ImageTransform = .identity
    // 좌우/상하 Before·After 비교가 화면에 떠 있는지. 무보정 프리뷰는 이 값이 true일 때만 렌더한다
    // (비교를 안 볼 땐 추가 현상 패스·메모리를 쓰지 않음).
    @Published var beforeAfterCompareActive: Bool = false

    @Published var capabilities: ScannerCapabilities?
    @Published var diagnostics: String = ""
    @Published var appearanceMode: AppAppearanceMode = .system {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.appearanceModeKey) }
    }

    /// 중앙 캔버스 배경색 — 우클릭 메뉴로 흰/회/검 선택. UserDefaults에 유지.
    @Published var canvasBackground: CanvasBackground = .black {
        didSet { UserDefaults.standard.set(canvasBackground.rawValue, forKey: Self.canvasBackgroundKey) }
    }

    // 내보내기 설정(좌측탭 Output · 상단 버튼 공유). UserDefaults에 유지.
    @Published var exportFormat: ExportFormat = .jpeg {
        didSet { UserDefaults.standard.set(exportFormat.rawValue, forKey: "export.format") }
    }
    @Published var exportColorSpace: ExportColorSpace = .sRGB {
        didSet { UserDefaults.standard.set(exportColorSpace.rawValue, forKey: "export.colorSpace") }
    }
    /// 0 = 미지정(스캔 DPI 사용).
    @Published var exportDPI: Int = 0 {
        didSet { UserDefaults.standard.set(exportDPI, forKey: "export.dpi") }
    }
    /// 긴 변 픽셀 상한. 0 = 원본 크기.
    @Published var exportLongEdge: Int = 0 {
        didSet { UserDefaults.standard.set(exportLongEdge, forKey: "export.longEdge") }
    }
    @Published var exportWriteSidecar: Bool = false
    @Published var quickExportFormat: ExportFormat = .jpeg {
        didSet { UserDefaults.standard.set(quickExportFormat.rawValue, forKey: "export.quick.format") }
    }
    @Published var quickExportDPI: Int = 300 {
        didSet { UserDefaults.standard.set(quickExportDPI, forKey: "export.quick.dpi") }
    }
    /// nil = ~/Downloads.
    @Published var quickExportFolderPath: String? = nil {
        didSet { UserDefaults.standard.set(quickExportFolderPath, forKey: "export.quick.folder") }
    }

    var exportOptions: ExportOptions {
        ExportOptions(colorSpace: exportColorSpace, dpi: exportDPI,
                      longEdge: exportLongEdge > 0 ? exportLongEdge : nil)
    }
    /// Quick Export: 미리 선택된 포맷/DPI, 원본 해상도 유지, sRGB.
    var quickExportOptions: ExportOptions {
        ExportOptions(colorSpace: .sRGB, dpi: quickExportDPI, longEdge: nil)
    }
    var quickExportFolderURL: URL {
        if let path = quickExportFolderPath, !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }
    var quickExportFolderDisplay: String { quickExportFolderURL.lastPathComponent }

    let presets: [LookPreset] = PresetRegistry.loadAll()
    let scannerProfiles: [ScannerProfile] = ScannerProfileRegistry.loadAll()
    var lastProgressUpdateAt: Date = .distantPast
    var lastProgressFraction: Double = -1
    var lastProgressPhase: ScanPhase = .idle
    var lastProgressMessage: String = ""
    var activeDevelopmentFrameIDs = Set<UUID>()

    var backend: ScannerBackend? { demoMode ? mockBackend : (hasSANE ? saneBackend : nil) }
    var saneDevices: [ScannerDescriptor] { devices.filter { $0.backendType == .sane } }
    var hasSANE: Bool { devices.contains { $0.backendType == .sane } }
    var hasScanner: Bool { backend != nil }
    var canScan: Bool { hasScanner && !isScanning }
    var effectiveScannerID: String? {
        if demoMode { return Self.mockDeviceID }
        return saneDevices.first(where: { $0.id == selectedDeviceID })?.id ?? saneDevices.first?.id
    }
    var activeScannerDisplayName: String {
        if demoMode { return Self.mockDisplayName }
        return saneDevices.first(where: { $0.id == selectedDeviceID })?.displayName
            ?? saneDevices.first?.displayName
            ?? "스캐너 없음"
    }
    var selectedFrame: ScanFrame? {
        guard let id = selectedFrameID else { return nil }
        return frames.first(where: { $0.id == id })
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.canvasBackgroundKey),
           let stored = CanvasBackground(rawValue: raw) {
            canvasBackground = stored
        }
        if let raw = UserDefaults.standard.string(forKey: Self.appearanceModeKey),
           let stored = AppAppearanceMode(rawValue: raw) {
            appearanceMode = stored
        }
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "export.format"), let v = ExportFormat(rawValue: raw) { exportFormat = v }
        if let raw = defaults.string(forKey: "export.colorSpace"), let v = ExportColorSpace(rawValue: raw) { exportColorSpace = v }
        exportDPI = defaults.integer(forKey: "export.dpi")
        exportLongEdge = defaults.integer(forKey: "export.longEdge")
        if let raw = defaults.string(forKey: "export.quick.format"), let v = ExportFormat(rawValue: raw) { quickExportFormat = v }
        let qd = defaults.integer(forKey: "export.quick.dpi")
        quickExportDPI = qd > 0 ? qd : 300
        quickExportFolderPath = defaults.string(forKey: "export.quick.folder")
        userDevelopPresets = loadUserDevelopPresets()
        // 구버전이 디스크에 남겼을 수 있는 ICE 임시 캐시를 시작 시 청소한다(현재는 메모리 캐시라
        // 디스크에 만들지 않음 — 잔재가 공간을 차지하지 않도록 보장).
        let iceTempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-ice", isDirectory: true)
        try? FileManager.default.removeItem(at: iceTempDir)
    }
}
