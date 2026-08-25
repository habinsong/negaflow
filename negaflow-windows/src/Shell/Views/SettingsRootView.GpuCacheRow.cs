using System.Globalization;
using Microsoft.UI.Xaml;
using Negaflow.Interop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views;

/// <summary>
/// 설정창 "메모리 캐시" 구역의 <b>GPU</b> 줄입니다.
/// </summary>
/// <remarks>
/// <para>
/// <b>macOS 에는 이 줄이 없습니다.</b> 통합 메모리라 GPU 텍스처가 이미 RAM 캐시 예산 안에
/// 들어 있기 때문입니다. Windows 는 외장 그래픽에서 아예 다른 물리 메모리(VRAM)를 쓰므로
/// RAM 예산이 아무리 정확해도 GPU 쪽은 한 줄도 안 세어집니다 — 48MP 한 장이 float32 RGBA 로
/// 770MB 이고 <c>GpuImagePool</c> 이 최대 여섯 장이라 막지 않으면 한 풀이 4.6GB 를 잡습니다.
/// </para>
/// <para>
/// 위 RAM 줄과 <b>같은 갈래</b>로 만듭니다 — 자동이면 값 한 줄, 수동이면 슬라이더와
/// "자동값으로 되돌리기". 사용자가 배워야 할 규칙을 늘리지 않기 위해서입니다.
/// </para>
/// <para>
/// GPU 가 없으면 다섯 줄이 통째로 접힙니다. 없는 장치의 한도를 고르게 두면 거짓말입니다.
/// </para>
/// </remarks>
public sealed partial class SettingsRootView
{
    /// <summary>
    /// 이 기계의 GPU 상황입니다. 프로세스에 한 번만 읽습니다 — 어댑터는 실행 중에 바뀌지
    /// 않고, DXGI 예산은 매 프레임 흔들려서 그때마다 다시 그리면 값이 춤춥니다.
    /// </summary>
    /// <remarks>
    /// <b>UI 스레드에서 읽지 않습니다.</b> 엔진이 아직 GPU 를 안 열었으면 이 호출이
    /// `D3D11CreateDevice` 를 부르고, 그것은 수백 ms 가 걸릴 수 있습니다. 사진을 한 장도
    /// 안 보고 설정부터 여는 경우가 정확히 그 자리입니다. 워커에서 읽고 돌아와 그립니다.
    /// </remarks>
    private static GpuCacheInfo? sharedGpuCache;

    private static bool gpuCacheRead;

    private GpuCacheInfo? gpuCache;

    private void InitializeGpuCacheRow()
    {
        gpuCache = sharedGpuCache;
        GpuCacheModePicker.SelectionChanged += OnGpuCacheModeChanged;
        GpuCacheSlider.ValuePicked += OnGpuCacheSizePicked;
        if (gpuCacheRead)
        {
            return;
        }
        gpuCacheRead = true;
        _ = Task.Run(() =>
        {
            GpuCacheInfo? info = GpuCacheBridge.TryRead();
            _ = DispatcherQueue?.TryEnqueue(() =>
            {
                sharedGpuCache = info;
                gpuCache = info;
                // 값이 왔으니 그 줄만 다시 그립니다. 창 전체를 다시 그리면 사용자가
                // 만지고 있던 다른 줄이 튑니다.
                if (workspaceState?.Current is { } preferences)
                {
                    SynchronizeGpuCacheRow(preferences);
                }
            });
        });
    }

    private void LocalizeGpuCacheRow()
    {
        string label = AppResources.Get("settingsGpuCacheLabel", "Text");
        GpuCacheModeRow.Label = label;
        GpuCacheValueRow.Label = label;
        GpuCacheSlider.Label = label;
        GpuCacheModePicker.SetOptions(
            [
                new SegmentOption(
                    GpuCacheMode.Automatic,
                    AppResources.Get("settingsMemoryCacheModeAutomatic", "Content")),
                new SegmentOption(
                    GpuCacheMode.Manual,
                    AppResources.Get("settingsMemoryCacheModeManual", "Content")),
            ],
            GpuCacheModePicker.SelectedValue ?? GpuCacheMode.Automatic);
        GpuCacheResetButton.Content =
            AppResources.Get("settingsMemoryCacheResetToAutomatic", "Content");
    }

