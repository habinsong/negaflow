using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Versions;

/// <summary>
/// 지금 recipe 를 이름 붙여 담고 되돌리는 패널입니다. 인스펙터·미리보기 갱신은
/// <see cref="VersionRestored"/> 로 뷰에 맡깁니다.
/// </summary>
public sealed partial class DevelopVersionsPanel : UserControl
{
    private DevelopPanelState? panel;

    public DevelopVersionsPanel() => InitializeComponent();

    /// <summary>버전을 되돌린 뒤 인스펙터와 미리보기를 맞출 때 올립니다.</summary>
    public event EventHandler? VersionRestored;

    public void Bind(DevelopPanelState hostPanel)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        panel = hostPanel;
    }

    public void Localize()
    {
        CaptureVersionButton.Content = AppResources.Get("developVersionCapture", "Content");
        VersionsEmptyText.Text = AppResources.Get("developVersionsEmpty", "Text");
        string versionName = AppResources.Get("developVersionNamePlaceholder", "Text");
        VersionNameBox.PlaceholderText = versionName;
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(VersionNameBox, versionName);
        Update();
    }

    public void Update()
    {
        if (VersionsList is null)
        {
            return;
        }
        IReadOnlyList<VersionRow> rows = VersionListProjection.Rows(
            panel?.Versions ?? [],
            AppResources.Get("developVersionRestore", "Content"),
            AppResources.Get("developVersionDelete", "Content"));
        VersionsList.ItemsSource = rows;
        VersionsEmptyText.Visibility = rows.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        CaptureVersionButton.IsEnabled =
            panel?.SelectedFrame is not null && !string.IsNullOrWhiteSpace(VersionNameBox.Text);
    }

    private void OnVersionNameChanged(object sender, TextChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        CaptureVersionButton.IsEnabled =
            panel?.SelectedFrame is not null && !string.IsNullOrWhiteSpace(VersionNameBox.Text);
    }

    private void OnCaptureVersionClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || panel.CaptureVersion(VersionNameBox.Text) != LibraryFrameError.None)
        {
            return;
        }
        // 담고 나면 이름 칸을 비웁니다 — 같은 이름으로 두 번 담는 실수를 줄입니다.
        VersionNameBox.Text = string.Empty;
        _ = panel.Save();
        Update();
    }

    private void OnRestoreVersionClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (panel is null || sender is not Button { Tag: string versionId })
        {
            return;
        }
        if (panel.RestoreVersion(versionId) != LibraryFrameError.None)
        {
            return;
        }
        _ = panel.Save();
        VersionRestored?.Invoke(this, EventArgs.Empty);
    }

    private void OnDeleteVersionClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (panel is null || sender is not Button { Tag: string versionId })
        {
            return;
        }
        if (panel.DeleteVersion(versionId) != LibraryFrameError.None)
        {
            return;
        }
        _ = panel.Save();
        Update();
    }
}
