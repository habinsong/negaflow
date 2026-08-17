using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Library.Culling;

/// <summary>훑어보기 헤더 단추입니다. 판 배치와 다른 이유입니다.</summary>
internal sealed class LibraryCullingChrome
{
    private readonly LibraryCullingSurface view;
    private Button? gridButton;
    private Button? surveyButton;
    private Button? compareButton;
    private TextBlock? selectionCount;

    internal LibraryCullingChrome(LibraryCullingSurface view) => this.view = view;

    internal void Attach(
        Button grid,
        Button survey,
        Button compare,
        TextBlock count)
    {
        gridButton = grid;
        surveyButton = survey;
        compareButton = compare;
        selectionCount = count;
    }

    internal void Localize()
    {
        if (gridButton is null || surveyButton is null || compareButton is null)
        {
            return;
        }
        SetTooltip(gridButton, "libraryCullingGrid");
        SetTooltip(surveyButton, "libraryCullingSurvey");
        SetTooltip(compareButton, "libraryCullingCompare");
    }

    internal void Paint()
    {
        if (gridButton is null || surveyButton is null || compareButton is null)
        {
            return;
        }
        foreach ((Button button, LibraryCullingMode mode) in new[]
        {
            (gridButton, LibraryCullingMode.Grid),
            (surveyButton, LibraryCullingMode.Survey),
            (compareButton, LibraryCullingMode.Compare),
        })
        {
            bool isCurrent = view.mode == mode;
            button.Background = isCurrent
                ? new SolidColorBrush(Windows.UI.Color.FromArgb(0x1F, 0x80, 0x80, 0x80))
                : new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        }
    }

    internal void SetCountVisible(bool visible)
    {
        if (selectionCount is not null)
        {
            selectionCount.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    internal void SetCount(int count)
    {
        if (selectionCount is not null)
        {
            selectionCount.Text = count.ToString(System.Globalization.CultureInfo.CurrentCulture);
        }
    }

    private static void SetTooltip(Button button, string key)
    {
        string text = AppResources.Get(key, "Text");
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }
}
