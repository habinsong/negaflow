using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Storage;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views;

/// <summary>
/// 설정창 "디스크" 탭입니다. macOS <c>DiskStorageSettingsSection</c> ·
/// <c>ScanStorageLocationView</c> · <c>ExternalBackupDestinationView</c> ·
/// <c>LibraryBackupScheduleView</c> 를 한 자리에 옮긴 것입니다.
/// </summary>
/// <remarks>
/// 여기서 고른 폴더는 <b>실제로 파일이 놓이는 자리</b>입니다 — 스캔 원본·썸네일·내보내기가
/// 모두 <see cref="DiskStorageLocations"/> 를 봅니다. 화면에만 적고 끝내면 사용자는 고른 곳에
/// 파일이 있다고 믿습니다.
/// </remarks>
public sealed partial class SettingsRootView
{
    /// <summary>여덟 경로 줄입니다. 라벨·현재 값·고른 값을 어디에 쓸지 한 자리에 둡니다.</summary>
    private (SettingsPathRow Row, string LabelKey, Func<DiskStorageLocations, string> Read,
        Func<DiskStorageSettings, string, DiskStorageSettings> Write)[] DiskPathRows =>
    [
        (DiskPage.DiskRootRow, "diskRootFolderLabel",
            locations => locations.Root,
            (settings, path) => settings with { RootFolder = path }),
        (DiskPage.DiskThumbnailsRow, "diskThumbnailsFolderLabel",
            locations => locations.Thumbnails,
            (settings, path) => settings with { ThumbnailsFolder = path }),
        (DiskPage.DiskImportedSourcesRow, "diskImportedSourcesFolderLabel",
            locations => locations.ImportedSources,
            (settings, path) => settings with { ImportedSourcesFolder = path }),
        (DiskPage.DiskCleanedRawRow, "diskCleanedRawFolderLabel",
            locations => locations.CleanedRaw,
            (settings, path) => settings with { CleanedRawFolder = path }),
        (DiskPage.DiskScanPreviewsRow, "diskScanPreviewFolderLabel",
            locations => locations.ScanPreviews,
            (settings, path) => settings with { ScanPreviewsFolder = path }),
        (DiskPage.DiskExportRow, "diskExportFolderLabel",
            locations => locations.Export,
            (settings, path) => settings with { ExportFolder = path }),
        (DiskPage.DiskQuickExportRow, "settingsQuickExportFolder",
            locations => locations.QuickExport,
            (settings, path) => settings with { QuickExportFolder = path }),
        (DiskPage.DiskScansRow, "scanStorageOriginals",
            locations => locations.Scans,
            (settings, path) => settings with { ScansFolder = path }),
    ];

    private void InitializeDiskTab()
    {
        DiskPage.DiskLocationPicker.SelectionChanged += OnDiskLocationChanged;
        foreach (var entry in DiskPathRows)
        {
            var write = entry.Write;
            SettingsPathRow row = entry.Row;
            var read = entry.Read;
            row.ChangeRequested += async (_, _) => await ChooseDiskFolderAsync(row, write);
            row.RevealRequested += (_, _) => RevealFolder(read(diskStorage));
        }
    }

