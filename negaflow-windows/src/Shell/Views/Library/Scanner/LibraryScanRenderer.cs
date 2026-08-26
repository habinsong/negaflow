using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Library.Scanner;

/// <summary>세션 상태를 스캔 컨트롤에 옮깁니다. 실행·이름표와 다른 이유입니다.</summary>
internal sealed class LibraryScanRenderer
{
    private readonly LibraryScanPanel view;

    internal LibraryScanRenderer(LibraryScanPanel view) => this.view = view;

    /// <summary>
    /// 세션 상태를 컨트롤에 옮깁니다. macOS 와 같은 세 갈래(플러그인 없음 · 승인 필요 ·
    /// 연결 대기)를 그대로 냅니다.
    /// </summary>
    internal void Render()
    {
        if (view.ScanSectionCard is null)
        {
            return;
        }
        bool wanted = view.Wanted;
        ScanSessionState state = view.scanSession?.State ?? ScanSessionState.NoPlugin;
        view.ScanSectionHeader.Visibility = wanted ? Visibility.Visible : Visibility.Collapsed;
        view.ScanSectionCard.Visibility = view.ScanSectionHeader.Visibility;
        if (!wanted || view.scanSession is null)
        {
            return;
        }

        bool ready = state is ScanSessionState.Ready or ScanSessionState.Scanning;
        view.ScanControls.Visibility = ready ? Visibility.Visible : Visibility.Collapsed;
        view.ScanApprovePluginButton.Visibility = state == ScanSessionState.NeedsApproval
            ? Visibility.Visible
            : Visibility.Collapsed;
        // macOS 는 [스캐너 찾기] 와 시뮬레이터 스위치를 `unavailableState` 에만 둡니다.
        // 쓸 수 있는 상태에서 이 둘을 계속 내면 macOS 에 없는 화면이 됩니다.
        Visibility unavailable = ready ? Visibility.Collapsed : Visibility.Visible;
        view.ScanDetectButton.Visibility = unavailable;
        view.ScanDetectButton.IsEnabled = !view.scanSession.IsDetecting;
        view.ScanSimulatorRow.Visibility = unavailable;
        view.ScanStateText.Text = state switch
        {
            ScanSessionState.NoPlugin => AppResources.Get("scanPluginMissingTitle", "Text") + "\n" +
                AppResources.Get("scanPluginMissingBody", "Text"),
            ScanSessionState.NeedsApproval => AppResources.Get("scanPluginApprovalTitle", "Text"),
            ScanSessionState.Searching => AppResources.Get("scanSearching", "Text"),
            ScanSessionState.NoDevice => AppResources.Get("scanWaitingStatus", "Text"),
            _ => string.Empty,
        };
        view.isSynchronizingScan = true;
        try
        {
            view.ScanSimulatorToggle.IsOn = view.scanSession.SimulatorEnabled;
        }
        finally
        {
            view.isSynchronizingScan = false;
        }
        view.ScanStateText.Visibility = view.ScanStateText.Text.Length == 0
            ? Visibility.Collapsed
            : Visibility.Visible;
        if (!ready)
        {
            return;
        }

        view.isSynchronizingScan = true;
        try
        {
            FillTagged(
                view.ScanDeviceSelector,
                [.. view.scanSession.Devices.Select(device =>
                    ((object)device.DisplayName, (object)device.Id))],
                view.scanSession.SelectedDevice?.Id);
            FillTagged(
                view.ScanFilmSelector,
                [.. FilmTypes.Select(film =>
                    ((object)FilmTypeNameConverter.Name(film), (object)film))],
                view.scanSession.Options.FilmType);
            FillTagged(
                view.ScanResolutionSelector,
                [.. view.scanSession.Resolutions.Select(dpi =>
                    ((object)string.Create(CultureInfo.CurrentCulture, $"{dpi} dpi"), (object)dpi))],
                view.scanSession.Options.ResolutionDpi);
            FillTagged(
                view.ScanColorModeSelector,
                [.. view.scanSession.ColorModes.Select(mode =>
                    ((object)ColorModeLabel(mode), (object)mode))],
                view.scanSession.Options.ColorMode);
            int channels = string.Equals(
                view.scanSession.Options.ColorMode,
                ScanSessionController.ColorModeGray,
                StringComparison.Ordinal) ? 1 : 3;
            FillTagged(
                view.ScanBitDepthSelector,
                [.. view.scanSession.BitDepths.Select(depth => ((object)string.Create(
                    CultureInfo.CurrentCulture,
                    $"{depth}-bit/ch ({depth * channels}-bit)"), (object)depth))],
                view.scanSession.Options.BitDepth);
            if (view.ScanFolderNameBox.Text != view.scanSession.Options.FolderName)
            {
                view.ScanFolderNameBox.Text = view.scanSession.Options.FolderName;
            }
            view.ScanFrameCountBox.Value = view.scanSession.Options.BatchCount;
            FillTagged(
                view.ScanFrameFormatSelector,
                [.. view.scanSession.AvailableFrameFormats.Select(format =>
                    ((object)FilmFrameFormats.DisplayName(format), (object)format))],
                view.scanSession.Options.FrameFormat);
            view.ScanDetectionAutomaticButton.IsChecked =
                view.scanSession.Options.FrameDetectionMode == FlatbedFrameDetectionMode.Automatic;
            view.ScanDetectionManualButton.IsChecked =
                view.scanSession.Options.FrameDetectionMode == FlatbedFrameDetectionMode.Manual;
            view.ScanInfraredToggle.IsOn = view.scanSession.Options.Infrared;
        }
        finally
        {
            view.isSynchronizingScan = false;
        }

        bool flatbed = view.scanSession.UsesFlatbedRegionWorkflow;
        view.ScanFrameFormatRow.Visibility = view.scanSession.AvailableFrameFormats.Count > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        view.ScanDetectionModeRow.Visibility = flatbed ? Visibility.Visible : Visibility.Collapsed;
        view.ScanRegionsRow.Visibility = view.ScanDetectionModeRow.Visibility;
        // 평판에서는 판 위에 놓인 프레임 수가 곧 스캔 수이므로 사진 수 줄이 없습니다.
        view.ScanFrameCountRow.Visibility = flatbed ? Visibility.Collapsed : Visibility.Visible;
        view.ScanRegionsLabel.Text = AppResources.FormatInteger(
            "scanFlatbedFramesFormat",
            "Text",
            view.scanSession.Regions.Count);
        bool hasSelectedRegion = view.scanSession.SelectedRegionId is not null;
        view.ScanCopyFrameButton.IsEnabled = hasSelectedRegion;
        view.ScanRemoveFrameButton.IsEnabled = hasSelectedRegion;
        view.ScanPasteFrameButton.IsEnabled = view.scanSession.CopiedRegion is not null;
        // 프리뷰 픽셀이 없으면 찾을 근거가 없습니다.
        view.ScanRefreshFramesButton.IsEnabled = !view.flatbedPreview.IsEmpty ||
            view.scanSession.Options.FrameDetectionMode == FlatbedFrameDetectionMode.Manual;

        bool hasDepths = view.scanSession.BitDepths.Count > 0;
        view.ScanBitDepthRow.Visibility = hasDepths ? Visibility.Visible : Visibility.Collapsed;
        view.ScanBitDepthUnavailableText.Visibility = hasDepths
            ? Visibility.Collapsed
            : Visibility.Visible;
        // macOS `if model.capabilities?.supportsInfrared == true` — IR 채널을 실제로 내놓는
        // 기기에서만 줄이 섭니다(OpticFilm "i" 계열).
        view.ScanInfraredRow.Visibility = view.scanSession.Capabilities?.SupportsInfrared == true
            ? Visibility.Visible
            : Visibility.Collapsed;
        view.ScanInfraredToggle.IsEnabled = view.scanSession.CanUseInfrared;
        view.ScanInfraredLabel.Opacity = view.scanSession.CanUseInfrared ? 1.0 : 0.5;
        view.ScanPreviewButton.Visibility = view.scanSession.Capabilities?.SupportsPreview == true
            ? Visibility.Visible
            : Visibility.Collapsed;
        view.ScanPreviewButton.IsEnabled = view.scanSession.CanPreview;
        view.ScanStartButton.IsEnabled = view.scanSession.CanScan;
        view.ScanRescanButton.IsEnabled = !view.scanSession.IsDetecting && !view.scanSession.IsScanning;
        // macOS 는 스캔 중이면 스캔 단추 자리를 취소로 바꿉니다.
        view.ScanStartButton.Visibility = view.scanSession.IsScanning
            ? Visibility.Collapsed
            : Visibility.Visible;
        // macOS `.disabled(model.isScanning)` 은 옵션 Section 에만 걸립니다. 단추 줄까지 잠그면
        // 스캔을 멈출 방법이 없어집니다.
        view.ScanControls.IsHitTestVisible = true;
        foreach (Microsoft.UI.Xaml.UIElement child in view.ScanControls.Children)
        {
            if (ReferenceEquals(child, view.ScanActionRow))
            {
                continue;
            }
            child.IsHitTestVisible = !view.scanSession.IsScanning;
            child.Opacity = view.scanSession.IsScanning ? 0.5 : 1.0;
        }
        LibraryScanCopy.SetButtonText(view.ScanStartButton, ScanButtonTitle(view));
        view.ScanFrameCountLabel.Text = AppResources.FormatInteger(
            "scanFramesFormat",
            "Text",
            view.scanSession.Options.BatchCount);
        // 찾은 프레임을 눈으로 볼 자리는 라이브러리 쪽 오버레이입니다. 개수만 적고
        // 그림을 그리지 않으면 "선택: 12" 가 어디를 가리키는지 알 수 없습니다.
        view.RaiseFlatbedPreviewChanged();
    }

