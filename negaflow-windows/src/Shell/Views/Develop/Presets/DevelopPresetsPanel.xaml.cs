using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Presets;

/// <summary>
/// 복사/붙여넣기와 사용자 프리셋 패널입니다. recipe 가 통째로 바뀌면
/// <see cref="RecipeReplaced"/> 로 뷰가 인스펙터와 미리보기를 맞춥니다.
/// </summary>
public sealed partial class DevelopPresetsPanel : UserControl
{
    private DevelopPanelState? panel;

    public DevelopPresetsPanel() => InitializeComponent();

    public event EventHandler? RecipeReplaced;

    public void Bind(DevelopPanelState hostPanel)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        panel = hostPanel;
    }

    private void OnCopyDevelopSettingsClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel?.CopyDevelopSettings() == true)
        {
            Update();
        }
    }

    private void OnPasteDevelopSettingsClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || panel.PasteDevelopSettings() != LibraryFrameError.None)
        {
            return;
        }
        _ = panel.Save();
        RecipeReplaced?.Invoke(this, EventArgs.Empty);
    }

    private void OnPasteScopeAllClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null)
        {
            return;
        }
        panel.PasteScope = DevelopSettingsPasteScope.All;
        Update();
    }

    private void OnPasteScopeToggled(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (panel is null || sender is not ToggleMenuFlyoutItem { Tag: string group } item)
        {
            return;
        }
        DevelopSettingsPasteScope scope = panel.PasteScope;
        panel.PasteScope = group switch
        {
            "Base" => scope with { Base = item.IsChecked },
            "Tone" => scope with { Tone = item.IsChecked },
            "Color" => scope with { Color = item.IsChecked },
            "Detail" => scope with { Detail = item.IsChecked },
            "Geometry" => scope with { Geometry = item.IsChecked },
            _ => scope,
        };
        Update();
    }

    private void OnUserPresetSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateUserPresetButtons();
    }

    private void OnSaveUserPresetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null)
        {
            return;
        }
        string name = AppResources.FormatIntegers(
            "developUserPresetNameFormat",
            "Value",
            panel.UserPresets.Count + 1);
        if (panel.SaveUserPreset(name) is not { } saved)
        {
            return;
        }
        // 방금 저장한 것을 고른 상태로 둡니다 — macOS 도 저장 직후 그 프리셋을 가리킵니다.
        Update(saved.Id);
    }

    private void OnApplyUserPresetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null ||
            SelectedUserPresetId() is not { } id ||
            panel.ApplyUserPreset(id) != LibraryFrameError.None)
        {
            return;
        }
        _ = panel.Save();
        RecipeReplaced?.Invoke(this, EventArgs.Empty);
    }

    private void OnDeleteUserPresetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || SelectedUserPresetId() is not { } id || !panel.DeleteUserPreset(id))
        {
            return;
        }
        Update();
    }

    private Guid? SelectedUserPresetId() =>
        UserPresetSelector.SelectedItem is ComboBoxItem { Tag: Guid id } ? id : null;

    public void Update(Guid? select = null)
    {
        if (PasteScopeButton is null)
        {
            return;
        }

        CopyPasteSectionText.Text = AppResources.Get("developCopyPaste", "Text");
        UserPresetSectionText.Text = AppResources.Get("developUserPreset", "Text");
        UserPresetLabel.Text = AppResources.Get("developUserPreset", "Text");
        PasteScopeLabel.Text = AppResources.Get("developPasteScope", "Text");
        CopyDevelopSettingsButton.Content = AppResources.Get("developCopy", "Content");
        PasteDevelopSettingsButton.Content = AppResources.Get("developPaste", "Content");
        SaveUserPresetButton.Content = AppResources.Get("developUserPresetSave", "Content");
        ApplyUserPresetButton.Content = AppResources.Get("developUserPresetApply", "Content");
        DeleteUserPresetButton.Content = AppResources.Get("developUserPresetDelete", "Content");
        PasteScopeAllItem.Text = AppResources.Get("developPasteScopeAll", "Text");
        PasteScopeBaseItem.Text = AppResources.Get("developScopeBase", "Text");
        PasteScopeToneItem.Text = AppResources.Get("developScopeTone", "Text");
        PasteScopeColorItem.Text = AppResources.Get("developScopeColor", "Text");
        PasteScopeDetailItem.Text = AppResources.Get("developScopeDetail", "Text");
        PasteScopeGeometryItem.Text = AppResources.Get("developScopeGeometry", "Text");
        AutomationProperties.SetHelpText(
            CopyDevelopSettingsButton, AppResources.Get("developCopyHelp", "Value"));
        AutomationProperties.SetHelpText(
            PasteDevelopSettingsButton, AppResources.Get("developPasteHelp", "Value"));
        AutomationProperties.SetHelpText(
            PasteScopeButton, AppResources.Get("developPasteScopeHelp", "Value"));
        AutomationProperties.SetHelpText(
            SaveUserPresetButton, AppResources.Get("developUserPresetSaveHelp", "Value"));
        AutomationProperties.SetHelpText(
            ApplyUserPresetButton, AppResources.Get("developUserPresetApplyHelp", "Value"));
        AutomationProperties.SetHelpText(
            DeleteUserPresetButton, AppResources.Get("developUserPresetDeleteHelp", "Value"));

        DevelopSettingsPasteScope scope = panel?.PasteScope ?? DevelopSettingsPasteScope.All;
        PasteScopeBaseItem.IsChecked = scope.Base;
        PasteScopeToneItem.IsChecked = scope.Tone;
        PasteScopeColorItem.IsChecked = scope.Color;
        PasteScopeDetailItem.IsChecked = scope.Detail;
        PasteScopeGeometryItem.IsChecked = scope.Geometry;
        PasteScopeButton.Content = DescribePasteScope(scope);

        CopyDevelopSettingsButton.IsEnabled = panel?.SelectedFrame is not null;
        PasteDevelopSettingsButton.IsEnabled =
            panel?.SelectedFrame is not null && panel.CopiedSettings is not null && !scope.IsEmpty;
        SaveUserPresetButton.IsEnabled = panel?.SelectedFrame is not null;

        Guid? keep = select ?? SelectedUserPresetId();
        IReadOnlyList<DevelopUserPreset> presets = panel?.UserPresets ?? [];
        List<ComboBoxItem> items = [];
        foreach (DevelopUserPreset preset in presets)
        {
            items.Add(new ComboBoxItem { Content = preset.Name, Tag = preset.Id });
        }
        UserPresetSelector.ItemsSource = items;
        UserPresetSelector.IsEnabled = items.Count != 0;
        if (items.Count == 0)
        {
            // macOS 는 목록이 비면 자리표시자 한 줄을 보여 주고 고를 수 없게 둡니다.
            UserPresetSelector.PlaceholderText =
                AppResources.Get("developUserPresetEmpty", "Text");
        }
        else
        {
            UserPresetSelector.SelectedItem =
                items.FirstOrDefault(item => (Guid)item.Tag! == keep) ?? items[^1];
        }
        UpdateUserPresetButtons();
    }

    private void UpdateUserPresetButtons()
    {
        bool hasSelection = SelectedUserPresetId() is not null;
        ApplyUserPresetButton.IsEnabled = hasSelection && panel?.SelectedFrame is not null;
        DeleteUserPresetButton.IsEnabled = hasSelection;
    }

    private static string DescribePasteScope(DevelopSettingsPasteScope scope) =>
        PasteScopeSummary.Describe(
            scope,
            new PasteScopeText(
                AppResources.Get("developPasteScopeAll", "Text"),
                AppResources.Get("developPasteScopeNone", "Text"),
                AppResources.Get("developScopeBase", "Text"),
                AppResources.Get("developScopeTone", "Text"),
                AppResources.Get("developScopeColor", "Text"),
                AppResources.Get("developScopeDetail", "Text"),
                AppResources.Get("developScopeGeometry", "Text")));
}
