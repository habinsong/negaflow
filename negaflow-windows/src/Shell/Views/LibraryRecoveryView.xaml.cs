using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// 카탈로그를 열지 못했을 때 사용자가 보는 유일한 화면입니다. macOS
/// <c>LibraryBlockedRecoveryView</c> 이식본입니다.
/// </summary>
/// <remarks>
/// 이 화면이 없던 동안 Windows 는 카탈로그가 손상돼도 <b>아무 말 없이 빈 라이브러리</b>를
/// 띄웠고, 사용자는 사진이 전부 사라졌다고 생각했습니다.
/// </remarks>
public sealed partial class LibraryRecoveryView : UserControl
{
    private LibraryHostService? host;
    private IReadOnlyList<CatalogBackupGeneration> generations = [];
    private bool isWorking;

    public LibraryRecoveryView()
    {
        InitializeComponent();
        LocalizedElement.Track(this, Localize);
    }

    /// <summary>라이브러리가 열렸습니다. 창이 이 화면을 걷고 셸을 세웁니다.</summary>
    public event EventHandler? Recovered;

    public void Attach(LibraryHostService attached)
    {
        ArgumentNullException.ThrowIfNull(attached);
        host = attached;
        Localize();
        Reload();
    }

    private void Localize()
    {
        TitleText.Text = AppResources.Get("libraryRecoveryTitle", "Text");
        RetryButton.Content = AppResources.Get("libraryRecoveryRetry", "Content");
        RevealButton.Content = AppResources.Get("showInExplorer", "Value");
        CopyDiagnosticsButton.Content =
            AppResources.Get("libraryRecoveryCopyDiagnostics", "Content");
        BackupSectionText.Text = AppResources.Get("diskLibraryBackupLabel", "Text");
        string refresh = AppResources.Get("libraryBackupRefresh", "Content");
        ToolTipService.SetToolTip(RefreshButton, refresh);
        AutomationProperties.SetName(RefreshButton, refresh);
        StartFreshButton.Content = AppResources.Get("libraryRecoveryStartFresh", "Content");
        RestoreButton.Content = AppResources.Get("libraryBackupRestoreSelected", "Content");
        CancelPendingButton.Content = AppResources.Get("libraryBackupCancelPending", "Content");
        PendingRestoreText.Text = AppResources.Get("libraryBackupRestorePending", "Text");
        ReasonText.Text = ReasonForBlock();
        CatalogPathText.Text = host?.AttemptedRoots?.CatalogPath ?? string.Empty;
        RenderGenerations();
    }

    /// <summary>
    /// 왜 못 열었는지입니다. 판정 코드가 있으면 코드까지 붙입니다 — "안전하게 열 수
    /// 없었습니다" 한 줄만으로는 지원 요청에서 원인을 좁힐 수 없습니다.
    /// </summary>
    private string ReasonForBlock()
    {
        string blocked = AppResources.Get("libraryCatalogBlockedStatus", "Text");
        if (host is not { } open)
        {
            return blocked;
        }
        List<string> codes = [];
        if (open.SessionError != CatalogSessionError.None)
        {
            codes.Add(open.SessionError.ToString());
        }
        if (open.StoreError != CatalogStoreError.None)
        {
            codes.Add(open.StoreError.ToString());
        }
        if (open.DefectSidecarError != DefectSidecarError.None)
        {
            codes.Add(open.DefectSidecarError.ToString());
        }
        return codes.Count == 0 ? blocked : $"{blocked} ({string.Join(" · ", codes)})";
    }

    private void Reload()
    {
        generations = host?.BackupGenerations() ?? [];
        RenderGenerations();
        string? pending = host?.AttemptedRoots is { } roots
            ? CatalogRecovery.PendingRestoreGenerationId(roots)
            : null;
        PendingRestoreRow.Visibility = pending is null ? Visibility.Collapsed : Visibility.Visible;
        UpdateActions();
    }

    private void RenderGenerations()
    {
        EmptyStateText.Text = AppResources.Get("libraryRecoveryNoBackupsHint", "Text");
        LibraryBackupGenerationRow.Fill(GenerationList, generations, EmptyStateText);
    }


    private CatalogBackupGeneration? SelectedGeneration =>
        LibraryBackupGenerationRow.Selected(GenerationList);

    private void UpdateActions()
    {
        bool canRestore = SelectedGeneration?.IsRestorable == true;
        RestoreButton.IsEnabled = canRestore && !isWorking;
        StartFreshButton.IsEnabled = !isWorking;
        RetryButton.IsEnabled = !isWorking;
        RefreshButton.IsEnabled = !isWorking;
        CancelPendingButton.IsEnabled = !isWorking;
        // 왜 못 누르는지를 항상 적습니다 - macOS 에서 QA 가 "복원 버튼이 안 눌린다" 고
        // 신고한 것이 실은 "고를 백업이 없어서" 였는데, 화면에 아무 설명이 없었습니다.
        RestoreHintText.Text = canRestore
            ? string.Empty
            : SelectedGeneration is null
                ? AppResources.Get("libraryRecoverySelectBackupHint", "Text")
                : AppResources.Get("libraryRecoveryUnusableBackupHint", "Text");
        ToolTipService.SetToolTip(
            RestoreButton,
            RestoreHintText.Text.Length == 0 ? null : RestoreHintText.Text);
    }

