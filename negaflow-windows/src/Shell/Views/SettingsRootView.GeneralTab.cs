using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Diagnostics;
using Negaflow.Shell.Library;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views;

/// <summary>
/// 설정창 "일반" 탭입니다. macOS <c>AppSettingsView.generalPane</c> 와 같은 세 구역 —
/// 일반(언어·화면 모드·개발자 모드) · <c>MemoryCacheSettingsSection</c> ·
/// <c>SupportBundleSettingsSection</c>.
/// </summary>
public sealed partial class SettingsRootView
{
    /// <summary>이 기계의 설치 메모리입니다. 자동 한도와 상한 계산의 기준입니다.</summary>
    private ulong InstalledMemoryBytes =>
        thumbnails?.InstalledMemory ?? FrameCacheBudget.ConservativeMemoryCeilingBytes;

    private void InitializeGeneralTab()
    {
        DeveloperModeRow.Switched += OnDeveloperModeSwitched;
        MemoryCacheModePicker.SelectionChanged += OnMemoryCacheModeChanged;
        MemoryCacheCleanedRawSlider.ValuePicked += OnMemoryCacheCleanedRawPicked;
        MemoryCacheDevelopedSlider.ValuePicked += OnMemoryCacheDevelopedPicked;
        InitializeGpuCacheRow();
    }

    private void LocalizeGeneralTab()
    {
        GeneralSection.HeaderText = AppResources.Get("settingsGeneralTab", "Text");
        LanguageRow.Label = AppResources.Get("settingsLanguagePicker", "Text");
        AppearanceRow.Label = AppResources.Get("settingsAppearancePicker", "Text");
        DeveloperModeRow.Label = AppResources.Get("developerMode", "Header");


        string memory = AppResources.Get("settingsMemoryCacheSection", "Text");
        MemoryCacheSection.HeaderText = memory;
        MemoryCacheModeRow.Label = memory;
        MemoryCacheModePicker.SetOptions(
            [
                new SegmentOption(
                    FrameCacheResidencyMode.Automatic,
                    AppResources.Get("settingsMemoryCacheModeAutomatic", "Content")),
                new SegmentOption(
                    FrameCacheResidencyMode.Manual,
                    AppResources.Get("settingsMemoryCacheModeManual", "Content")),
            ],
            MemoryCacheModePicker.SelectedValue ?? FrameCacheResidencyMode.Automatic);
        string cleanedRaw = AppResources.Get("settingsMemoryCacheCleanedRawLabel", "Text");
        string developed = AppResources.Get("settingsMemoryCacheDevelopedLabel", "Text");
        MemoryCacheCleanedRawRow.Label = cleanedRaw;
        MemoryCacheDevelopedRow.Label = developed;
        MemoryCacheCleanedRawSlider.Label = cleanedRaw;
        MemoryCacheDevelopedSlider.Label = developed;
        MemoryCacheResetButton.Content =
            AppResources.Get("settingsMemoryCacheResetToAutomatic", "Content");

        LocalizeGpuCacheRow();

        SupportBundleSection.HeaderText = AppResources.Get("supportBundleTitle", "Text");
        SupportBundleRow.Label = AppResources.Get("supportBundleTitle", "Text");
        SupportBundleExportButton.Content = isExportingSupportBundle
            ? AppResources.Get("supportBundleCreating", "Content")
            : AppResources.Get("supportBundleExport", "Content");
    }

