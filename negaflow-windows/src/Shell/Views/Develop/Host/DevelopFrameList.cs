using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Host;

/// <summary>
/// 현상 작업공간의 frame 목록과 선택입니다. 미리보기·크롭·GrainMend 와 다른 이유입니다.
/// </summary>
internal sealed class DevelopFrameList
{
    private readonly DevelopWorkspaceView view;

    internal DevelopFrameList(DevelopWorkspaceView view) => this.view = view;

    internal void Hook()
    {
        view.LeftPanel.FrameSelected += OnSourceFrameSelected;
        view.LeftPanel.FramesImported += OnSourceFramesImported;
        view.LeftPanel.ScannerSetupRequested += OnSourceScannerSetupRequested;
        view.Filmstrip.FrameSelected += OnFilmstripFrameSelected;
        view.FrameSelector.SelectionChanged += OnFrameSelectionChanged;
    }

    internal void Refresh()
    {
        if (view.libraryHost is null)
        {
            return;
        }

        IReadOnlyList<LibraryFrameListItem> items =
            LibraryFrameListItems.From(view.libraryHost.Frames);
        bool hasFrames = items.Count > 0;
        view.FramePanel.Visibility = hasFrames ? Visibility.Visible : Visibility.Collapsed;
        view.NoFrameLeftPanel.Visibility = hasFrames ? Visibility.Collapsed : Visibility.Visible;
        view.NoFrameCard.Visibility = hasFrames ? Visibility.Collapsed : Visibility.Visible;
        view.DevelopInspectorContent.Visibility = hasFrames ? Visibility.Visible : Visibility.Collapsed;
        if (!hasFrames)
        {
            view.LeftPanel.SetHeaderTitle(AppResources.Get("noFrame", "Text"));
            view.FrameSelector.ItemsSource = null;
            view.Filmstrip.ShowFrames([], -1);
            view.HistogramView.Clear();
            view.LeftPanel.RebuildLibraryTree();
            view.SyncToneControls();
            view.NotifyQuickExportAvailabilityChanged();
            return;
        }

        int selectedIndex = IndexOf(items, view.libraryHost.ActiveFrameId);
        if (selectedIndex < 0)
        {
            selectedIndex = 0;
        }
        view.isSynchronizingFrameSelection = true;
        try
        {
            view.FrameSelector.ItemsSource = items;
            view.FrameSelector.SelectedIndex = selectedIndex;
            // 필름스트립과 왼쪽 목록은 같은 항목을 봅니다. 썸네일이 도착하면 둘 다 채워집니다.
            view.LeftPanel.RebuildLibraryTree();
            view.Filmstrip.ShowFrames(items, selectedIndex);
        }
        finally
        {
            view.isSynchronizingFrameSelection = false;
        }
        Activate(items[selectedIndex], selectedIndex, publishSelection: false);
        foreach (LibraryFrameListItem item in items)
        {
            if (view.thumbnails?.TryGet(item.Id) is not null)
            {
                continue;
            }
            view.thumbnails?.Request(item.Frame);
        }
    }

