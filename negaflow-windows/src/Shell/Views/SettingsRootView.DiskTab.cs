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
        (DiskRootRow, "diskRootFolderLabel",
            locations => locations.Root,
            (settings, path) => settings with { RootFolder = path }),
        (DiskThumbnailsRow, "diskThumbnailsFolderLabel",
            locations => locations.Thumbnails,
            (settings, path) => settings with { ThumbnailsFolder = path }),
        (DiskImportedSourcesRow, "diskImportedSourcesFolderLabel",
            locations => locations.ImportedSources,
            (settings, path) => settings with { ImportedSourcesFolder = path }),
        (DiskCleanedRawRow, "diskCleanedRawFolderLabel",
            locations => locations.CleanedRaw,
            (settings, path) => settings with { CleanedRawFolder = path }),
        (DiskScanPreviewsRow, "diskScanPreviewFolderLabel",
            locations => locations.ScanPreviews,
            (settings, path) => settings with { ScanPreviewsFolder = path }),
        (DiskExportRow, "diskExportFolderLabel",
            locations => locations.Export,
            (settings, path) => settings with { ExportFolder = path }),
        (DiskQuickExportRow, "settingsQuickExportFolder",
            locations => locations.QuickExport,
            (settings, path) => settings with { QuickExportFolder = path }),
        (DiskScansRow, "scanStorageOriginals",
            locations => locations.Scans,
            (settings, path) => settings with { ScansFolder = path }),
    ];

    private void InitializeDiskTab()
    {
        DiskLocationPicker.SelectionChanged += OnDiskLocationChanged;
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
        DiskSection.HeaderText = AppResources.Get("settingsDiskTab", "Text");
        DiskLocationPicker.SetOptions(
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
            DiskLocationPicker.SelectedValue ?? DiskStorageLocationMode.Desktop);
        string change = AppResources.Get("scanStorageChange", "Value");
        string reveal = AppResources.Get("showInExplorer", "Value");
        foreach (var entry in DiskPathRows)
        {
            entry.Row.Label = AppResources.Get(entry.LabelKey, "Text");
            entry.Row.SetButtonTooltips(change, reveal);
        }
        DiskAvailableRow.Label = AppResources.Get("scanStorageEstimatedAvailable", "Text");
        DiskStorageKindRow.Label = AppResources.Get("scanStorageStorage", "Text");
        DiskResetButton.Content = AppResources.Get("diskResetPathsButton", "Content");
        DiskThumbnailCacheRow.Label = AppResources.Get("diskThumbnailCacheLabel", "Text");
        DiskClearThumbnailCacheButton.Content =
            AppResources.Get("diskClearThumbnailCache", "Content");

        DiskBackupSection.HeaderText = AppResources.Get("diskLibraryBackupLabel", "Text");
        BackupFolderRow.Label = AppResources.Get("diskLibraryBackupLabel", "Text");
        ExternalBackupRow.Label = AppResources.Get("externalBackupTitle", "Text");
        ExternalBackupRemoveButton.Content = AppResources.Get("externalBackupRemove", "Content");
        ExternalBackupLastSuccessRow.Label =
            AppResources.Get("externalBackupLastSuccess", "Text");
        BackupScheduleRow.Label = AppResources.Get("backupScheduleLabel", "Text");
        BackupScheduleManualItem.Content = AppResources.Get("backupScheduleManual", "Content");
        BackupScheduleTerminationItem.Content =
            AppResources.Get("backupScheduleTermination", "Content");
        BackupScheduleDailyItem.Content = AppResources.Get("backupScheduleDaily", "Content");
        BackupScheduleWeeklyItem.Content = AppResources.Get("backupScheduleWeekly", "Content");
        BackupLastAttemptRow.Label = AppResources.Get("backupLastAttempt", "Text");
        BackupLastSuccessRow.Label = AppResources.Get("backupLastSuccess", "Text");
        BackupVerificationRow.Label = AppResources.Get("backupVerification", "Text");
        BackupNowButton.Content = AppResources.Get("diskLibraryBackupNow", "Content");
        BackupBrowseButton.Content = AppResources.Get("diskLibraryBackupBrowse", "Content");
        BackupArchiveButton.Content = AppResources.Get("libraryArchiveCreate", "Content");
    }

    private void SynchronizeDiskTab(ShellPreferences preferences)
    {
        bool custom = preferences.Disk.LocationMode == DiskStorageLocationMode.Custom;
        DiskLocationPicker.SetSelected(preferences.Disk.LocationMode);
        foreach (var entry in DiskPathRows)
        {
            entry.Row.PathText = DiskStorageLocations.Abbreviate(entry.Read(diskStorage));
            entry.Row.CanChange = custom;
        }
        DiskResetRow.Visibility = custom ? Visibility.Visible : Visibility.Collapsed;
        DiskSection.Apply();

        ScanStorageLocationStatus status =
            ScanStorageLocationInspector.Inspect(diskStorage.Scans);
        DiskAvailableRow.ValueText = status.AvailableCapacityBytes is { } available
            ? FileBytesText(available)
            : AppResources.Get("scanStorageUnavailable", "Text");
        DiskStorageKindRow.ValueText = AppResources.Get(
            status.Kind == ScanStorageKind.CloudManaged
                ? "scanStorageCloudManaged"
                : "scanStorageLocal",
            "Text");

        LibraryBackupSettings backup = preferences.Backup;
        BackupFolderRow.ValueText = library?.StorageRoots is { } roots
            ? DiskStorageLocations.Abbreviate(roots.BackupRoot)
            : AppResources.Get("scanStorageUnavailable", "Text");
        ExternalBackupChooseButton.Content = AppResources.Get(
            backup.ExternalDestination.Length == 0 ? "externalBackupChoose" : "externalBackupChange",
            "Content");
        ExternalBackupRemoveButton.Visibility = backup.ExternalDestination.Length == 0
            ? Visibility.Collapsed
            : Visibility.Visible;
        ExternalBackupStatusLine.Text = ExternalBackupStatusText(backup);
        ExternalBackupLastSuccessRow.ValueText = DateText(backup.ExternalLastSuccessAt);
        BackupScheduleComboBox.SelectedIndex = (int)backup.Schedule;
        BackupLastAttemptRow.ValueText = DateText(backup.LastAttemptAt);
        BackupLastSuccessRow.ValueText = DateText(backup.LastSuccessAt);
        BackupVerificationRow.ValueText = backup.LastRestoreDrillSucceeded is { } passed
            ? AppResources.Get(passed ? "backupPassed" : "backupFailed", "Text")
            : AppResources.Get("backupNever", "Text");
        BackupVerificationRow.Reason = backup.LastRestoreDrillGeneration.Length == 0
            ? string.Empty
            : $"{AppResources.Get("backupGeneration", "Text")} {backup.LastRestoreDrillGeneration}";
        DiskBackupSection.Apply();
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
        if (isUpdating || DiskLocationPicker.SelectedValue is not DiskStorageLocationMode mode)
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
            DiskLocationPicker.SetSelected(state.Current.Disk.LocationMode);
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

    private void OnDiskResetPathsClick(object sender, RoutedEventArgs args)
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
        DiskThumbnailCacheSize.Text = AppResources.Get("diskCacheSizeCalculating", "Text");
        string directory = diskStorage.Thumbnails;
        _ = MeasureThumbnailCacheAsync(directory);
    }

    private async Task MeasureThumbnailCacheAsync(string directory)
    {
        long bytes = await Task.Run(
            () => Negaflow.Shell.Library.ThumbnailDiskCache.DirectorySize(directory));
        DiskThumbnailCacheSize.Text = FileBytesText(bytes);
    }

    private async void OnClearThumbnailCacheClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        DiskClearThumbnailCacheButton.IsEnabled = false;
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
            DiskClearThumbnailCacheButton.IsEnabled = true;
        }
    }

    private void OnBackupScheduleChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating || BackupScheduleComboBox.SelectedIndex < 0)
        {
            return;
        }
        var schedule = (LibraryBackupSchedule)BackupScheduleComboBox.SelectedIndex;
        workspaceState?.UpdateBackup(backup => backup with { Schedule = schedule });
    }

    private async void OnBackupNowClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (library is not { } host)
        {
            return;
        }
        BackupNowButton.IsEnabled = false;
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
            BackupNowButton.IsEnabled = true;
        }
    }

    private void OnBrowseBackupsClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (library?.StorageRoots is { } roots)
        {
            RevealFolder(roots.BackupRoot);
        }
    }

    private async void OnChooseExternalBackupClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (await PickFolderAsync() is { } chosen)
        {
            workspaceState?.UpdateBackup(backup => backup with { ExternalDestination = chosen });
        }
    }

    private void OnRemoveExternalBackupClick(object sender, RoutedEventArgs args)
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
    private async void OnCreateArchiveClick(object sender, RoutedEventArgs args)
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
        BackupArchiveButton.IsEnabled = false;
        try
        {
            DateTimeOffset now = DateTimeOffset.Now;
            _ = await Task.Run(() => LibraryArchiveWriter.Write(roots, destination, now));
        }
        finally
        {
            BackupArchiveButton.IsEnabled = true;
        }
    }
}
