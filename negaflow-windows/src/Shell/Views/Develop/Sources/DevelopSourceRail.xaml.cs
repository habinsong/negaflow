using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Sources;

/// <summary>macOS <c>WorkflowSidebarTab</c>과 같은 현상 왼쪽 소스 레일입니다.</summary>
public sealed partial class DevelopSourceRail : UserControl
{
    public DevelopSourceRail() => InitializeComponent();

    public event EventHandler<WorkflowSidebarTab>? TabClicked;

    public void Localize()
    {
        SetNameAndTooltip(LibraryRailButton, "sidebarLibrary");
        SetNameAndTooltip(FilesRailButton, "sidebarFiles");
        SetNameAndTooltip(VersionsRailButton, "sidebarVersions");
        SetNameAndTooltip(PresetsRailButton, "sidebarPresets");
        SetNameAndTooltip(FilmRailButton, "sidebarFilm");
        SetNameAndTooltip(OutputRailButton, "sidebarOutput");
        SetLocalizedNameAndTooltip(LibraryRailButton, AppResources.Get("developLibrary", "Text"));
        SetLocalizedNameAndTooltip(VersionsRailButton, AppResources.Get("developSectionVersions", "Text"));
        SetLocalizedNameAndTooltip(FilmRailButton, AppResources.Get("developSectionFilm", "Text"));
        SetLocalizedNameAndTooltip(OutputRailButton, AppResources.Get("developSectionOutput", "Text"));
    }

    public void SetCompact(bool compact)
    {
        Rail.Padding = compact
            ? new Thickness(8, 10, 8, 0)
            : new Thickness(22, 10, 22, 0);
    }

    public void SetSelected(WorkflowSidebarTab selected)
    {
        var accent = (Brush)Application.Current.Resources["AccentTextFillColorPrimaryBrush"];
        var normal = (Brush)Application.Current.Resources["TextFillColorPrimaryBrush"];
        var selection = (Brush)Application.Current.Resources["NegaflowSelectionBrush"];
        foreach ((Button button, FrameworkElement icon, WorkflowSidebarTab kind) in Buttons())
        {
            bool isSelected = kind == selected;
            button.Background = isSelected
                ? selection
                : new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            SetIconForeground(icon, isSelected ? accent : normal);
            AutomationProperties.SetItemStatus(
                button,
                AppResources.Get(isSelected ? "selected" : "notSelected", "Value"));
        }
    }

    private void OnRailClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not Button { Tag: string tag } ||
            !Enum.TryParse(tag, out WorkflowSidebarTab kind))
        {
            return;
        }
        TabClicked?.Invoke(this, kind);
    }

    // 아이콘 형식을 `Control` 로 둡니다. Segoe 에 뜻이 맞는 글리프가 없는 자리는
    // 직접 그린 `VectorIcon` 이라 `FontIcon` 으로 묶으면 컴파일이 안 됩니다.
    // 여기서 쓰는 것은 `Foreground` 하나뿐이라 공통 기반형으로 충분합니다.
    // `FontIcon` 은 `IconElement`, 직접 그린 `VectorIcon` 은 `Control` 이라 공통 기반이
    // `FrameworkElement` 뿐입니다. 거기에는 `Foreground` 가 없어 형식을 갈라 넣습니다.
    private static void SetIconForeground(FrameworkElement icon, Brush brush)
    {
        switch (icon)
        {
            case FontIcon font:
                font.Foreground = brush;
                break;
            case Control control:
                control.Foreground = brush;
                break;
        }
    }

    private IEnumerable<(Button Button, FrameworkElement Icon, WorkflowSidebarTab Kind)> Buttons()
    {
        yield return (LibraryRailButton, LibraryRailIcon, WorkflowSidebarTab.Library);
        yield return (FilesRailButton, FilesRailIcon, WorkflowSidebarTab.Files);
        yield return (VersionsRailButton, VersionsRailIcon, WorkflowSidebarTab.Versions);
        yield return (PresetsRailButton, PresetsRailIcon, WorkflowSidebarTab.Presets);
        yield return (FilmRailButton, FilmRailIcon, WorkflowSidebarTab.Film);
        yield return (OutputRailButton, OutputRailIcon, WorkflowSidebarTab.Output);
    }

    private static void SetNameAndTooltip(Button button, string resourceKey)
    {
        string text = AppResources.Get(resourceKey, "Value");
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    private static void SetLocalizedNameAndTooltip(Button button, string text)
    {
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }
}