    /// <summary>
    /// macOS <c>scanButtonTitle</c> 그대로입니다 — 평판이면 판 위의 프레임 수, 아니면 배치가
    /// 여럿일 때 그 수, 둘 다 아니면 손대는 사진이 없으면 "스캔" 있으면 "다음 스캔" 입니다.
    /// </summary>
    private static string ScanButtonTitle(LibraryScanPanel view)
    {
        if (view.scanSession is not { } session)
        {
            return AppResources.Get("scanStart", "Content");
        }
        if (session.UsesFlatbedRegionWorkflow)
        {
            return session.Regions.Count > 0
                ? AppResources.FormatInteger("scanCountFormat", "Text", session.Regions.Count)
                : AppResources.Get("scanStart", "Content");
        }
        if (session.Options.BatchCount > 1)
        {
            return AppResources.FormatInteger("scanCountFormat", "Text", session.Options.BatchCount);
        }
        return view.libraryHost?.ActiveFrameId is null
            ? AppResources.Get("scanStart", "Content")
            : AppResources.Get("scanNext", "Content");
    }

    /// <summary>macOS 스캔 절의 필름 목록 순서입니다.</summary>
    internal static IReadOnlyList<FilmType> FilmTypes { get; } =
    [
        FilmType.ColorNegative,
        FilmType.ColorPositive,
        FilmType.BlackAndWhiteNegative,
        FilmType.BlackAndWhitePositive,
    ];

