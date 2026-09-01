using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// 설정 · 디스크 탭에서 백업 세대를 고르고 되돌리는 시트입니다. macOS
/// <c>LibraryRestoreBrowser</c> 이식본입니다.
/// </summary>
/// <remarks>
/// 백업을 부지런히 만들어 둬도 <b>앱 안에서 되돌릴 방법이 없었습니다.</b> 사용자는
/// 탐색기로 파일을 직접 옮겨야 했고, 그 방법을 앱이 알려 주지도 않았습니다.
/// <para>
/// 여기서는 <b>예약만</b> 합니다. 지금 열려 있는 카탈로그를 발밑에서 갈아 끼우지 않고,
/// 다음 열기에 적용합니다 — macOS 도 같은 차례입니다.
/// </para>
/// </remarks>
public sealed partial class SettingsRootView
{
    internal async void OnRestoreBackupClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (library is not { } host)
        {
            return;
        }

        ListView list = new()
        {
            SelectionMode = ListViewSelectionMode.Single,
            MaxHeight = 320,
        };
        AutomationProperties.SetAutomationId(list, "settings.disk.backup-generations");
        TextBlock emptyState = new()
        {
            Text = AppResources.Get("libraryBackupEmpty", "Text"),
            TextWrapping = TextWrapping.Wrap,
            HorizontalAlignment = HorizontalAlignment.Center,
            Visibility = Visibility.Collapsed,
        };
        TextBlock hint = new()
        {
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap,
        };
        Button refresh = new() { Content = AppResources.Get("libraryBackupRefresh", "Content") };
        Button cancelPending = new()
        {
            Content = AppResources.Get("libraryBackupCancelPending", "Content"),
        };
        Grid pendingRow = PendingRow(cancelPending);

        ContentDialog dialog = new()
        {
            XamlRoot = XamlRoot,
            Title = AppResources.Get("diskLibraryBackupLabel", "Text"),
            Content = Body(list, emptyState, hint, refresh, pendingRow),
            PrimaryButtonText = AppResources.Get("libraryBackupScheduleRestore", "Content"),
            CloseButtonText = AppResources.Get("commonCancel", "Content"),
            DefaultButton = ContentDialogButton.Close,
        };

        void Reload()
        {
            LibraryBackupGenerationRow.Fill(list, host.BackupGenerations(), emptyState);
            pendingRow.Visibility = host.AttemptedRoots is { } roots &&
                CatalogRecovery.PendingRestoreGenerationId(roots) is not null
                    ? Visibility.Visible
                    : Visibility.Collapsed;
            UpdateSelectionHint(dialog, list, hint);
        }

        refresh.Click += (_, _) => Reload();
        cancelPending.Click += (_, _) =>
        {
            _ = host.CancelScheduledRestore();
            Reload();
        };
        list.SelectionChanged += (_, _) => UpdateSelectionHint(dialog, list, hint);
        Reload();

        if (await dialog.ShowAsync() != ContentDialogResult.Primary ||
            LibraryBackupGenerationRow.Selected(list) is not { } generation)
        {
            return;
        }
        if (!host.ScheduleRestore(generation.Id).IsSuccess)
        {
            await Notify(
                AppResources.Get("libraryBackupRestoreScheduleFailed", "Text"),
                AppResources.Get("libraryRecoveryUnusableBackupHint", "Text"));
            return;
        }
        // 예약은 다음 열기에 적용됩니다. 그 사실을 화면에 남겨야 사용자가 왜 아직
        // 그대로인지 압니다.
        await Notify(
            AppResources.Get("libraryBackupRestorePending", "Text"),
            AppResources.Get("libraryBackupRestoreConfirmMessage", "Text"));
    }

    /// <summary>
    /// 고르지 못하는 까닭을 항상 적습니다 — macOS 에서 QA 가 "복원 버튼이 안 눌린다" 고
    /// 신고한 것이 실은 "백업이 0 개라 고를 게 없어서" 였는데 화면에 설명이 없었습니다.
    /// </summary>
    private static void UpdateSelectionHint(ContentDialog dialog, ListView list, TextBlock hint)
    {
        CatalogBackupGeneration? selected = LibraryBackupGenerationRow.Selected(list);
        bool canRestore = selected?.IsRestorable == true;
        dialog.IsPrimaryButtonEnabled = canRestore;
        hint.Text = canRestore
            ? string.Empty
            : selected is null
                ? AppResources.Get("libraryRecoverySelectBackupHint", "Text")
                : AppResources.Get("libraryRecoveryUnusableBackupHint", "Text");
    }

    private static Grid PendingRow(Button cancelPending)
    {
        Grid row = new() { ColumnSpacing = 8, Visibility = Visibility.Collapsed };
        row.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = new GridLength(1, GridUnitType.Star),
        });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        TextBlock text = new()
        {
            Text = AppResources.Get("libraryBackupRestorePending", "Text"),
            TextWrapping = TextWrapping.Wrap,
            VerticalAlignment = VerticalAlignment.Center,
        };
        row.Children.Add(text);
        Grid.SetColumn(cancelPending, 1);
        row.Children.Add(cancelPending);
        return row;
    }

    private static StackPanel Body(
        ListView list,
        TextBlock emptyState,
        TextBlock hint,
        Button refresh,
        Grid pendingRow)
    {
        Grid header = new() { ColumnSpacing = 8 };
        header.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = new GridLength(1, GridUnitType.Star),
        });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(refresh, 1);
        header.Children.Add(refresh);

        StackPanel body = new() { Spacing = 12, MinWidth = 480 };
        body.Children.Add(header);
        body.Children.Add(list);
        body.Children.Add(emptyState);
        body.Children.Add(pendingRow);
        body.Children.Add(hint);
        return body;
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
