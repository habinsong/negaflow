using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// 백업 세대 한 줄입니다. 복구 화면과 설정 · 디스크 탭이 <b>같은 줄</b>을 씁니다 —
/// 두 자리가 다르게 보이면 사용자는 다른 목록이라고 생각합니다.
/// macOS <c>LibraryBackupGenerationRow</c> 이식본이며 세 칸의 차례가 같습니다.
/// </summary>
internal static class LibraryBackupGenerationRow
{
    /// <summary>세대 목록을 <see cref="ListView"/> 에 채우고 고른 것을 되살립니다.</summary>
    internal static void Fill(
        ListView list,
        IReadOnlyList<CatalogBackupGeneration> generations,
        TextBlock emptyState)
    {
        string? previousId = Selected(list)?.Id;
        list.Items.Clear();
        foreach (CatalogBackupGeneration generation in generations)
        {
            list.Items.Add(new ListViewItem
            {
                Content = Build(generation),
                Tag = generation,
                // 복원할 수 없는 세대는 고를 수 없습니다. 왜 안 되는지는 부르는 쪽이 적습니다.
                IsEnabled = generation.IsRestorable,
            });
        }
        if (previousId is { } id)
        {
            foreach (object item in list.Items)
            {
                if (item is ListViewItem { Tag: CatalogBackupGeneration candidate } &&
                    string.Equals(candidate.Id, id, StringComparison.Ordinal))
                {
                    list.SelectedItem = item;
                    break;
                }
            }
        }
        bool empty = generations.Count == 0;
        list.Visibility = empty ? Visibility.Collapsed : Visibility.Visible;
        emptyState.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
    }

    internal static CatalogBackupGeneration? Selected(ListView list) =>
        list.SelectedItem is ListViewItem { Tag: CatalogBackupGeneration generation }
            ? generation
            : null;

    private static Grid Build(CatalogBackupGeneration generation)
    {
        Grid row = new() { ColumnSpacing = 12, Padding = new Thickness(0, 3, 0, 3) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = new GridLength(1, GridUnitType.Star),
        });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        FontIcon icon = new()
        {
            FontSize = 14,
            // Segoe Fluent Icons: 검증됨은 Accept(E73E), 아니면 Warning(E7BA) 입니다.
            Glyph = generation.IsRestorable ? "" : "",
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(icon, 0);
        row.Children.Add(icon);

        StackPanel text = new() { Spacing = 3 };
        text.Children.Add(new TextBlock { Text = DateText(generation.CreatedAt) });
        text.Children.Add(new TextBlock
        {
            FontSize = 11,
            Text = AppResources.FormatIntegers(
                "libraryBackupCountsFormat",
                "Text",
                generation.FrameCount ?? 0,
                generation.DefectRecipeCount ?? 0),
        });
        Grid.SetColumn(text, 1);
        row.Children.Add(text);

        TextBlock state = new()
        {
            FontSize = 11,
            Text = StateText(generation.State),
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(state, 2);
        row.Children.Add(state);

        AutomationProperties.SetAutomationId(row, "negaflow.recovery.generation");
        AutomationProperties.SetName(
            row,
            $"{DateText(generation.CreatedAt)} {StateText(generation.State)}");
        return row;
    }

    internal static string DateText(DateTimeOffset? created) =>
        created is { } value
            ? value.ToLocalTime().ToString("g", CultureInfo.CurrentCulture)
            : AppResources.Get("libraryBackupUnknownDate", "Text");

    /// <summary>
    /// Windows 검증은 전부 맞거나 아니거나입니다. 매니페스트조차 못 읽은 세대도 사용자에게는
    /// "손상됨" 이 사실이고, 어느 쪽이었는지는 진단에 남습니다.
    /// </summary>
    internal static string StateText(CatalogBackupGenerationState state) =>
        state == CatalogBackupGenerationState.Verified
            ? AppResources.Get("libraryBackupChecksummed", "Text")
            : AppResources.Get("libraryBackupDamaged", "Text");
}
