using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Versions;

/// <summary>
/// macOS <c>WorkflowSidebar</c> versions 탭 — <c>VirtualCopySection</c> ·
/// <c>DevelopHistorySection</c> · <c>SnapshotSection</c> 세 구획입니다.
///
/// 기록과 스냅샷은 같은 모양의 목록 둘입니다(카탈로그의 <c>developHistory</c> ·
/// <c>developSnapshots</c>). 그래서 이 화면도 같은 두 줄 — 고르개 한 줄, 단추 한 줄 — 을
/// 두 번 씁니다. 되돌린 뒤의 인스펙터·미리보기 갱신은 <see cref="VersionRestored"/> 로
/// 뷰에 맡깁니다.
/// </summary>
public sealed partial class DevelopVersionsPanel : UserControl
{
    private DevelopPanelState? panel;

    public DevelopVersionsPanel() => InitializeComponent();

    /// <summary>기록·스냅샷을 되돌린 뒤 인스펙터와 미리보기를 맞출 때 올립니다.</summary>
    public event EventHandler? VersionRestored;

    /// <summary>가상 사본을 만든 뒤 목록을 다시 그릴 때 올립니다.</summary>
    public event EventHandler? VirtualCopyCreated;

    public void Bind(DevelopPanelState hostPanel)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        panel = hostPanel;
    }

    public void Localize()
    {
        VirtualCopySectionText.Text = AppResources.Get("developVirtualCopySection", "Text");
        CreateVirtualCopyButton.Content = AppResources.Get("libraryVirtualCopy", "Content");

        HistorySectionText.Text = AppResources.Get("developHistorySection", "Text");
        HistoryLabel.Text = HistorySectionText.Text;
        RecordHistoryButton.Content = AppResources.Get("developHistoryRecord", "Content");
        ApplyHistoryButton.Content = AppResources.Get("developHistoryApply", "Content");

        SnapshotSectionText.Text = AppResources.Get("developSnapshotSection", "Text");
        SnapshotLabel.Text = SnapshotSectionText.Text;
        SaveSnapshotButton.Content = AppResources.Get("developVersionCapture", "Content");
        ApplySnapshotButton.Content = AppResources.Get("developVersionRestore", "Content");
        DeleteSnapshotButton.Content = AppResources.Get("developVersionDelete", "Content");
        Update();
    }

    public void Update()
    {
        if (HistorySelector is null)
        {
            return;
        }
        bool hasFrame = panel?.SelectedFrame is not null;
        Fill(
            HistorySelector,
            panel?.History ?? [],
            AppResources.Get("developHistoryEmpty", "Text"));
        Fill(
            SnapshotSelector,
            panel?.Versions ?? [],
            AppResources.Get("developSnapshotEmpty", "Text"));

        CreateVirtualCopyButton.IsEnabled = hasFrame;
        RecordHistoryButton.IsEnabled = hasFrame;
        SaveSnapshotButton.IsEnabled = hasFrame;
        ApplyHistoryButton.IsEnabled = SelectedId(HistorySelector) is not null;
        ApplySnapshotButton.IsEnabled = SelectedId(SnapshotSelector) is not null;
        DeleteSnapshotButton.IsEnabled = ApplySnapshotButton.IsEnabled;
    }

    /// <summary>
    /// macOS <c>ensureSelection()</c> — 목록이 비면 "없음" 한 줄만 두고 고르개를 잠급니다.
    /// 목록이 있으면 macOS 처럼 **마지막 항목**을 고른 채로 둡니다.
    /// </summary>
    private static void Fill(
        ComboBox selector,
        IReadOnlyList<LibraryVersionSnapshot> entries,
        string emptyLabel)
    {
        string? previous = SelectedId(selector);
        if (entries.Count == 0)
        {
            selector.ItemsSource = new[] { new VersionEntryRow(null, emptyLabel) };
            selector.SelectedIndex = 0;
            selector.IsEnabled = false;
            return;
        }
        VersionEntryRow[] rows =
            [.. entries.Select(entry => new VersionEntryRow(entry.Id, entry.Name))];
        selector.ItemsSource = rows;
        selector.IsEnabled = true;
        int restored = previous is null
            ? -1
            : Array.FindIndex(rows, row => string.Equals(row.Id, previous, StringComparison.Ordinal));
        selector.SelectedIndex = restored >= 0 ? restored : rows.Length - 1;
    }

    private static string? SelectedId(ComboBox selector) =>
        selector.SelectedItem is VersionEntryRow { Id: { Length: > 0 } id } ? id : null;

    private void OnCreateVirtualCopyClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || !panel.CreateVirtualCopy())
        {
            return;
        }
        _ = panel.Save();
        VirtualCopyCreated?.Invoke(this, EventArgs.Empty);
        Update();
    }

    private void OnRecordHistoryClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null ||
            panel.RecordHistory(AppResources.Get("developHistoryNameFormat", "Value")) !=
                LibraryFrameError.None)
        {
            return;
        }
        _ = panel.Save();
        Update();
    }

    private void OnApplyHistoryClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || SelectedId(HistorySelector) is not { } entryId ||
            panel.ApplyHistory(entryId) != LibraryFrameError.None)
        {
            return;
        }
        _ = panel.Save();
        VersionRestored?.Invoke(this, EventArgs.Empty);
        Update();
    }

    private void OnSaveSnapshotClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null)
        {
            return;
        }
        // macOS 도 이름을 순번으로 붙입니다 — 이름 칸을 따로 두지 않습니다.
        string name = string.Format(
            System.Globalization.CultureInfo.CurrentCulture,
            AppResources.Get("developSnapshotNameFormat", "Value"),
            panel.Versions.Count + 1);
        if (panel.CaptureVersion(name) != LibraryFrameError.None)
        {
            return;
        }
        _ = panel.Save();
        Update();
    }

    private void OnApplySnapshotClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || SelectedId(SnapshotSelector) is not { } versionId ||
            panel.RestoreVersion(versionId) != LibraryFrameError.None)
        {
            return;
        }
        _ = panel.Save();
        VersionRestored?.Invoke(this, EventArgs.Empty);
        Update();
    }

    private void OnDeleteSnapshotClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || SelectedId(SnapshotSelector) is not { } versionId ||
            panel.DeleteVersion(versionId) != LibraryFrameError.None)
        {
            return;
        }
        _ = panel.Save();
        Update();
    }
}

/// <summary>고르개 한 줄입니다. 목록이 비었을 때는 <see cref="Id"/> 가 null 입니다.</summary>
public sealed record VersionEntryRow(string? Id, string Label);