    /// <summary>
    /// 저장값을 화면에 겁니다. macOS <c>MemoryCacheSettingsSection.body</c> 와 같은 갈래 —
    /// 자동이면 값 두 줄, 수동이면 슬라이더 두 줄과 되돌리기 단추.
    /// </summary>
    private void SynchronizeGeneralTab(ShellPreferences preferences)
    {
        DeveloperModeRow.IsOn = preferences.DeveloperMode;

        FrameCacheResidencySettings settings = preferences.FrameCache;
        ulong installed = InstalledMemoryBytes;
        bool manual = settings.Mode == FrameCacheResidencyMode.Manual;
        MemoryCacheModePicker.SetSelected(settings.Mode);

        FrameCacheLimits effective = settings.EffectiveLimits(installed);
        FrameCacheLimits maximum = FrameCacheResidencySettings.ManualMaximumLimits(installed);
        MemoryCacheCleanedRawRow.ValueText = FrameCountText(effective.CleanedRaw);
        MemoryCacheDevelopedRow.ValueText = FrameCountText(effective.Developed);
        MemoryCacheCleanedRawSlider.Configure(
            FrameCacheBudget.MinimumCleanedRaw, maximum.CleanedRaw, effective.CleanedRaw);
        MemoryCacheCleanedRawSlider.ValueLabel = FrameCountText(effective.CleanedRaw);
        MemoryCacheDevelopedSlider.Configure(
            FrameCacheBudget.MinimumDeveloped, maximum.Developed, effective.Developed);
        MemoryCacheDevelopedSlider.ValueLabel = FrameCountText(effective.Developed);

        MemoryCacheCleanedRawRow.Visibility = manual ? Visibility.Collapsed : Visibility.Visible;
        MemoryCacheDevelopedRow.Visibility = manual ? Visibility.Collapsed : Visibility.Visible;
        MemoryCacheCleanedRawSlider.Visibility = manual ? Visibility.Visible : Visibility.Collapsed;
        MemoryCacheDevelopedSlider.Visibility = manual ? Visibility.Visible : Visibility.Collapsed;
        MemoryCacheResetRow.Visibility = manual ? Visibility.Visible : Visibility.Collapsed;
        // 보임이 바뀌었으니 분리선을 다시 놓습니다 — 접힌 줄 앞에 선만 남으면 빈 줄로 보입니다.
        MemoryCacheSection.Apply();

        // macOS 는 세 줄을 개행으로 이어 한 덩어리로 냅니다.
        double residentMegabytes = FrameCacheBudget.EstimatedResidentMegabytes(effective);
        MemoryCacheHelp.Text = string.Join(
            '\n',
            string.Format(
                CultureInfo.CurrentCulture,
                AppResources.Get("settingsMemoryCacheInstalledMemoryFormat", "Text"),
                MemoryBytesText((long)installed)),
            string.Format(
                CultureInfo.CurrentCulture,
                AppResources.Get("settingsMemoryCacheEstimateFormat", "Text"),
                MemoryBytesText((long)(residentMegabytes * 1024 * 1024)),
                (int)Math.Round(
                    FrameCacheBudget.ResidentMemoryFraction(effective, installed) * 100)),
            AppResources.Get(
                manual ? "settingsMemoryCacheManualHelp" : "settingsMemoryCacheAutomaticHelp",
                "Text"));

        SynchronizeGpuCacheRow(preferences);
    }

    private static string FrameCountText(int count) => string.Format(
        CultureInfo.CurrentCulture,
        AppResources.Get("settingsMemoryCacheFramesFormat", "Text"),
        count);

    /// <summary>
    /// macOS <c>ByteCountFormatter</c>(<c>useGB/useMB</c>, <c>countStyle: .memory</c>) 자리입니다.
    /// </summary>
    /// <remarks>
    /// <c>.memory</c> 는 1024 배수를 쓰고 소수점 뒤 0 을 떨굽니다 — 24GiB 는 "24 GB",
    /// 6.21GiB 는 "6.21 GB" 로 나옵니다. 화면 문구가 macOS 와 같아야 하므로 그 규칙을 그대로 씁니다.
    /// </remarks>
    private static string MemoryBytesText(long bytes)
    {
        const double Mebibyte = 1024.0 * 1024.0;
        const double Gibibyte = Mebibyte * 1024.0;
        (double value, string unit) = bytes >= Gibibyte
            ? (bytes / Gibibyte, "GB")
            : (bytes / Mebibyte, "MB");
        string text = Math.Round(value, 2).ToString("0.##", CultureInfo.CurrentCulture);
        return $"{text} {unit}";
    }

