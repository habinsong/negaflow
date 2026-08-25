using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Library.Browser;

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

        // 하단바가 정한 범위와 차례를 그대로 씁니다. macOS
        // `activeDevelopInteractionScopeFrameIDs` 와 같은 계산입니다 — 범위로 좁힌 뒤
        // 정렬하며, 기준은 지금 보고 있는 사진입니다.
        IReadOnlyList<LibraryFrameListItem> items =
            FilmstripPresentation.Project(view.libraryHost, view.workspaceState);
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
            view.LeftPanel.RebuildFilesTree();
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
            // "파일" 탭도 같은 사진들을 냅니다. 여기서 짓지 않으면 카탈로그가 붙기 <b>전에</b>
            // 한 번 지어진 빈 목록이 그대로 남습니다 — 앱을 켜자마자 현상뷰의 파일 탭이 비어
            // 있던 원인이며, 다른 세로탭을 눌렀다 돌아와야 그제서야 채워졌습니다.
            view.LeftPanel.RebuildFilesTree();
            view.Filmstrip.ShowFrames(items, selectedIndex);
        }
        finally
        {
            view.isSynchronizingFrameSelection = false;
        }
        Activate(items[selectedIndex], selectedIndex, publishSelection: false);
        // 예전에는 캐시에 있는 프레임을 **건너뛰기만** 했습니다. `Request` 는 이미 들고 있는
        // 프레임에 아무 일도 하지 않으므로 `ThumbnailReady` 가 오지 않고, 방금 새로 만든
        // 항목의 `Thumbnail` 은 영원히 null 로 남습니다 — 폴더 일괄 적용이 모든 프레임을
        // 캐시에 넣은 직후 필름스트립이 통째로 비던 원인이 이것입니다.
        _ = LibraryThumbnailBinder.Hydrate(view.thumbnails, items, "develop");
        // 고른 사진이 평판 프리뷰면 그 위에 프레임 사각형이 서야 합니다.
        view.SyncFlatbedOverlay();
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
        if (view.thumbnails?.TryGet(frameId) is not { } jpeg)
        {
            return;
        }
        Microsoft.UI.Xaml.Media.ImageSource? decoded =
            LibraryWorkspaceView.DecodeThumbnail(jpeg);
        if (view.FrameSelector.ItemsSource is IReadOnlyList<LibraryFrameListItem> current)
        {
            foreach (LibraryFrameListItem item in current)
            {
                if (string.Equals(item.Id, frameId, StringComparison.Ordinal))
                {
                    item.Thumbnail = decoded;
                    break;
                }
            }
        }
        // 하단 스트립은 목록을 다시 지어도 **예전 항목 객체**를 붙들고 있습니다. 위에서
        // 새 객체만 갱신하면 스트립은 비어 있는 채로 남습니다.
        view.Filmstrip.ApplyThumbnail(frameId, decoded);
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
        // 목록을 통째로 다시 짓지 않고 강조만 옮깁니다 — 인화뷰와 같은 처리입니다.
        view.LeftPanel.SynchronizeFilesSelection(view.libraryHost?.ActiveFrameId);
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
        if (view.FrameSelector.ItemsSource is not IReadOnlyList<LibraryFrameListItem> items)
        {
            Select(item.Id);
            return;
        }
        int index = IndexOf(items, item.Id);
        if (index < 0)
        {
            return;
        }
        // FrameSelector.SelectedIndex 만 바꾸면, 이미 그 칸이거나 SelectionChanged 가
        // 빠른 클릭을 건너뛸 때 Activate 가 안 불립니다. 스트립 클릭은 항상 이 장을 엽니다.
        view.isSynchronizingFrameSelection = true;
        try
        {
            if (view.FrameSelector.SelectedIndex != index)
            {
                view.FrameSelector.SelectedIndex = index;
            }
        }
        finally
        {
            view.isSynchronizingFrameSelection = false;
        }
        Activate(item, index, publishSelection: true);
    }

    /// <summary>
    /// 좌측탭 목록에서 사진을 골랐습니다. macOS 는 이 목록의 선택이 곧 <b>공유 선택</b>이라
    /// 필름스트립·파일 탭 강조·인화 대상이 함께 움직입니다. 예전에는 여기서 캔버스만 바꿔
    /// 놓아 목록의 파란 강조와 하단 필름스트립이 옛 사진에 남았습니다.
    /// </summary>
    private void OnSourceFrameSelected(object? sender, string frameId)
    {
        _ = sender;
        if (view.panel is null)
        {
            return;
        }
        if (view.libraryHost is { } host)
        {
            host.SetSelection([frameId], frameId);
        }
        // 공유 선택이 이미 그 사진이었다면 알림이 나지 않습니다. 그때만 직접 옮깁니다.
        if (!string.Equals(view.panel.SelectedFrame?.Id, frameId, StringComparison.Ordinal))
        {
            view.panel.Select(frameId);
            view.SynchronizeInspectorValues();
            view.RequestPreview();
            view.LeftPanel.RebuildLibraryTree();
        }
        if (InfraredCleanStatusText.For(view.panel.LastInfraredClean) is { Length: > 0 } infrared)
        {
            view.ExportStatusText.Text = infrared;
        }
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

    /// <summary>
    /// macOS 는 스포이드를 <c>basePickerFrameID == frame.id</c> 로, 비교 모드를
    /// <c>frame.showDeveloped</c> 로 **프레임마다** 답니다. 이쪽은 작업공간에 한 벌뿐이라
    /// 프레임을 옮길 때 새 프레임 기준으로 다시 걸어 줘야 합니다.
    ///
    /// 안 걸면 <c>PreviewCoordinator.UninvertedSource</c> 가 켜진 채 남아
    /// <c>FilmPolarity = Positive</c> 로 현상 요청이 나갑니다 — 한 프레임에서 `원본` 을
    /// 켜거나 베이스 스포이드를 켠 뒤로는 **여는 사진마다** 반전 전 네거티브(주황 베이스에
    /// 반전 전 그레인)가 나와 "전부 노이즈투성이에 베이스가 이상하다" 로 보입니다.
    /// </summary>
    private void RebindPerFrameCanvasTools()
    {
        view.BaseCard.CancelBasePicker();
        if (view.previewCoordinator is not null)
        {
            view.previewCoordinator.UninvertedSource =
                view.BaseCard.IsBasePickerActive ||
                view.panel?.Compare.ActiveMode == CanvasCompareMode.Raw;
        }
        view.PreviewCanvas.RefreshCompare();
    }

    /// <summary>
    /// 이 클릭으로 발행할 선택입니다. 스트립이 여러 장을 잡고 있고 그 안에 이 사진이 있으면
    /// 그 목록 그대로, 아니면 이 사진 하나입니다.
    /// </summary>
    private IReadOnlyList<string> SelectionIdsFor(LibraryFrameListItem item)
    {
        IReadOnlyList<string> shown = view.Filmstrip.SelectedFrameIds;
        return shown.Count > 1 && shown.Contains(item.Id, StringComparer.Ordinal)
            ? shown
            : [item.Id];
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
            // **스트립이 실제로 잡은 것을 그대로 발행합니다.** 앞 판은 언제나 한 장짜리
            // 목록을 발행해서, Ctrl 로 여러 장을 골라도 매번 한 장으로 접혔습니다 -
            // 그래서 현상뷰에서는 배치 내보내기를 시작할 수가 없었습니다(인화뷰는 다중
            // 목록을 발행해 되고 있었습니다).
            view.libraryHost?.SetSelection(SelectionIdsFor(item), item.Id);
        }
        if (!view.panel.Select(item.Id))
        {
            return;
        }
        _ = selectedIndex;
        // 여러 장을 고른 채로 두려면 **번호 하나가 아니라 목록**으로 맞춰야 합니다.
        // `SynchronizeSelection(int)` 는 `SelectedIndex` 를 넣어 선택을 하나로 접습니다.
        view.Filmstrip.SynchronizeSelection(
            view.libraryHost?.SelectedFrames
                .Where(frame => !frame.IsPreviewScan)
                .Select(frame => frame.Id)
                .ToArray() ?? [item.Id],
            item.Id);
        view.LeftPanel.SetHeaderTitle(item.DisplayName);
        UpdateSelectedFrameText();
        RebindPerFrameCanvasTools();
        // 좌측탭의 프로세스·타깃·필름 프로파일·룩은 선택된 프레임을 따라갑니다.
        view.LeftPanel.SynchronizeDevelopDefaults();
        // 인스펙터 동기화보다 먼저 렌더를 겁니다. 안 그러면 전환이 한 박자 늦습니다.
        view.RequestPreviewNow();
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
        // IR 결함 제거는 프레임을 고르는 것만으로 돕니다(macOS `runInfraredCleanIfNeeded`).
        // 할 말이 있을 때만 덮어씁니다 — 현상 불가 안내를 지우면 안 됩니다.
        if (InfraredCleanStatusText.For(view.panel.LastInfraredClean) is { Length: > 0 } infrared)
        {
            view.ExportStatusText.Text = infrared;
        }
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