    private void OnGenerationSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateActions();
    }

    private void OnRefreshClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        Reload();
    }

    private void OnRetryClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (host is not { } open)
        {
            return;
        }
        if (open.RetryOpen() == LibraryHostState.Open)
        {
            Recovered?.Invoke(this, EventArgs.Empty);
            return;
        }
        Localize();
        Reload();
    }

    private void OnRevealClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (host?.AttemptedRoots is not { } roots)
        {
            return;
        }
        try
        {
            // 카탈로그 파일이 없을 수도 있으므로 그 폴더를 엽니다.
            using System.Diagnostics.Process? _ = System.Diagnostics.Process.Start(
                new System.Diagnostics.ProcessStartInfo(roots.LibraryRoot)
                {
                    UseShellExecute = true,
                });
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            System.ComponentModel.Win32Exception)
        {
            // 탐색기를 못 열어도 복구 화면은 그대로 있습니다.
        }
    }

    private void OnCopyDiagnosticsClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (host is not { } open)
        {
            return;
        }
        Windows.ApplicationModel.DataTransfer.DataPackage package = new();
        package.SetText(open.BuildRecoveryDiagnostics(
            typeof(LibraryRecoveryView).Assembly.GetName().Version?.ToString() ?? "0.0.0").Text);
        Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(package);
    }

    private async void OnRestoreClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (host is not { } open || SelectedGeneration is not { } generation)
        {
            return;
        }
        if (!await Confirm(
                AppResources.Get("libraryBackupRestoreConfirmTitle", "Text"),
                AppResources.Get("libraryBackupRestoreConfirmMessage", "Text"),
                AppResources.Get("libraryBackupRestoreSelected", "Content")))
        {
            return;
        }
        await RunAsync(() =>
        {
            if (!open.ScheduleRestore(generation.Id).IsSuccess)
            {
                return false;
            }
            return open.RetryOpen() == LibraryHostState.Open;
        },
        AppResources.Get("libraryBackupRestoreScheduleFailed", "Text"));
    }

    private async void OnStartFreshClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (host is not { } open)
        {
            return;
        }
        if (!await Confirm(
                AppResources.Get("libraryRecoveryStartFreshConfirmTitle", "Text"),
                AppResources.Get("libraryRecoveryStartFreshConfirmMessage", "Text"),
                AppResources.Get("libraryRecoveryStartFresh", "Content")))
        {
            return;
        }
        await RunAsync(
            open.StartFreshLibrary,
            AppResources.Get("libraryRecoveryStartFreshFailed", "Text"));
    }

    private async void OnCancelPendingClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (host is not { } open)
        {
            return;
        }
        await RunAsync(
            () =>
            {
                _ = open.CancelScheduledRestore();
                // 취소는 화면을 떠나지 않습니다 - 예약 줄만 사라집니다.
                return false;
            },
            failureMessage: null);
    }

    /// <summary>
    /// 디스크를 만지는 동안 단추를 잠그고, 끝나면 결과에 따라 화면을 걷거나 까닭을 알립니다.
    /// 실제 일은 <b>워커에서</b> 합니다 — 파일을 복사하므로 UI 스레드에서 하면 창이 멈춥니다.
    /// </summary>
    private async Task RunAsync(Func<bool> work, string? failureMessage)
    {
        isWorking = true;
        UpdateActions();
        bool recovered;
        try
        {
            recovered = await Task.Run(work);
        }
        finally
        {
            isWorking = false;
        }
        if (recovered)
        {
            Recovered?.Invoke(this, EventArgs.Empty);
            return;
        }
        Localize();
        Reload();
        if (failureMessage is { } message)
        {
            // 실패했으면 무엇이 그대로인지도 말합니다 - 제목만 띄우면 사용자는 지금 라이브러리가
            // 어떤 상태인지 알 수 없습니다.
            await Notify(message, ReasonForBlock());
        }
    }

    private async Task<bool> Confirm(string title, string message, string primary)
    {
        ContentDialog dialog = new()
        {
            XamlRoot = XamlRoot,
            Title = title,
            Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap },
            PrimaryButtonText = primary,
            CloseButtonText = AppResources.Get("commonCancel", "Content"),
            DefaultButton = ContentDialogButton.Close,
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    /// <summary>
    /// 이미 벌어진 일을 알립니다. <b>닫기 단추는 "완료" 입니다</b> — 알림에 "취소" 를 달면
    /// 사용자는 무엇이 취소되는지 알 수 없습니다.
    /// </summary>
    private async Task Notify(string title, string message)
    {
        ContentDialog dialog = new()
        {
            XamlRoot = XamlRoot,
            Title = title,
            Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap },
            CloseButtonText = AppResources.Get("commonDone", "Content"),
            DefaultButton = ContentDialogButton.Close,
        };
        _ = await dialog.ShowAsync();
    }
}
