using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>인스펙터 아코디언 한 칸의 펼침 표시와 제목·되돌리기 이름을 맞춥니다.</summary>
internal static class DevelopInspectorSectionChrome
{
    public static void Apply(
        DisclosureButton header,
        FontIcon chevron,
        FrameworkElement content,
        bool isExpanded)
    {
        header.IsExpanded = isExpanded;
        chevron.Glyph = isExpanded ? "\uE70D" : "\uE76C";
        content.Visibility = isExpanded ? Visibility.Visible : Visibility.Collapsed;
    }

    public static void Localize(
        FrameworkElement section,
        ButtonBase headerButton,
        TextBlock titleText,
        Button resetButton,
        string title)
    {
        titleText.Text = title;
        AutomationProperties.SetName(section, title);
        SetNameAndTooltip(headerButton, title);
        string resetName = AppResources.Get("developResetSectionFormat", "Value")
            .Replace("%@", title, StringComparison.Ordinal);
        SetNameAndTooltip(resetButton, resetName);
    }

    public static void SetNameAndTooltip(ButtonBase button, string text)
    {
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    public static void SetButtonText(Button button, string text)
    {
        button.Content = text;
        SetNameAndTooltip(button, text);
    }

    public static void SetToggleText(ToggleButton toggle, string text)
    {
        toggle.Content = text;
        SetNameAndTooltip(toggle, text);
    }
}