    /// <summary>
    /// 라이브러리에서 넘어온 frame 을 고릅니다. 목록에 없으면 아무 것도 바꾸지 않습니다 —
    /// 방금 지워진 frame 때문에 보고 있던 사진이 바뀌지 않게 합니다.
    /// </summary>
    internal void Select(string frameId)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        if (view.FrameSelector.ItemsSource is not IReadOnlyList<LibraryFrameListItem> current)
        {
            return;
        }
        for (int index = 0; index < current.Count; ++index)
        {
            if (string.Equals(current[index].Id, frameId, StringComparison.Ordinal))
            {
                view.FrameSelector.SelectedIndex = index;
                return;
            }
        }
    }

    internal void OnThumbnailReady(string frameId)
    {
        if (view.FrameSelector.ItemsSource is not IReadOnlyList<LibraryFrameListItem> current ||
            view.thumbnails?.TryGet(frameId) is not { } jpeg)
        {
            return;
        }
        foreach (LibraryFrameListItem item in current)
        {
            if (string.Equals(item.Id, frameId, StringComparison.Ordinal))
            {
                item.Thumbnail = LibraryWorkspaceView.DecodeThumbnail(jpeg);
                return;
            }
        }
    }

    internal void OnLibrarySelectionChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (view.libraryHost?.ActiveFrameId is { } activeFrameId &&
            (view.FrameSelector.ItemsSource is not IReadOnlyList<LibraryFrameListItem> items ||
             IndexOf(items, activeFrameId) < 0))
        {
            Refresh();
        }
        else
        {
            SynchronizeSharedSelection();
        }
        view.LeftPanel.RebuildLibraryTree();
        view.LeftPanel.ExportPanel.RefreshPreview();
    }

    internal void UpdateSelectedFrameText()
    {
        if (view.panel?.SelectedFrame is { } frame)
        {
            view.SelectedFrameText.Text = new LibraryFrameListItem(frame).Detail;
        }
    }

    private void OnFilmstripFrameSelected(object? sender, LibraryFrameListItem item)
    {
        _ = sender;
        Select(item.Id);
    }

    private void OnSourceFrameSelected(object? sender, string frameId)
    {
        _ = sender;
        if (view.panel is null)
        {
            return;
        }
        view.panel.Select(frameId);
        view.SynchronizeInspectorValues();
        view.RequestPreview();
        view.LeftPanel.RebuildLibraryTree();
    }

    private void OnSourceFramesImported(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        Refresh();
    }

    private void OnSourceScannerSetupRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        view.RaiseScannerSetupRequested();
    }

    private void OnFrameSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (view.isSynchronizingFrameSelection || view.panel is null ||
            view.FrameSelector.SelectedItem is not LibraryFrameListItem item)
        {
            return;
        }

        Activate(item, view.FrameSelector.SelectedIndex, publishSelection: true);
    }

    private void Activate(
        LibraryFrameListItem item,
        int selectedIndex,
        bool publishSelection)
    {
        if (view.panel is null)
        {
            return;
        }

        view.cropSession.Cancel();
        if (publishSelection)
        {
            view.libraryHost?.SetSelection([item.Id], item.Id);
        }
        view.panel.Select(item.Id);
        view.Filmstrip.SynchronizeSelection(selectedIndex);
        view.LeftPanel.SetHeaderTitle(item.DisplayName);
        UpdateSelectedFrameText();
        view.SynchronizeInspectorValues();
        view.SyncBaseControls();
        view.SyncToneControls();
        view.NotifyQuickExportAvailabilityChanged();
        view.ExportStatusText.Text = item.CanDevelop
            ? string.Empty
            : DevelopPanelState.Describe(new DevelopExportOutcome(
                DevelopExportOutcomeKind.Refused,
                null,
                DevelopWorkspaceView.RefusalFor(item.Frame),
                null));
        view.RequestPreview();
    }

    private void SynchronizeSharedSelection()
    {
        if (view.libraryHost?.ActiveFrameId is not { } activeFrameId ||
            view.FrameSelector.ItemsSource is not IReadOnlyList<LibraryFrameListItem> items)
        {
            return;
        }
        int index = IndexOf(items, activeFrameId);
        if (index < 0 || index == view.FrameSelector.SelectedIndex)
        {
            return;
        }
        view.isSynchronizingFrameSelection = true;
        try
        {
            view.FrameSelector.SelectedIndex = index;
        }
        finally
        {
            view.isSynchronizingFrameSelection = false;
        }
        Activate(items[index], index, publishSelection: false);
    }

    private static int IndexOf(IReadOnlyList<LibraryFrameListItem> items, string? frameId)
    {
        if (frameId is null)
        {
            return -1;
        }
        for (int index = 0; index < items.Count; ++index)
        {
            if (string.Equals(items[index].Id, frameId, StringComparison.Ordinal))
            {
                return index;
            }
        }
        return -1;
    }
}
