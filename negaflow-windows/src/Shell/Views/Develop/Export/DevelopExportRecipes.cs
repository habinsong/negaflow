using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Export;

/// <summary>담아 둔 내보내기 설정 목록입니다. 패널 배치와 다른 이유로 바뀝니다.</summary>
internal sealed class DevelopExportRecipes
{
    private readonly DevelopExportPanel view;

    internal DevelopExportRecipes(DevelopExportPanel view) => this.view = view;

    internal void BuildExportRecipeMenu()
    {
        view.ExportRecipeFlyout.Items.Clear();
        var save = new MenuFlyoutItem
        {
            Text = AppResources.Get("developExportRecipeSaveCurrent", "Text"),
        };
        save.Click += (_, _) => view.SaveCurrentExportRecipe();
        view.ExportRecipeFlyout.Items.Add(save);
        if (view.exportRecipes.Selected is not { } selected)
        {
            return;
        }
        view.ExportRecipeFlyout.Items.Add(new MenuFlyoutSeparator());
        var rename = new MenuFlyoutItem
        {
            Text = AppResources.Get("libraryRename", "Content"),
        };
        rename.Click += (_, _) => view.RenameExportRecipe(selected);
        view.ExportRecipeFlyout.Items.Add(rename);
        var delete = new MenuFlyoutItem { Text = AppResources.Get("libraryDelete", "Content") };
        delete.Click += (_, _) =>
        {
            view.UpdateExportRecipes(library => library.Delete(selected.Id));
        };
        view.ExportRecipeFlyout.Items.Add(delete);
    }

    /// <summary>
    /// 담아 둔 내보내기 설정의 이름을 바꿉니다. 저장은 이름을 짓지 않고 "내보내기 설정 N" 을
    /// 붙이므로, 사용자가 자기 이름을 주는 자리는 여기뿐입니다.
    /// </summary>
    internal async Task RenameExportRecipe(ExportRecipe recipe)
    {
        TextBox field = new()
        {
            Text = recipe.Name,
            PlaceholderText = AppResources.Get("developExportRecipeName", "Text"),
        };
        AutomationProperties.SetName(field, field.PlaceholderText);
        AutomationProperties.SetAutomationId(field, "negaflow.develop.export.recipe-name");
        ContentDialog dialog = new()
        {
            XamlRoot = view.XamlRoot,
            Title = AppResources.Get("libraryRename", "Content"),
            Content = field,
            PrimaryButtonText = AppResources.Get("libraryRename", "Content"),
            CloseButtonText = AppResources.Get("commonCancel", "Content"),
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }
        // 빈 이름이나 공백뿐인 이름은 Rename 이 스스로 거절합니다 — 이름 없는 프리셋은
        // 목록에서 고를 수 없습니다.
        view.UpdateExportRecipes(library => library.Rename(recipe.Id, field.Text));
    }

    /// <summary>
    /// 이름은 파일명 패턴 칸이 아니라 macOS 처럼 "내보내기 설정 N" 으로 짓습니다. 사용자가
    /// 자기 이름을 주려면 메뉴의 이름 변경을 씁니다.
    /// </summary>
    internal void SaveCurrentExportRecipe()
    {
        string name = AppResources.FormatInteger(
            "developExportRecipeDefaultName",
            "Text",
            view.exportRecipes.NextDefaultIndex());
        view.UpdateExportRecipes(library => library.Save(name, view.exportSettings));
    }

    internal void UpdateExportRecipes(Func<ExportRecipeLibrary, ExportRecipeLibrary> update)
    {
        view.exportRecipes = update(view.exportRecipes).Normalize();
        view.workspaceState?.UpdateExportRecipes(_ => view.exportRecipes);
        view.SynchronizeExportControls();
    }

    internal void SynchronizeExportRecipeControls()
    {
        view.ExportRecipeSelector.Items.Clear();
        view.ExportRecipeSelector.Items.Add(new ComboBoxItem
        {
            Content = AppResources.Get("developExportRecipeEmpty", "Content"),
            Tag = null,
        });
        foreach (ExportRecipe recipe in view.exportRecipes.Recipes)
        {
            view.ExportRecipeSelector.Items.Add(new ComboBoxItem
            {
                Content = recipe.Name,
                Tag = recipe.Id,
            });
        }
        view.ExportRecipeSelector.SelectedIndex = 0;
        for (int index = 0; index < view.ExportRecipeSelector.Items.Count; ++index)
        {
            if (view.ExportRecipeSelector.Items[index] is ComboBoxItem candidate &&
                Equals(candidate.Tag, view.exportRecipes.SelectedId))
            {
                view.ExportRecipeSelector.SelectedIndex = index;
                break;
            }
        }
        view.BuildExportRecipeMenu();
    }
}
