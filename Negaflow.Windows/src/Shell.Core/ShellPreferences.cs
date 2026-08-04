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

    public ShellPreferences Normalize()
    {
        return this with
        {
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