    private void SynchronizeGpuCacheRow(ShellPreferences preferences)
    {
        if (gpuCache is not { HasGpu: true } info)
        {
            GpuCacheModeRow.Visibility = Visibility.Collapsed;
            GpuCacheValueRow.Visibility = Visibility.Collapsed;
            GpuCacheSlider.Visibility = Visibility.Collapsed;
            GpuCacheResetRow.Visibility = Visibility.Collapsed;
            GpuCacheHelp.Visibility = Visibility.Collapsed;
            return;
        }

        GpuCacheSettings settings = preferences.GpuCache;
        bool manual = settings.Mode == GpuCacheMode.Manual;
        // 상·하한은 **이 기계가 보고한 용량**에서 옵니다. 바이트 상수를 박으면 VRAM 이
        // 다른 기계에서 그대로 거짓말이 됩니다.
        int minimum = GpuCacheSettings.MinimumMegabytesFor(info, InstalledMemoryBytes);
        int maximum = GpuCacheSettings.MaximumMegabytesFor(info, InstalledMemoryBytes);
        int automatic = Math.Clamp(
            GpuCacheSettings.AutomaticMegabytes(info), minimum, maximum);
        int chosen = manual && settings.ManualMegabytes > 0 ? settings.ManualMegabytes : automatic;
        chosen = Math.Clamp(chosen, minimum, maximum);

        GpuCacheModePicker.SetSelected(settings.Mode);
        GpuCacheValueRow.ValueText = MemoryBytesText((long)chosen * 1024L * 1024L);
        int step = GpuCacheSettings.StepMegabytes;
        GpuCacheSlider.Configure(
            minimum / step,
            Math.Max(minimum / step, maximum / step),
            chosen / step);
        GpuCacheSlider.ValueLabel = MemoryBytesText((long)chosen * 1024L * 1024L);

        GpuCacheModeRow.Visibility = Visibility.Visible;
        GpuCacheValueRow.Visibility = manual ? Visibility.Collapsed : Visibility.Visible;
        GpuCacheSlider.Visibility = manual ? Visibility.Visible : Visibility.Collapsed;
        GpuCacheResetRow.Visibility = manual ? Visibility.Visible : Visibility.Collapsed;
        GpuCacheHelp.Visibility = Visibility.Visible;
        MemoryCacheSection.Apply();

        // 어느 장치에 얼마를 걸었는지, 그 장치가 무엇을 가졌는지를 한 덩어리로 냅니다.
        // 내장은 VRAM 이 시스템 RAM 이라 위 RAM 예산과 같은 물리 메모리를 두고 다툽니다 —
        // 그 사실을 문구로 밝힙니다.
        ulong total = info.IsIntegrated
            ? InstalledMemoryBytes
            : (info.DedicatedVideoMemoryBytes > 0UL
                ? info.DedicatedVideoMemoryBytes
                : info.VideoMemoryBudgetBytes);
        GpuCacheHelp.Text = string.Join(
            '\n',
            string.Format(
                CultureInfo.CurrentCulture,
                AppResources.Get("settingsGpuCacheAdapterFormat", "Text"),
                info.AdapterDescription,
                MemoryBytesText((long)total)),
            AppResources.Get(
                info.IsIntegrated
                    ? "settingsGpuCacheIntegratedHelp"
                    : "settingsGpuCacheDiscreteHelp",
                "Text"));
    }

    private void OnGpuCacheModeChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating || GpuCacheModePicker.SelectedValue is not GpuCacheMode mode)
        {
            return;
        }
        // 자동에서 수동으로 넘어갈 때 값이 비어 있으면 슬라이더가 최소값으로 뚝 떨어집니다.
        // RAM 줄과 같은 규칙으로 자동값에서 시작합니다.
        GpuCacheInfo? info = gpuCache;
        workspaceState?.UpdateGpuCache(settings =>
            mode == GpuCacheMode.Manual && settings.ManualMegabytes <= 0 && info is { } known
                ? settings.ResetManualToAutomatic(known) with { Mode = mode }
                : settings with { Mode = mode });
    }

    private void OnGpuCacheSizePicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating)
        {
            return;
        }
        int megabytes = GpuCacheSlider.Value * GpuCacheSettings.StepMegabytes;
        workspaceState?.UpdateGpuCache(settings => settings with { ManualMegabytes = megabytes });
    }

    private void OnGpuCacheResetClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (gpuCache is not { } info)
        {
            return;
        }
        workspaceState?.UpdateGpuCache(settings => settings.ResetManualToAutomatic(info));
    }
}
