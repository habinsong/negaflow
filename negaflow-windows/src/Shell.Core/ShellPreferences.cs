using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Print;
using Negaflow.Shell.Shortcuts;

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
    /// 자동 결함 도구가 미세 반점까지 찾을지의 **기본값**입니다. 프레임마다 따로 끄고 켜는
    /// 것과 별개로, 새로 여는 도구가 무엇으로 시작할지를 정합니다.
    /// </summary>
    public bool AutoDefectDetectsMicroSpecks { get; init; } = true;

    /// <summary>가이드 결함 도구의 같은 기본값입니다.</summary>
    public bool GuidedDefectDetectsMicroSpecks { get; init; } = true;

    /// <summary>
    /// 캔버스에서 포인터 아래 화소의 값을 읽어 보여 줄지입니다. 끄면 읽지도 않습니다 —
    /// 보이지 않는 값을 계산하느라 포인터가 무거워지지 않게.
    /// </summary>
    public bool PixelSamplerEnabled { get; init; }

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
            Language = AppLanguages.Normalize(Language),
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
