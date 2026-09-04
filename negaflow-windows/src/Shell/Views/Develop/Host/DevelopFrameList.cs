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
            view.inspectorHeader.Clear();
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
        // **기준이 목록에 없으면 가장 최근 사진입니다 — 첫 장이 아닙니다.**
        // macOS `selectMostRecentAvailableFrameIfNeeded()` 자리입니다. 스캔·가져오기 직후에는
        // 게시와 선택이 서로 다른 차례로 UI 스레드에 올라오므로 기준이 잠깐 목록 밖에
        // 있습니다. 그때 첫 장으로 접으면 방금 넣은 사진 대신 맨 앞 사진이 열립니다.
        bool activeFrameMissing = selectedIndex < 0;
        if (activeFrameMissing)
        {
            selectedIndex = FilmstripScopes.MostRecentIndex(items);
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
        // 기준을 새로 고른 것은 **선택을 옮긴 것**입니다. macOS 도 `selectedFrameID` 에
        // 그대로 적습니다 — 여기서 적지 않으면 라이브러리·인화뷰가 없는 사진을 계속
        // 가리켜 세 화면이 서로 다른 사진을 보여 줍니다.
        Activate(items[selectedIndex], selectedIndex, publishSelection: activeFrameMissing);
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
        view.LeftPanel.SynchronizeFilesSelection();
        view.LeftPanel.ExportPanel.RefreshPreview();
    }

    /// <summary>
    /// 위 막대 가운데 줄입니다. 현상할 수 있으면 원본 경로를, 아니면 <b>왜 안 되는지</b>를
    /// 지역화된 문구로 냅니다 — 목록에 있는데 내보내기가 조용히 아무 일도 하지 않는 것보다
    /// 낫습니다.
    /// </summary>
    internal void UpdateSelectedFrameText()
    {
        if (view.panel?.SelectedFrame is not { } frame)
        {
            return;
        }

        view.SelectedFrameText.Text = frame.CanDevelop
            ? new LibraryFrameListItem(frame).Detail
            : DevelopExportOutcomeText.For(new DevelopExportOutcome(
                DevelopExportOutcomeKind.Refused,
                null,
                DevelopWorkspaceView.RefusalFor(frame),
                null));
    }

    /// <summary>
    /// 하단 필름스트립에서 사진을 눌렀습니다. <b>Shift·Ctrl 풀이는 라이브러리가 합니다.</b>
    /// </summary>
    /// <remarks>
    /// macOS <c>selectFrame(_:orderedFrameIDs:modifiers:)</c> 자리이며 인화뷰도 같은 길을
    /// 씁니다(<c>PrintSourceController.HandleFilmstripSelected</c>).
    ///
    /// 현상뷰만 자기 계산을 따로 들고 있었습니다 — 누른 순간 <b>컨트롤이 잡고 있는 선택</b>
    /// 을 읽어 여러 장이면 그대로, 아니면 한 장으로 발행했습니다. 그런데 <c>ItemClick</c> 은
    /// <c>SelectionChanged</c> 보다 **먼저** 오므로 그때 읽는 목록에는 방금 Ctrl 로 더한
    /// 사진이 아직 없습니다. 그래서 언제나 "여러 장이 아님" 으로 판정돼 한 장으로 접혔고,
    /// 이어지는 <c>Activate</c> 가 그 한 장짜리 선택을 스트립에 되써서 Shift·Ctrl 이
    /// 아예 듣지 않았습니다. 고른 장수를 세는 내보내기·빠른 내보내기도 늘 한 장이었습니다.
    /// </remarks>
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
        // 차례는 **스트립이 보여 주는 차례**입니다. Shift 로 이어 고를 때 그 사이가 곧
        // 화면에 보이는 사이여야 합니다.
        view.libraryHost?.SelectFrame(
            item.Id,
            [.. items.Select(candidate => candidate.Id)],
            LibraryModifierKeys.Current());
        // Ctrl 로 방금 누른 사진을 뺐다면 이제 열려야 할 사진은 다른 것입니다. 라이브러리가
        // 정한 활성 사진을 따릅니다 — 그것이 목록에 없을 때만 누른 사진으로 물러납니다.
        int activeIndex = IndexOf(items, view.libraryHost?.ActiveFrameId);
        if (activeIndex < 0)
        {
            activeIndex = index;
        }
        LibraryFrameListItem active = items[activeIndex];
        // FrameSelector.SelectedIndex 만 바꾸면, 이미 그 칸이거나 SelectionChanged 가
        // 빠른 클릭을 건너뛸 때 Activate 가 안 불립니다. 스트립 클릭은 항상 이 장을 엽니다.
        view.isSynchronizingFrameSelection = true;
        try
        {
            if (view.FrameSelector.SelectedIndex != activeIndex)
            {
                view.FrameSelector.SelectedIndex = activeIndex;
            }
        }
        finally
        {
            view.isSynchronizingFrameSelection = false;
        }
        // 선택은 위에서 이미 발행했습니다. 여기서 다시 발행하면 그 풀이를 덮어씁니다.
        Activate(active, activeIndex, publishSelection: false);
    }

    /// <summary>
    /// 좌측탭 목록에서 사진을 골랐습니다. macOS 는 이 목록의 선택이 곧 <b>공유 선택</b>이라
    /// 필름스트립·파일 탭 강조·인화 대상이 함께 움직입니다. 예전에는 여기서 캔버스만 바꿔
    /// 놓아 목록의 파란 강조와 하단 필름스트립이 옛 사진에 남았습니다.
    /// </summary>
    private void OnSourceFrameSelected(object? sender, Negaflow.Shell.Views.Library.Sources.LibraryFrameInvocation invocation)
    {
        _ = sender;
        ArgumentNullException.ThrowIfNull(invocation);
        if (view.panel is null)
        {
            return;
        }
        // Shift · Ctrl 은 라이브러리가 풉니다 — 필름스트립·격자·인화뷰와 같은 한 규칙입니다.
        view.libraryHost?.SelectFrame(
            invocation.FrameId,
            invocation.OrderedFrameIds,
            invocation.Modifiers);
        // 열 사진은 라이브러리가 정한 활성 사진입니다. Ctrl 로 누른 사진을 빼면 다른 사진이
        // 활성이 됩니다.
        string frameId = view.libraryHost?.ActiveFrameId ?? invocation.FrameId;
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
        // 가져오기는 카탈로그의 프레임 집합을 바꿉니다. 라이브러리·인화 화면도 맞춰야
        // 합니다 — 앞 판은 현상뷰만 알고 있어서, 라이브러리로 넘어가면 방금 가져온 폴더가
        // 목록에 없었습니다.
        view.RaiseLibraryFramesChanged();
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
            // 글쇠 없이 이 사진 하나를 여는 길입니다(좌측 목록·복구·단축키). 필름스트립
            // 클릭은 여기로 오지 않습니다 — Shift·Ctrl 풀이가 필요해서
            // `OnFilmstripFrameSelected` 가 라이브러리의 `SelectFrame` 으로 먼저 발행합니다.
            view.libraryHost?.SetSelection([item.Id], item.Id);
        }
        if (!view.panel.Select(item.Id))
        {
            return;
        }
        _ = selectedIndex;
        // 여러 장을 고른 채로 두려면 **번호 하나가 아니라 목록**으로 맞춰야 합니다.
        // `SynchronizeSelection(int)` 는 `SelectedIndex` 를 넣어 선택을 하나로 접습니다.
        // **프리뷰도 고를 수 있어야 합니다.** macOS `actionableFrame` 은 고른 프레임을
        // 그대로 돌려주고 프리뷰를 빼지 않습니다 - 평판 프레임 사각형을 그리는 자리가 바로
        // 현상 캔버스 위의 프리뷰이기 때문입니다. 여기서 걸러 내면 프리뷰를 눌렀을 때
        // 고른 것이 하나도 없는 목록이 되어, 스트립이 선택을 잃습니다.
        string[] selectedIds = view.libraryHost?.SelectedFrames
            .Select(frame => frame.Id)
            .ToArray() ?? [];
        view.Filmstrip.SynchronizeSelection(
            selectedIds.Length == 0 ? [item.Id] : selectedIds,
            item.Id);
        view.LeftPanel.SetHeaderTitle(item.DisplayName);
        // 머리줄 오른쪽 한 줄입니다. 스캐너 TIFF 는 타깃·공정을, 가져온 파일은 그 파일에
        // 실제로 적힌 EXIF 를 냅니다 — macOS `DevelopInspectorHeaderSummary` 와 같습니다.
        view.inspectorHeader.Update(item.Frame);
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
            : DevelopExportOutcomeText.For(new DevelopExportOutcome(
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
