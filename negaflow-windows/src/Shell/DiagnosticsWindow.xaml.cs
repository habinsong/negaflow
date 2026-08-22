using Microsoft.UI.Xaml;
using Negaflow.Shell.Diagnostics;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell;

/// <summary>
/// 작업 옵션 · 진단 창입니다. macOS 는 팝오버이고 Windows 는 창이지만, 안에 든 것과 차례는
/// 같습니다(<c>DiagnosticsReportView</c>).
/// </summary>
public sealed partial class DiagnosticsWindow : Window
{
    private readonly PresentationSettingsStore settingsStore;

    public DiagnosticsWindow(
        PresentationSettingsStore settingsStore,
        Func<Task<DiagnosticsReport>> reportSource)
    {
        ArgumentNullException.ThrowIfNull(settingsStore);
        ArgumentNullException.ThrowIfNull(reportSource);
        this.settingsStore = settingsStore;
        InitializeComponent();
        WindowIcon.Apply(AppWindow);
        Title = AppResources.Get("commandDiagnostics", "Text");
        ReportView.ReportSource = reportSource;
        // macOS 팝오버 폭 500 + 좌우 여백 20. 높이는 네 구역이 스크롤 없이 들어가는 값입니다.
        AppWindow.Resize(WindowDpiSizing.LogicalToPhysical(this, 540, 640));
        ApplyAppearance(settingsStore.Current.Appearance);
        settingsStore.Changed += OnSettingsChanged;
        Closed += OnClosed;
        // 창을 열면 곧바로 한 번 만듭니다. macOS 도 여는 순간 runDiagnostics 를 부릅니다.
        _ = ReportView.RefreshAsync();
    }

    private void OnSettingsChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        ApplyAppearance(preferences.Appearance);
    }

    private void ApplyAppearance(AppearanceMode appearance) =>
        WindowRoot.RequestedTheme = appearance switch
        {
            AppearanceMode.Dark => ElementTheme.Dark,
            AppearanceMode.Light => ElementTheme.Light,
            _ => ElementTheme.Default,
        };

    private void OnClosed(object sender, WindowEventArgs args)
    {
        _ = sender;
        _ = args;
        settingsStore.Changed -= OnSettingsChanged;
    }
}
