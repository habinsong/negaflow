using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;
using Negaflow.Shell.Shortcuts;
using Negaflow.Shell.Storage;

namespace Negaflow.Shell;

/// <summary>macOS <c>WorkflowSidebarTab</c>과 같은 현상 왼쪽 소스 탭입니다.</summary>
public enum WorkflowSidebarTab
{
    Library,
    Files,
    Versions,
    Presets,
    Film,
    Output,
}

public sealed record ShellPreferences
{
    public WorkspaceModule SelectedWorkspace { get; init; } = WorkspaceModule.Develop;

    /// <summary>
    /// Library, Develop, Print가 함께 보는 현재 사진입니다. macOS
    /// <c>workspace.activeFrameID</c>와 같은 presentation 상태이며 catalog 선택 집합과는
    /// 별도로 저장합니다.
    /// </summary>
    public string? ActiveFrameId { get; init; }

    /// <summary>현상 화면을 다시 열어도 마지막 왼쪽 탭을 유지합니다.</summary>
    public WorkflowSidebarTab SelectedDevelopSidebarTab { get; init; } = WorkflowSidebarTab.Library;

    public bool IsSidebarVisible { get; init; } = true;

    public bool IsInspectorVisible { get; init; } = true;

    public bool IsFilmstripVisible { get; init; } = true;

    public double SidebarWidth { get; init; } = ShellLayoutMetrics.DevelopPanelDefaultWidth;

    public double InspectorWidth { get; init; } = ShellLayoutMetrics.DevelopPanelDefaultWidth;

    public double LibraryControlsWidth { get; init; } = ShellLayoutMetrics.LibraryControlsDefaultWidth;

    public double FilmstripHeight { get; init; } = ShellLayoutMetrics.FilmstripDefaultHeight;

    public double FilmstripItemScale { get; init; } = 1;

    /// <summary>
    /// 하단바가 정하는 필름스트립 차례입니다. macOS <c>workspace.filmstripSortKey</c> 자리이며
    /// 라이브러리 격자의 차례와 따로 기억합니다 — 두 화면이 서로를 흔들지 않습니다.
    /// </summary>
    public LibrarySortKey FilmstripSortKey { get; init; } = LibrarySortKey.InputOrder;

    public bool FilmstripSortAscending { get; init; } = true;

    /// <summary>하단바가 정하는 필름스트립 범위입니다. macOS 기본값과 같이 "해당 폴더" 입니다.</summary>
    public FilmstripScope FilmstripScope { get; init; } = FilmstripScope.Folder;

    public AppearanceMode Appearance { get; init; } = AppearanceMode.System;

    public ImageContentHashMode ImageContentHash { get; init; } = ImageContentHashMode.Off;

    public SettingsCategory SelectedSettingsCategory { get; init; } = SettingsCategory.General;

    /// <summary>출력 패널의 내보내기 설정입니다. macOS 처럼 앱 전체에 하나만 있습니다.</summary>
    public ExportSettings Export { get; init; } = new();

    public QuickExportSettings QuickExport { get; init; } = new();

    /// <summary>보기용 프루프 시뮬레이션입니다. 게시하는 파일에는 들어가지 않습니다.</summary>
    public SoftProofPreferences SoftProof { get; init; } = new();

    /// <summary>이름 붙여 담아 둔 내보내기 설정입니다.</summary>
    public ExportRecipeLibrary ExportRecipes { get; init; } = new();

    /// <summary>사용자가 바꾼 단축키입니다. 기본값과 같은 것은 담지 않습니다.</summary>
    public WorkflowShortcutMap Shortcuts { get; init; } = new();

    /// <summary>인화 화면의 설정입니다. macOS 처럼 앱 전체에 하나만 있습니다.</summary>
    public PrintPreferences Print { get; init; } = new();

    /// <summary>
    /// 썸네일·내보내기·스캔 원본이 놓일 자리입니다. macOS <c>DiskStorageStore</c> 가
    /// UserDefaults 에 두는 값과 같은 자리입니다.
    /// </summary>
    public DiskStorageSettings Disk { get; init; } = new();

