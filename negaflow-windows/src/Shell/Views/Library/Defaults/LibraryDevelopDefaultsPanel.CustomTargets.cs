using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Windows.System;

namespace Negaflow.Shell.Views.Library.Defaults;

public sealed partial class LibraryDevelopDefaultsPanel
{
    private readonly Dictionary<DevelopTarget, Button> customButtons = [];
    private Flyout? customFlyout;
    private string? customFrameId;

    private void BuildCustomTargetPicker()
    {
        if (customFlyout is not null) { return; }
        Grid grid = new() { ColumnSpacing = 4, RowSpacing = 3, Padding = new Thickness(4) };
        AutomationProperties.SetAutomationId(grid, "negaflow.custom.palette");
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        int row = 0;
        foreach (IReadOnlyList<DevelopTarget> group in DevelopTargets.CustomGroups)
        {
            if (row > 0)
            {
                grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                MenuFlyoutSeparator separator = new() { IsTabStop = false };
                Grid.SetRow(separator, row++);
                Grid.SetColumnSpan(separator, 2);
                grid.Children.Add(separator);
            }
            for (int index = 0; index < group.Count; index += 2)
            {
                grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                for (int column = 0; column < 2 && index + column < group.Count; ++column)
                {
                    DevelopTarget target = group[index + column];
                    Button button = new()
                    {
                        Tag = target,
                        HorizontalAlignment = HorizontalAlignment.Stretch,
                        HorizontalContentAlignment = HorizontalAlignment.Left,
                        MinHeight = 30,
                        Padding = new Thickness(6, 3, 6, 3),
                        FontSize = 12,
                    };
                    AutomationProperties.SetAutomationId(button, "negaflow.custom.target." + DevelopTargets.CustomId(target));
                    AutomationProperties.SetName(button, DevelopTargets.DisplayName(target));
                    button.Click += (_, _) =>
                    {
                        if (ActionableFrame is not { } frame || frame.Id != customFrameId) { return; }
                        customFlyout?.Hide();
                        if (frame.DevelopTarget != target) { ApplyDevelopTarget(target); }
                    };
                    button.KeyDown += OnCustomTargetKeyDown;
                    Grid.SetRow(button, row);
                    Grid.SetColumn(button, column);
                    grid.Children.Add(button);
                    customButtons.Add(target, button);
                }
                ++row;
            }
        }
        customFlyout = new Flyout
        {
            Content = new ScrollViewer
            {
                Content = grid,
                Width = 344,
                MaxHeight = 390,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            },
        };
        customFlyout.Opening += (_, _) =>
        {
            customFrameId = ActionableFrame?.Id;
            RefreshCustomButtons();
        };
        customFlyout.Opened += (_, _) =>
        {
            if (ActionableFrame is { } frame && customButtons.TryGetValue(frame.DevelopTarget, out Button? button))
            {
                button.Focus(FocusState.Programmatic);
            }
        };
        CustomTargetButton.Flyout = customFlyout;
    }

    private void SynchronizeCustomTarget(LibraryFrameSnapshot? frame)
    {
        BuildCustomTargetPicker();
        if (customFrameId != frame?.Id || !DevelopTargets.IsCustom(frame?.DevelopTarget ?? DevelopTarget.Main))
        {
            customFlyout?.Hide();
        }
        CustomTargetButton.IsEnabled = frame is not null && libraryHost is not null;
        CustomTargetName.Text = DevelopTargets.DisplayName(frame?.DevelopTarget ?? DevelopTarget.Emulsion);
        AutomationProperties.SetName(CustomTargetButton, AppResources.Get("customTarget", "Text") + ": " + CustomTargetName.Text);
        RefreshCustomButtons();
    }

    private void RefreshCustomButtons()
    {
        foreach ((DevelopTarget target, Button button) in customButtons)
        {
            AutomationProperties.SetItemStatus(button,
                AppResources.Get(ActionableFrame?.DevelopTarget == target ? "selected" : "notSelected", "Value"));
            Grid content = new() { ColumnSpacing = 6 };
            content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(14) });
            content.ColumnDefinitions.Add(new ColumnDefinition());
            FontIcon check = new() { Glyph = "\uE73E", FontSize = 12,
                Opacity = ActionableFrame?.DevelopTarget == target ? 1 : 0 };
            TextBlock label = new() { Text = DevelopTargets.DisplayName(target), TextTrimming = TextTrimming.CharacterEllipsis };
            Grid.SetColumn(label, 1);
            content.Children.Add(check);
            content.Children.Add(label);
            button.Content = content;
        }
    }

    private void OnCustomTargetKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (sender is not Button { Tag: DevelopTarget target }) { return; }
        (int horizontal, int vertical) = args.Key switch
        {
            VirtualKey.Left => (-1, 0), VirtualKey.Right => (1, 0),
            VirtualKey.Up => (0, -1), VirtualKey.Down => (0, 1), _ => (0, 0),
        };
        if (horizontal == 0 && vertical == 0) { return; }
        DevelopTarget next = DevelopTargets.MoveCustomSelection(target, horizontal, vertical);
        if (customButtons.TryGetValue(next, out Button? button)) { button.Focus(FocusState.Keyboard); }
        args.Handled = true;
    }
}