    internal static string ColorModeLabel(string mode) =>
        mode.Length == 0 ? mode : char.ToUpperInvariant(mode[0]) + mode[1..];

    /// <summary>
    /// 목록을 갈아 끼우고 고른 값을 다시 잡습니다. 목록을 지우면 선택이 풀리므로 항상 짝으로
    /// 해야 합니다.
    /// </summary>
    internal static void FillTagged(
        ComboBox selector,
        IReadOnlyList<(object Text, object Tag)> items,
        object? selectedTag)
    {
        if (!NeedsRebuild(selector, items))
        {
            SelectTagged(selector, selectedTag);
            return;
        }

        // 열린 콤보의 항목을 지우면 WinUI 가 0xc000027b 로 프로세스를 죽입니다.
        // 프레임 규격을 고를 때 그렇게 재현됐습니다. 목록이 달라질 때만 다시 채웁니다.
        selector.Items.Clear();
        foreach ((object text, object tag) in items)
        {
            selector.Items.Add(new ComboBoxItem { Content = text, Tag = tag });
        }

        SelectTagged(selector, selectedTag);
    }

    private static bool NeedsRebuild(
        ComboBox selector,
        IReadOnlyList<(object Text, object Tag)> items)
    {
        if (selector.Items.Count != items.Count)
        {
            return true;
        }

        for (int index = 0; index < items.Count; index++)
        {
            if (selector.Items[index] is not ComboBoxItem existing ||
                !Equals(existing.Tag, items[index].Tag) ||
                !Equals(existing.Content, items[index].Text))
            {
                return true;
            }
        }

        return false;
    }

    private static void SelectTagged(ComboBox selector, object? selectedTag)
    {
        foreach (object item in selector.Items)
        {
            if (item is ComboBoxItem candidate && Equals(candidate.Tag, selectedTag))
            {
                selector.SelectedItem = candidate;
                return;
            }
        }
    }
}