    /// <summary>
    /// 카탈로그 백업 일정과 최근 결과입니다. macOS <c>LibraryBackupScheduleStore</c> /
    /// <c>LibraryBackupDestinationStore</c> 자리입니다.
    /// </summary>
    public LibraryBackupSettings Backup { get; init; } = new();

    /// <summary>
    /// 상주 프레임 캐시 한도입니다. macOS <c>FrameCacheResidencyStore</c> 가 UserDefaults 에
    /// 두는 값과 같은 자리입니다.
    /// </summary>
    public FrameCacheResidencySettings FrameCache { get; init; } = new();

    /// <summary>
    /// 자동 결함 도구가 미세 반점까지 찾을지의 **기본값**입니다. 프레임마다 따로 끄고 켜는
    /// 것과 별개로, 새로 여는 도구가 무엇으로 시작할지를 정합니다.
    /// </summary>
    public bool AutoDefectDetectsMicroSpecks { get; init; } = true;

    /// <summary>가이드 결함 도구의 같은 기본값입니다.</summary>
    public bool GuidedDefectDetectsMicroSpecks { get; init; } = true;

    /// <summary>
    /// macOS <c>PresentationPreferencesStore.developerMode</c>. 현상 인스펙터의 "개발자 디버그"
    /// 구역을 열어 줍니다 — 켜고 끄는 것 말고 현상 결과를 바꾸지 않습니다.
    /// </summary>
    public bool DeveloperMode { get; init; }

    /// <summary>
    /// 캔버스에서 포인터 아래 화소의 값을 읽어 보여 줄지입니다. 끄면 읽지도 않습니다 —
    /// 보이지 않는 값을 계산하느라 포인터가 무거워지지 않게.
    /// </summary>
    public bool PixelSamplerEnabled { get; init; }

    /// <summary>
    /// macOS <c>PresentationPreferencesStore.canvasBackground</c>. 현상 캔버스의 바탕색이며
    /// 캔버스 위 컨트롤의 글자색도 여기서 갈립니다.
    /// </summary>
    public CanvasBackgroundKind CanvasBackground { get; init; } = CanvasBackgroundKind.Black;

    /// <summary>
    /// macOS <c>developsImportsAutomatically</c>. 가져온 사진을 곧바로 현상할지입니다.
    /// </summary>
    public bool DevelopsImportsAutomatically { get; init; } = true;

    /// <summary>
    /// macOS <c>model.demoMode</c>. <b>다음 실행까지 남지 않습니다</b> — macOS 도
    /// <c>@Published var demoMode = false</c> 로 세션 값이며, 켜 둔 채 다시 켰을 때
    /// 진짜 스캐너 대신 시뮬레이터가 조용히 도는 일을 막습니다.
    /// </summary>
    public bool ScannerSimulatorEnabled { get; init; }

    /// <summary>
    /// macOS <c>clippingOverlayEnabled</c>. 현상 결과는 바꾸지 않고 미리보기에만 경계를 표시합니다.
    /// </summary>
    public bool ClippingOverlayEnabled { get; init; }

    /// <summary>
    /// 앱 언어입니다. 빈 문자열이면 시스템 언어를 따릅니다 — macOS 의 <c>system</c> 과 같은
    /// 뜻이며, 그때는 Windows 가 고른 것을 그대로 씁니다.
    /// </summary>
    public string Language { get; init; } = string.Empty;

    /// <summary>
    /// 스캔한 사진을 가져올 때 걸어 둘 회전입니다. 홀더에 필름을 늘 같은 방향으로 넣는
    /// 사용자가 매번 돌리지 않도록 macOS 가 두는 값입니다.
    /// </summary>
    public ImageRotation DefaultScanRotation { get; init; } = ImageRotation.Degrees0;

