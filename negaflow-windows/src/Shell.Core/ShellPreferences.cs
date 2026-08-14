using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

public sealed record ShellPreferences
{
    public WorkspaceModule SelectedWorkspace { get; init; } = WorkspaceModule.Develop;

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

    public ShellPreferences Normalize()
    {
        return this with
        {
            Export = (Export ?? new ExportSettings()).Normalize(),
            QuickExport = (QuickExport ?? new QuickExportSettings()).Normalize(),
            SoftProof = (SoftProof ?? new SoftProofPreferences()).Normalize(),
            ExportRecipes = (ExportRecipes ?? new ExportRecipeLibrary()).Normalize(),
            SelectedWorkspace = Enum.IsDefined(SelectedWorkspace)
                ? SelectedWorkspace
                : WorkspaceModule.Develop,
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
}
