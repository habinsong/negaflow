namespace Negaflow.Shell;

public readonly record struct WorkspaceLayout(
    double PanelMinimumWidth,
    double PanelMaximumWidth,
    double CenterMinimumWidth,
    double LibraryControlsMinimumWidth,
    double LibraryControlsMaximumWidth,
    double LibraryBrowserMinimumWidth)
{
    public double ClampPanelWidth(double value) =>
        Math.Clamp(value, PanelMinimumWidth, PanelMaximumWidth);

    public double ClampLibraryControlsWidth(double value) =>
        Math.Clamp(value, LibraryControlsMinimumWidth, LibraryControlsMaximumWidth);
}

public static class WorkspaceLayoutCalculator
{
    public static WorkspaceLayout Calculate(double availableWidth)
    {
        double width = Math.Max(ShellLayoutMetrics.MinimumWindowWidth, availableWidth);
        bool isRegular = width >= ShellLayoutMetrics.RegularWidthThreshold;

        double panelMinimum = isRegular
            ? ShellLayoutMetrics.RegularPanelMinimumWidth
            : ShellLayoutMetrics.CompactPanelMinimumWidth;
        double centerMinimum = isRegular
            ? ShellLayoutMetrics.RegularCenterMinimumWidth
            : ShellLayoutMetrics.CompactCenterMinimumWidth;
        double panelMaximum = Math.Max(
            panelMinimum,
            Math.Min(
                ShellLayoutMetrics.PanelMaximumWidth,
                (width - centerMinimum) / 2));

        double libraryControlsMinimum = isRegular
            ? ShellLayoutMetrics.RegularLibraryControlsMinimumWidth
            : ShellLayoutMetrics.CompactLibraryControlsMinimumWidth;
        double libraryBrowserMinimum = isRegular
            ? ShellLayoutMetrics.RegularLibraryBrowserMinimumWidth
            : ShellLayoutMetrics.CompactLibraryBrowserMinimumWidth;
        double libraryControlsMaximum = Math.Max(
            libraryControlsMinimum,
            Math.Min(
                ShellLayoutMetrics.PanelMaximumWidth,
                width - libraryBrowserMinimum));

        return new WorkspaceLayout(
            panelMinimum,
            panelMaximum,
            centerMinimum,
            libraryControlsMinimum,
            libraryControlsMaximum,
            libraryBrowserMinimum);
    }
}
