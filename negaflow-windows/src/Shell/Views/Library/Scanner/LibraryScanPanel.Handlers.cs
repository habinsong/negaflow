using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell.Views.Library.Scanner;

/// <summary>
/// 스캔 카드의 컨트롤 반응입니다. 세션 수명·메뉴 표면과 다른 이유로 바뀝니다.
/// </summary>
/// <remarks>
/// macOS <c>ScannerControlsSection</c> 의 각 <c>Binding</c> 이 하는 일과 하나씩 맞물립니다 —
/// 고르개 하나가 <c>model</c> 값 하나를 바꾸고, 값이 바뀌면 절 전체가 다시 그려집니다.
/// </remarks>
public sealed partial class LibraryScanPanel
{
    private void OnScanApprovePluginClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (scanSession?.PluginsRequiringApproval is not { Count: > 0 } pending)
        {
            return;
        }
        foreach (InstalledScannerPlugin plugin in pending)
        {
            scanSession.Approve(plugin);
        }
    }

    /// <summary>
    /// 하드웨어 없이 스캔 흐름을 돌립니다. 켜면 가상 장치가 나타나고, 스캔은 합성 네거티브를
    /// 실제와 같은 게시 경로로 카탈로그에 올립니다.
    /// </summary>
    private async void OnScanSimulatorToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan || scanSession is null)
        {
            return;
        }
        scanSession.SetSimulatorEnabled(ScanSimulatorToggle.IsOn);
        if (scanSession.State is ScanSessionState.NoDevice)
        {
            await scanSession.RefreshDevicesAsync();
        }
    }

    private async void OnScanRescanClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (scanSession is not null)
        {
            await scanSession.RefreshDevicesAsync();
        }
    }

    private async void OnScanDeviceChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            scanSession is null ||
            ScanDeviceSelector.SelectedItem is not ComboBoxItem { Tag: string deviceId })
        {
            return;
        }
        await scanSession.SelectDeviceAsync(deviceId);
    }

    private void OnScanFilmChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            ScanFilmSelector.SelectedItem is not ComboBoxItem { Tag: FilmType filmType })
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { FilmType = filmType });
    }

    private void OnScanFolderNameChanged(object sender, TextChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan)
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { FolderName = ScanFolderNameBox.Text });
    }

    private void OnScanResolutionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            ScanResolutionSelector.SelectedItem is not ComboBoxItem { Tag: int dpi })
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { ResolutionDpi = dpi });
    }

    private void OnScanColorModeChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            ScanColorModeSelector.SelectedItem is not ComboBoxItem { Tag: string mode })
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { ColorMode = mode });
    }

    private void OnScanBitDepthChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            ScanBitDepthSelector.SelectedItem is not ComboBoxItem { Tag: int depth })
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { BitDepth = depth });
    }

    private void OnScanFrameCountChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        _ = sender;
        if (isSynchronizingScan || double.IsNaN(args.NewValue))
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { BatchCount = (int)args.NewValue });
    }

    private void OnScanInfraredToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan)
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { Infrared = ScanInfraredToggle.IsOn });
    }

    private void OnScanFrameFormatChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan ||
            ScanFrameFormatSelector.SelectedItem is not ComboBoxItem { Tag: FlatbedFrameFormat format })
        {
            return;
        }
        scanSession?.UpdateOptions(options => options with { FrameFormat = format });
    }

    private void OnScanDetectionModeChecked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingScan || scanSession is null)
        {
            return;
        }
        scanSession.UpdateOptions(options => options with
        {
            FrameDetectionMode = ScanDetectionManualButton.IsChecked == true
                ? FlatbedFrameDetectionMode.Manual
                : FlatbedFrameDetectionMode.Automatic,
        });
    }

    /// <summary>
    /// 자동이면 프리뷰에서 다시 찾고, 수동이면 지우고 규격 프레임 하나를 놓아 다시 시작할 자리를
    /// 만듭니다 — macOS 새로고침과 같은 규칙입니다.
    /// </summary>
    private void OnScanRefreshFramesClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (scanSession is null)
        {
            return;
        }
        // 프리뷰 픽셀이 아직 없으면 찾을 근거가 없습니다. macOS 도 프리뷰 전에는 잠급니다.
        _ = scanSession.RefreshRegions(
            flatbedPreview.Values,
            flatbedPreview.Width,
            flatbedPreview.Height);
        renderer.Render();
    }

    private void OnScanAddFrameClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _ = scanSession?.AddRegion();
        renderer.Render();
    }

    private void OnScanRemoveFrameClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _ = scanSession?.DeleteSelectedRegion();
        renderer.Render();
    }

    private void OnScanCopyFrameClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _ = scanSession?.CopySelectedRegion();
        renderer.Render();
    }

    private void OnScanPasteFrameClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _ = scanSession?.PasteRegion();
        renderer.Render();
    }

    private async void OnScanPreviewClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        await runner.RunAsync(preview: true);
    }

    private async void OnScanStartClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        await runner.RunAsync(preview: false);
    }

    /// <summary>macOS <c>Button(role: .destructive) { cancelScan() }</c>.</summary>
    private void OnScanCancelClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        runner.Cancel();
    }

    /// <summary>
    /// macOS <c>chooseScanStorageRoot()</c> — 스캔 원본을 둘 폴더를 고릅니다. 고른 값은
    /// <c>diskStorage.scansPath</c> 자리인 <see cref="ScanSessionController.ScanStorageRoot"/>
    /// 에 들어갑니다.
    /// </summary>
    private async void OnScanChooseFolderClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (scanSession is null || WindowId is not { } windowId)
        {
            return;
        }
        Microsoft.Windows.Storage.Pickers.FolderPicker picker = new(windowId)
        {
            CommitButtonText = Localization.AppResources.Get("scanChooseFolder", "Text"),
        };
        Microsoft.Windows.Storage.Pickers.PickFolderResult? picked =
            await picker.PickSingleFolderAsync();
        if (picked is null)
        {
            return;
        }
        scanSession.ScanStorageRoot = picked.Path;
        ScanStatusText.Text = picked.Path;
    }
}