    private void OnDeveloperModeSwitched(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isUpdating)
        {
            workspaceState?.SetDeveloperMode(DeveloperModeRow.IsOn);
        }
    }

    private void OnMemoryCacheModeChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating ||
            MemoryCacheModePicker.SelectedValue is not FrameCacheResidencyMode mode)
        {
            return;
        }
        // 자동에서 수동으로 넘어갈 때 값이 비어 있으면 슬라이더가 최소값으로 뚝 떨어집니다.
        // macOS 는 저장된 값이 없으면 자동값에서 시작하므로 그 자리를 채워 둡니다.
        ulong installed = InstalledMemoryBytes;
        workspaceState?.UpdateFrameCache(settings => mode == FrameCacheResidencyMode.Manual &&
            (settings.ManualCleanedRaw <= 0 || settings.ManualDeveloped <= 0)
                ? settings.ResetManualToAutomatic(installed) with { Mode = mode }
                : settings with { Mode = mode });
    }

    private void OnMemoryCacheCleanedRawPicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isUpdating)
        {
            int value = MemoryCacheCleanedRawSlider.Value;
            MemoryCacheCleanedRawSlider.ValueLabel = FrameCountText(value);
            workspaceState?.UpdateFrameCache(
                settings => settings with { ManualCleanedRaw = value });
        }
    }

    private void OnMemoryCacheDevelopedPicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isUpdating)
        {
            int value = MemoryCacheDevelopedSlider.Value;
            MemoryCacheDevelopedSlider.ValueLabel = FrameCountText(value);
            workspaceState?.UpdateFrameCache(
                settings => settings with { ManualDeveloped = value });
        }
    }

    private void OnMemoryCacheResetClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ulong installed = InstalledMemoryBytes;
        workspaceState?.UpdateFrameCache(
            settings => settings.ResetManualToAutomatic(installed));
    }

    private bool isExportingSupportBundle;

    /// <summary>
    /// macOS <c>SupportBundleSettingsSection.presentSavePanel()</c> 자리입니다. 파일 이름도
    /// 같은 규칙입니다 — <c>negaflow-support-yyyyMMdd-HHmmss.zip</c>.
    /// </summary>
    private async void OnSupportBundleExportClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isExportingSupportBundle || pickerWindowId is not { } windowId)
        {
            return;
        }

        Microsoft.Windows.Storage.Pickers.FileSavePicker picker = new(windowId)
        {
            SuggestedFileName = string.Create(
                CultureInfo.InvariantCulture,
                $"negaflow-support-{DateTime.Now:yyyyMMdd-HHmmss}"),
        };
        picker.FileTypeChoices.Add("Zip", [".zip"]);
        string? destination;
        try
        {
            destination = (await picker.PickSaveFileAsync())?.Path;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            ShowSupportBundleResult(succeeded: false);
            return;
        }
        if (destination is null)
        {
            return;
        }

        isExportingSupportBundle = true;
        SupportBundleExportButton.IsEnabled = false;
        SupportBundleExportButton.Content =
            AppResources.Get("supportBundleCreating", "Content");
        SupportBundleResult.Visibility = Visibility.Collapsed;
        try
        {
            SupportBundleInputs inputs = CollectSupportBundleInputs();
            DateTimeOffset now = DateTimeOffset.Now;
            SupportBundleArchiveError result = await Task.Run(() =>
                SupportBundleArchiveWriter.Write(
                    SupportBundleBuilder.Build(inputs, now), destination));
            ShowSupportBundleResult(result == SupportBundleArchiveError.None);
        }
        finally
        {
            isExportingSupportBundle = false;
            SupportBundleExportButton.IsEnabled = true;
            SupportBundleExportButton.Content =
                AppResources.Get("supportBundleExport", "Content");
        }
    }

    private void ShowSupportBundleResult(bool succeeded)
    {
        SupportBundleResult.Text = AppResources.Get(
            succeeded ? "supportBundleComplete" : "supportBundleFailed", "Text");
        SupportBundleResult.Visibility = Visibility.Visible;
        SupportBundleSection.Apply();
    }

    /// <summary>
    /// 번들에 담을 값을 모읍니다. 디스크를 읽는 부분은 <see cref="SupportBundleBuilder"/> 가
    /// 워커에서 합니다 — 여기서는 <b>UI 스레드에서만 읽을 수 있는 것</b>만 집습니다.
    /// </summary>
    private SupportBundleInputs CollectSupportBundleInputs()
    {
        StorageRootSet roots = library?.StorageRoots ??
            StorageRootResolver.ResolveProduction().Roots ??
            throw new InvalidOperationException("Storage roots are unavailable.");
        IReadOnlyList<InstalledScannerPlugin> plugins =
            ScannerPluginDiscovery.Discover(roots.PluginRoot);
        ScannerPluginTrustStore trust = new();
        Dictionary<string, ScannerPluginApprovalState> approvals = new(StringComparer.Ordinal);
        foreach (InstalledScannerPlugin plugin in plugins)
        {
            approvals[plugin.Manifest.Id] = trust.StateFor(plugin);
        }
        FrameCacheResidencySettings cache =
            workspaceState?.Current.FrameCache ?? new FrameCacheResidencySettings();
        return new SupportBundleInputs
        {
            Roots = roots,
            ScanOriginalsDirectory = diskStorage.Scans,
            ThumbnailDirectory = diskStorage.Thumbnails,
            ScanStorageKind =
                Negaflow.Shell.Storage.ScanStorageLocationInspector
                    .Inspect(diskStorage.Scans).Kind ==
                    Negaflow.Shell.Storage.ScanStorageKind.CloudManaged
                    ? "cloudManaged"
                    : "local",
            Lifecycle = library?.State.ToString() ?? "notOpened",
            BlockReason = library?.SessionError is { } sessionError and not CatalogSessionError.None
                ? sessionError.ToString()
                : null,
            FrameCount = library?.Frames.Count(frame => !frame.IsPreviewScan) ?? 0,
            RollCount = library?.Rolls.Count ?? 0,
            FolderCount = library?.Folders.Count ?? 0,
            Issues = [.. (library?.Issues ?? [])
                .Select(issue => new SupportBundleIssue(
                    issue.Error.ToString(),
                    issue.Error == LibraryFrameError.None ? "warning" : "error"))],
            Limits = cache.EffectiveLimits(InstalledMemoryBytes),
            ResidentDevelopedCount = 0,
        };
    }
}