    /// <summary>
    /// 현상·인화 내보내기가 <b>실제로 쓸</b> 설정입니다. 출력 패널에서 따로 고른 폴더가
    /// 없으면 디스크 탭의 "내보내기 폴더"를 씁니다.
    /// </summary>
    /// <remarks>
    /// 여기를 거치지 않고 <see cref="Export"/> 를 바로 쓰면 폴더가 빈 문자열이라 파일이
    /// 어디에도 저장되지 않습니다 — 디스크 탭이 생기기 전의 상태가 정확히 그랬습니다.
    /// </remarks>
    public ExportSettings ResolvedExport => Export.FolderPath.Length != 0
        ? Export
        : Export with { FolderPath = new DiskStorageLocations(Disk).Export };

    /// <summary>빠른 내보내기의 같은 자리입니다 — 디스크 탭의 "빠른 내보내기 폴더".</summary>
    public QuickExportSettings ResolvedQuickExport => QuickExport.FolderPath.Length != 0
        ? QuickExport
        : QuickExport with { FolderPath = new DiskStorageLocations(Disk).QuickExport };

    public ShellPreferences Normalize()
    {
        return this with
        {
            Export = (Export ?? new ExportSettings()).Normalize(),
            QuickExport = (QuickExport ?? new QuickExportSettings()).Normalize(),
            SoftProof = (SoftProof ?? new SoftProofPreferences()).Normalize(),
            ExportRecipes = (ExportRecipes ?? new ExportRecipeLibrary()).Normalize(),
            Shortcuts = (Shortcuts ?? new WorkflowShortcutMap()).Normalize(),
            Print = (Print ?? new PrintPreferences()).Normalize(),
            FrameCache = (FrameCache ?? new FrameCacheResidencySettings()).Normalize(),
            Disk = (Disk ?? new DiskStorageSettings()).Normalize(),
            Backup = (Backup ?? new LibraryBackupSettings()).Normalize(),
            Language = AppLanguages.Normalize(Language),
            CanvasBackground = Enum.IsDefined(CanvasBackground)
                ? CanvasBackground
                : CanvasBackgroundKind.Black,
            DefaultScanRotation = Enum.IsDefined(DefaultScanRotation)
                ? DefaultScanRotation
                : ImageRotation.Degrees0,
            SelectedWorkspace = Enum.IsDefined(SelectedWorkspace)
                ? SelectedWorkspace
                : WorkspaceModule.Develop,
            SelectedDevelopSidebarTab = Enum.IsDefined(SelectedDevelopSidebarTab)
                ? SelectedDevelopSidebarTab
                : WorkflowSidebarTab.Library,
            ActiveFrameId = NormalizeActiveFrameId(ActiveFrameId),
            SidebarWidth = FiniteOrDefault(
                SidebarWidth,
                ShellLayoutMetrics.DevelopPanelDefaultWidth),
            InspectorWidth = FiniteOrDefault(
                InspectorWidth,
                ShellLayoutMetrics.DevelopPanelDefaultWidth),
            LibraryControlsWidth = FiniteOrDefault(
                LibraryControlsWidth,
                ShellLayoutMetrics.LibraryControlsDefaultWidth),
            FilmstripHeight = Math.Clamp(
                FiniteOrDefault(FilmstripHeight, ShellLayoutMetrics.FilmstripDefaultHeight),
                ShellLayoutMetrics.FilmstripMinimumHeight,
                ShellLayoutMetrics.FilmstripMaximumHeight),
            FilmstripItemScale = Math.Clamp(
                FiniteOrDefault(FilmstripItemScale, 1),
                ShellLayoutMetrics.FilmstripMinimumItemScale,
                ShellLayoutMetrics.FilmstripMaximumItemScale),
            Appearance = Enum.IsDefined(Appearance) ? Appearance : AppearanceMode.System,
            ImageContentHash = Enum.IsDefined(ImageContentHash)
                ? ImageContentHash
                : ImageContentHashMode.Off,
            SelectedSettingsCategory = Enum.IsDefined(SelectedSettingsCategory)
                ? SelectedSettingsCategory
                : SettingsCategory.General,
        };
    }

    private static double FiniteOrDefault(double value, double fallback) =>
        double.IsFinite(value) ? value : fallback;

    private static string? NormalizeActiveFrameId(string? value)
    {
        string? normalized = value?.Trim();
        return string.IsNullOrEmpty(normalized) || normalized.Length > 256 ? null : normalized;
    }
}