    private void LocalizeDiskTab()
    {
        DiskPage.DiskSection.HeaderText = AppResources.Get("settingsDiskTab", "Text");
        DiskPage.DiskLocationPicker.SetOptions(
            [
                new SegmentOption(
                    DiskStorageLocationMode.Cloud,
                    AppResources.Get("diskLocationCloud", "Content")),
                new SegmentOption(
                    DiskStorageLocationMode.Desktop,
                    AppResources.Get("diskLocationDesktop", "Content")),
                new SegmentOption(
                    DiskStorageLocationMode.SpecificFolder,
                    AppResources.Get("diskLocationSpecificFolder", "Content")),
                new SegmentOption(
                    DiskStorageLocationMode.Custom,
                    AppResources.Get("diskLocationCustom", "Content")),
            ],
            DiskPage.DiskLocationPicker.SelectedValue ?? DiskStorageLocationMode.Desktop);
        string change = AppResources.Get("scanStorageChange", "Value");
        string reveal = AppResources.Get("showInExplorer", "Value");
        foreach (var entry in DiskPathRows)
        {
            entry.Row.Label = AppResources.Get(entry.LabelKey, "Text");
            entry.Row.SetButtonTooltips(change, reveal);
        }
        DiskPage.DiskAvailableRow.Label = AppResources.Get("scanStorageEstimatedAvailable", "Text");
        DiskPage.DiskStorageKindRow.Label = AppResources.Get("scanStorageStorage", "Text");
        DiskPage.DiskResetButton.Content = AppResources.Get("diskResetPathsButton", "Content");
        DiskPage.DiskThumbnailCacheRow.Label = AppResources.Get("diskThumbnailCacheLabel", "Text");
        DiskPage.DiskClearThumbnailCacheButton.Content =
            AppResources.Get("diskClearThumbnailCache", "Content");

        DiskPage.DiskBackupSection.HeaderText = AppResources.Get("diskLibraryBackupLabel", "Text");
        DiskPage.BackupFolderRow.Label = AppResources.Get("diskLibraryBackupLabel", "Text");
        DiskPage.ExternalBackupRow.Label = AppResources.Get("externalBackupTitle", "Text");
        DiskPage.ExternalBackupRemoveButton.Content = AppResources.Get("externalBackupRemove", "Content");
        DiskPage.ExternalBackupLastSuccessRow.Label =
            AppResources.Get("externalBackupLastSuccess", "Text");
        DiskPage.BackupScheduleRow.Label = AppResources.Get("backupScheduleLabel", "Text");
        DiskPage.BackupScheduleManualItem.Content = AppResources.Get("backupScheduleManual", "Content");
        DiskPage.BackupScheduleTerminationItem.Content =
            AppResources.Get("backupScheduleTermination", "Content");
        DiskPage.BackupScheduleDailyItem.Content = AppResources.Get("backupScheduleDaily", "Content");
        DiskPage.BackupScheduleWeeklyItem.Content = AppResources.Get("backupScheduleWeekly", "Content");
        DiskPage.BackupLastAttemptRow.Label = AppResources.Get("backupLastAttempt", "Text");
        DiskPage.BackupLastSuccessRow.Label = AppResources.Get("backupLastSuccess", "Text");
        DiskPage.BackupVerificationRow.Label = AppResources.Get("backupVerification", "Text");
        DiskPage.BackupNowButton.Content = AppResources.Get("diskLibraryBackupNow", "Content");
        DiskPage.BackupBrowseButton.Content = AppResources.Get("diskLibraryBackupBrowse", "Content");
        DiskPage.BackupArchiveButton.Content = AppResources.Get("libraryArchiveCreate", "Content");
    }

    private void SynchronizeDiskTab(ShellPreferences preferences)
    {
        bool custom = preferences.Disk.LocationMode == DiskStorageLocationMode.Custom;
        DiskPage.DiskLocationPicker.SetSelected(preferences.Disk.LocationMode);
        foreach (var entry in DiskPathRows)
        {
            entry.Row.PathText = DiskStorageLocations.Abbreviate(entry.Read(diskStorage));
            entry.Row.CanChange = custom;
        }
        DiskPage.DiskResetRow.Visibility = custom ? Visibility.Visible : Visibility.Collapsed;
        DiskPage.DiskSection.Apply();

        ScanStorageLocationStatus status =
            ScanStorageLocationInspector.Inspect(diskStorage.Scans);
        DiskPage.DiskAvailableRow.ValueText = status.AvailableCapacityBytes is { } available
            ? FileBytesText(available)
            : AppResources.Get("scanStorageUnavailable", "Text");
        DiskPage.DiskStorageKindRow.ValueText = AppResources.Get(
            status.Kind == ScanStorageKind.CloudManaged
                ? "scanStorageCloudManaged"
                : "scanStorageLocal",
            "Text");

        LibraryBackupSettings backup = preferences.Backup;
        DiskPage.BackupFolderRow.ValueText = library?.StorageRoots is { } roots
            ? DiskStorageLocations.Abbreviate(roots.BackupRoot)
            : AppResources.Get("scanStorageUnavailable", "Text");
        DiskPage.ExternalBackupChooseButton.Content = AppResources.Get(
            backup.ExternalDestination.Length == 0 ? "externalBackupChoose" : "externalBackupChange",
            "Content");
        DiskPage.ExternalBackupRemoveButton.Visibility = backup.ExternalDestination.Length == 0
            ? Visibility.Collapsed
            : Visibility.Visible;
        DiskPage.ExternalBackupStatusLine.Text = ExternalBackupStatusText(backup);
        DiskPage.ExternalBackupLastSuccessRow.ValueText = DateText(backup.ExternalLastSuccessAt);
        DiskPage.BackupScheduleComboBox.SelectedIndex = (int)backup.Schedule;
        DiskPage.BackupLastAttemptRow.ValueText = DateText(backup.LastAttemptAt);
        DiskPage.BackupLastSuccessRow.ValueText = DateText(backup.LastSuccessAt);
        DiskPage.BackupVerificationRow.ValueText = backup.LastRestoreDrillSucceeded is { } passed
            ? AppResources.Get(passed ? "backupPassed" : "backupFailed", "Text")
            : AppResources.Get("backupNever", "Text");
        DiskPage.BackupVerificationRow.Reason = backup.LastRestoreDrillGeneration.Length == 0
            ? string.Empty
            : $"{AppResources.Get("backupGeneration", "Text")} {backup.LastRestoreDrillGeneration}";
        DiskPage.DiskBackupSection.Apply();
        RefreshThumbnailCacheSize();
    }

