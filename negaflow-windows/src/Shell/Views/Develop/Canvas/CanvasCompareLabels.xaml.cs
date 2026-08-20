using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Canvas;

/// <summary>macOS <c>CanvasCompareLabels</c>.</summary>
public sealed partial class CanvasCompareLabels : UserControl
{
    private CanvasCompareState? compare;
    private Action<string>? selectBefore;
    private Action? selectCurrent;
    private string mainLabel = "MAIN";
    private string uneditedLabel = "Unedited";
    private string rawLabel = "Raw";
    private string photoLabel = "Photo";
    private IReadOnlyList<CanvasCompareBeforeOption> frames = [];

    public CanvasCompareLabels()
    {
        InitializeComponent();
    }

    public void Bind(
        CanvasCompareState state,
        Action<string> onSelectBefore,
        Action onSelectCurrent)
    {
        ArgumentNullException.ThrowIfNull(state);
        ArgumentNullException.ThrowIfNull(onSelectBefore);
        ArgumentNullException.ThrowIfNull(onSelectCurrent);
        compare = state;
        selectBefore = onSelectBefore;
        selectCurrent = onSelectCurrent;
        RebuildMenu();
        Refresh();
    }

    public void Localize()
    {
        mainLabel = DevelopTargets.DisplayName(DevelopTarget.Main);
        uneditedLabel = AppResources.Get("canvasCompareUnedited", "Text");
        rawLabel = AppResources.Get("canvasCompareRaw", "Text");
        photoLabel = AppResources.Get("canvasComparePhoto", "Text");
        AfterText.Text = AppResources.Get("canvasCompareCurrentImage", "Text");
        string help = AppResources.Get("canvasCompareBeforeSourceHelp", "Text");
        AutomationProperties.SetName(BeforeButton, help);
        ToolTipService.SetToolTip(BeforeButton, help);
        AutomationProperties.SetName(AfterButton, AfterText.Text);
        ToolTipService.SetToolTip(AfterButton, AfterText.Text);
        RebuildMenu();
        Refresh();
    }

    public void SetFrameOptions(IReadOnlyList<CanvasCompareBeforeOption> options)
    {
        frames = options;
        RebuildMenu();
        Refresh();
    }

    public void Place(PreviewFrame frame, CanvasCompareOrientation orientation)
    {
        (double beforeX, double beforeY) = CanvasCompareBeforePolicy.BeforeCenter(frame.Left, frame.Top);
        (double afterX, double afterY) = CanvasCompareBeforePolicy.AfterCenter(
            frame.Left,
            frame.Top,
            frame.Width,
            frame.Height,
            orientation);
        double beforeW = BeforeButton.ActualWidth > 0 ? BeforeButton.ActualWidth : 80;
        double beforeH = BeforeButton.ActualHeight > 0 ? BeforeButton.ActualHeight : 22;
        double afterW = AfterButton.ActualWidth > 0 ? AfterButton.ActualWidth : 80;
        double afterH = AfterButton.ActualHeight > 0 ? AfterButton.ActualHeight : 22;
        BeforeButton.Margin = new Thickness(beforeX - (beforeW / 2), beforeY - (beforeH / 2), 0, 0);
        AfterButton.Margin = new Thickness(afterX - (afterW / 2), afterY - (afterH / 2), 0, 0);
    }

    public void Refresh()
    {
        if (compare is null)
        {
            return;
        }

        IReadOnlyList<CanvasCompareBeforeOption> primary = CanvasCompareBeforePolicy.PrimaryOptions(
            mainLabel,
            uneditedLabel,
            rawLabel);
        BeforeText.Text = CanvasCompareBeforePolicy.BeforeLabel(
            compare.SelectedBeforeId,
            primary,
            frames,
            uneditedLabel);
    }

    private void RebuildMenu()
    {
        BeforeMenu.Items.Clear();
        MenuFlyoutItem header = new()
        {
            Text = AppResources.Get("canvasCompareBefore", "Text"),
            IsEnabled = false,
        };
        BeforeMenu.Items.Add(header);
        foreach (CanvasCompareBeforeOption option in CanvasCompareBeforePolicy.PrimaryOptions(
                     mainLabel,
                     uneditedLabel,
                     rawLabel))
        {
            BeforeMenu.Items.Add(MenuItem(option));
        }

        if (frames.Count == 0)
        {
            return;
        }

        MenuFlyoutSubItem photos = new() { Text = photoLabel };
        foreach (CanvasCompareBeforeOption option in frames)
        {
            photos.Items.Add(MenuItem(option));
        }

        BeforeMenu.Items.Add(photos);
    }

    private MenuFlyoutItem MenuItem(CanvasCompareBeforeOption option)
    {
        MenuFlyoutItem item = new() { Text = option.Label, Tag = option.Id };
        if (compare is not null && option.Id == compare.SelectedBeforeId)
        {
            item.Icon = new FontIcon { Glyph = "\uE73E" };
        }

        item.Click += (_, _) => selectBefore?.Invoke(option.Id);
        return item;
    }

    private void OnBeforeClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
    }

    private void OnAfterClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        selectCurrent?.Invoke();
    }
}