    /// <summary>
    /// macOS <c>ExternalBackupDestinationView.statusRow</c> — 상태와 남은 공간을 한 줄로.
    /// </summary>
    private string ExternalBackupStatusText(LibraryBackupSettings backup)
    {
        string catalogPath = library?.StorageRoots?.CatalogPath ?? string.Empty;
        (ExternalBackupStatus status, long? available) = ExternalBackupInspector.Inspect(
            backup.ExternalDestination, catalogPath, RequiredBackupBytes());
        string label = AppResources.Get(status switch
        {
            ExternalBackupStatus.Disconnected => "externalBackupDisconnected",
            ExternalBackupStatus.SameVolume => "externalBackupSameVolume",
            ExternalBackupStatus.ReadOnly => "externalBackupReadOnly",
            ExternalBackupStatus.Insufficient => "externalBackupInsufficient",
            ExternalBackupStatus.Ready => "externalBackupReady",
            _ => "externalBackupNotConfigured",
        }, "Text");
        if (available is not { } bytes)
        {
            return label;
        }
        return string.Concat(
            label,
            " · ",
            AppResources.Get("externalBackupCapacity", "Text"),
            " ",
            FileBytesText(bytes));
    }

    /// <summary>백업 한 세대가 쓸 만한 넉넉한 크기입니다 — 카탈로그 파일 크기의 세 배.</summary>
    private long RequiredBackupBytes()
    {
        try
        {
            if (library?.StorageRoots is { } roots && File.Exists(roots.CatalogPath))
            {
                return Math.Max(16L * 1024 * 1024, new FileInfo(roots.CatalogPath).Length * 3);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // 크기를 못 재면 최소값으로 봅니다.
        }
        return 16L * 1024 * 1024;
    }

    /// <summary>macOS <c>ByteCountFormatter(countStyle: .file)</c> — 1000 배수입니다.</summary>
    private static string FileBytesText(long bytes)
    {
        string[] units = ["bytes", "KB", "MB", "GB", "TB"];
        double value = bytes;
        int unit = 0;
        while (value >= 1000 && unit < units.Length - 1)
        {
            value /= 1000;
            ++unit;
        }
        string text = unit == 0
            ? ((long)value).ToString(CultureInfo.CurrentCulture)
            : Math.Round(value, 2).ToString("0.##", CultureInfo.CurrentCulture);
        return $"{text} {units[unit]}";
    }

    private static string DateText(DateTimeOffset? value) => value is { } stamp
        ? stamp.LocalDateTime.ToString("g", CultureInfo.CurrentCulture)
        : AppResources.Get("backupNever", "Text");

    private void OnDiskLocationChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating || DiskPage.DiskLocationPicker.SelectedValue is not DiskStorageLocationMode mode)
        {
            return;
        }
        if (mode == DiskStorageLocationMode.SpecificFolder)
        {
            // macOS 도 "특정 폴더"를 고르면 곧바로 폴더 선택기를 엽니다. 고르지 않고 닫으면
            // 방식이 바뀌지 않아야 하므로 되돌립니다.
            _ = ChooseSpecificFolderAsync();
            return;
        }
        workspaceState?.UpdateDisk(settings => settings with { LocationMode = mode });
        EnsureDiskFolders();
    }

    private async Task ChooseSpecificFolderAsync()
    {
        if (await PickFolderAsync() is { } chosen)
        {
            workspaceState?.UpdateDisk(settings => settings with
            {
                LocationMode = DiskStorageLocationMode.SpecificFolder,
                SpecificFolder = chosen,
            });
            EnsureDiskFolders();
        }
        else if (workspaceState is { } state)
        {
            DiskPage.DiskLocationPicker.SetSelected(state.Current.Disk.LocationMode);
        }
    }

    private async Task ChooseDiskFolderAsync(
        SettingsPathRow row,
        Func<DiskStorageSettings, string, DiskStorageSettings> write)
    {
        _ = row;
        if (await PickFolderAsync() is { } chosen)
        {
            // macOS activateCustomMode — 폴더를 직접 고르면 방식은 커스텀이 됩니다.
            workspaceState?.UpdateDisk(settings => write(settings, chosen) with
            {
                LocationMode = DiskStorageLocationMode.Custom,
            });
            EnsureDiskFolders();
        }
    }

    private async Task<string?> PickFolderAsync()
    {
        if (pickerWindowId is not { } windowId)
        {
            return null;
        }
        Microsoft.Windows.Storage.Pickers.FolderPicker picker = new(windowId)
        {
            CommitButtonText = AppResources.Get("scanStorageChange", "Value"),
        };
        try
        {
            return (await picker.PickSingleFolderAsync())?.Path;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            return null;
        }
    }

    /// <summary>고른 자리에 폴더를 실제로 만듭니다. macOS <c>ensureCurrentFolders()</c>.</summary>
    private void EnsureDiskFolders()
    {
        if (workspaceState is { } state)
        {
            new DiskStorageLocations(state.Current.Disk).EnsureAll();
        }
    }

    internal void OnDiskResetPathsClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.UpdateDisk(settings => settings.ResetPaths());
    }

    private static void RevealFolder(string path)
    {
        if (path.Length == 0)
        {
            return;
        }
        try
        {
            DiskStorageLocations.EnsureDirectory(path);
            using System.Diagnostics.Process? _ = System.Diagnostics.Process.Start(
                new System.Diagnostics.ProcessStartInfo(path) { UseShellExecute = true });
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            System.ComponentModel.Win32Exception)
        {
            // 열지 못해도 설정은 그대로입니다.
        }
    }

    private void RefreshThumbnailCacheSize()
    {
        DiskPage.DiskThumbnailCacheSize.Text = AppResources.Get("diskCacheSizeCalculating", "Text");
        string directory = diskStorage.Thumbnails;
        _ = MeasureThumbnailCacheAsync(directory);
    }

    private async Task MeasureThumbnailCacheAsync(string directory)
    {
        long bytes = await Task.Run(
            () => Negaflow.Shell.Library.ThumbnailDiskCache.DirectorySize(directory));
        DiskPage.DiskThumbnailCacheSize.Text = FileBytesText(bytes);
    }

    internal async void OnClearThumbnailCacheClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        DiskPage.DiskClearThumbnailCacheButton.IsEnabled = false;
        try
        {
            string directory = diskStorage.Thumbnails;
            if (thumbnails is { } cache)
            {
                await cache.ClearDiskCacheAsync();
            }
            await MeasureThumbnailCacheAsync(directory);
        }
        finally
        {
            DiskPage.DiskClearThumbnailCacheButton.IsEnabled = true;
        }
    }

    internal void OnBackupScheduleChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating || DiskPage.BackupScheduleComboBox.SelectedIndex < 0)
        {
            return;
        }
        var schedule = (LibraryBackupSchedule)DiskPage.BackupScheduleComboBox.SelectedIndex;
        workspaceState?.UpdateBackup(backup => backup with { Schedule = schedule });
    }

    internal async void OnBackupNowClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (library is not { } host)
        {
            return;
        }
        DiskPage.BackupNowButton.IsEnabled = false;
        try
        {
            DateTimeOffset attempt = DateTimeOffset.Now;
            Negaflow.Catalog.CatalogBackupCreateResult result =
                await Task.Run(host.CreateBackup);
            // 시도는 늘 적고, 성공은 정말 성공했을 때만 적습니다.
            workspaceState?.UpdateBackup(backup => result.IsSuccess
                ? backup with { LastAttemptAt = attempt, LastSuccessAt = attempt }
                : backup with { LastAttemptAt = attempt });
        }
        finally
        {
            DiskPage.BackupNowButton.IsEnabled = true;
        }
    }

    internal void OnBrowseBackupsClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (library?.StorageRoots is { } roots)
        {
            RevealFolder(roots.BackupRoot);
        }
    }

    internal async void OnChooseExternalBackupClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (await PickFolderAsync() is { } chosen)
        {
            workspaceState?.UpdateBackup(backup => backup with { ExternalDestination = chosen });
        }
    }

    internal void OnRemoveExternalBackupClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.UpdateBackup(backup => backup with
        {
            ExternalDestination = string.Empty,
            ExternalLastSuccessAt = null,
        });
    }

    /// <summary>
    /// macOS <c>LibraryArchiveButton.presentSavePanel()</c> 자리입니다. 카탈로그와 결함
    /// 레시피를 한 덩어리로 묶고 파일마다 SHA-256 을 적습니다.
    /// </summary>
    internal async void OnCreateArchiveClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (library?.StorageRoots is not { } roots || pickerWindowId is not { } windowId)
        {
            return;
        }
        Microsoft.Windows.Storage.Pickers.FileSavePicker picker = new(windowId)
        {
            SuggestedFileName = LibraryArchiveWriter.DefaultFileName(DateTimeOffset.Now),
        };
        picker.FileTypeChoices.Add("negaflow", [".negaflowarchive"]);
        string? destination;
        try
        {
            destination = (await picker.PickSaveFileAsync())?.Path;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            return;
        }
        if (destination is null)
        {
            return;
        }
        DiskPage.BackupArchiveButton.IsEnabled = false;
        try
        {
            DateTimeOffset now = DateTimeOffset.Now;
            _ = await Task.Run(() => LibraryArchiveWriter.Write(roots, destination, now));
        }
        finally
        {
            DiskPage.BackupArchiveButton.IsEnabled = true;
        }
    }
}
