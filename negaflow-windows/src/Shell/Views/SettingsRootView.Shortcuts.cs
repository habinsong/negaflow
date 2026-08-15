using Microsoft.UI.Input;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Shortcuts;
using Windows.System;
using Windows.UI.Core;

namespace Negaflow.Shell.Views;

/// <summary>
/// 설정의 단축키 표입니다. macOS <c>WorkflowShortcutsSettingsSection</c> 과 같은 세 덩이입니다 —
/// 묶음 고르개, 그 묶음의 명령 표, 전체 초기화.
/// </summary>
public sealed partial class SettingsRootView
{
    private WorkflowShortcutGroup shortcutGroup = WorkflowShortcutGroup.Library;

    /// <summary>지금 키를 기다리는 줄입니다. 없으면 null 입니다.</summary>
    private WorkflowShortcutAction? recordingAction;

    /// <summary>방금 거절당한 줄입니다. 그 줄에만 빨간 안내가 붙습니다.</summary>
    private WorkflowShortcutAction? rejectedAction;

    private void BuildShortcutGroups()
    {
        ShortcutGroupBar.Children.Clear();
        foreach (WorkflowShortcutGroup group in Enum.GetValues<WorkflowShortcutGroup>())
        {
            WorkflowShortcutGroup value = group;
            Button button = new()
            {
                Content = GroupTitle(group),
                Padding = new Thickness(10, 4, 10, 4),
                FontSize = 12,
                CornerRadius = new CornerRadius(13),
            };
            button.Click += (_, _) =>
            {
                shortcutGroup = value;
                recordingAction = null;
                rejectedAction = null;
                BuildShortcutGroups();
                BuildShortcutRows();
            };
            SetSelectedLook(button, group == shortcutGroup);
            ShortcutGroupBar.Children.Add(button);
        }
    }

    private static void SetSelectedLook(Button button, bool selected)
    {
        button.Background = selected
            ? new SolidColorBrush(Windows.UI.Color.FromArgb(0x2D, 0x6B, 0x8B, 0xFF))
            : new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        button.FontWeight = selected ? FontWeights.SemiBold : FontWeights.Normal;
        button.Opacity = selected ? 1 : 0.72;
    }

    private void BuildShortcutRows()
    {
        ShortcutRows.Children.Clear();
        if (workspaceState is not { } state)
        {
            return;
        }
        WorkflowShortcutMap map = state.Current.Shortcuts;
        foreach (WorkflowShortcutAction action in WorkflowShortcutActions.All)
        {
            if (WorkflowShortcutActions.Group(action) != shortcutGroup)
            {
                continue;
            }
            ShortcutRows.Children.Add(ShortcutRow(action, map));
            if (rejectedAction == action)
            {
                ShortcutRows.Children.Add(new TextBlock
                {
                    Text = AppResources.Get("shortcutInvalidOrConflict", "Text"),
                    FontSize = 11,
                    Foreground = new SolidColorBrush(
                        Windows.UI.Color.FromArgb(0xFF, 0xE5, 0x48, 0x4D)),
                    TextWrapping = TextWrapping.Wrap,
                });
            }
        }
    }

    private Grid ShortcutRow(WorkflowShortcutAction action, WorkflowShortcutMap map)
    {
        Grid row = new() { ColumnSpacing = 8 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(180) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        TextBlock title = new()
        {
            Text = ActionTitle(action),
            FontSize = 13,
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis,
        };
        row.Children.Add(title);

        // 빼앗긴 단축키는 빈칸으로 보입니다. 남의 키를 자기 것처럼 보여 주면 눌러 보고 나서야
        // 안 듣는다는 것을 알게 됩니다.
        bool bound = map.IsBound(action);
        Button recorder = new()
        {
            Content = recordingAction == action
                ? AppResources.Get("shortcutRecordingPrompt", "Text")
                : bound ? map.For(action).Display() : string.Empty,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            FontSize = 12,
            MinHeight = 30,
        };
        ToolTipService.SetToolTip(recorder, AppResources.Get("shortcutClickToRecord", "Text"));
        AutomationProperties.SetName(recorder, title.Text);
        AutomationProperties.SetAutomationId(
            recorder,
            "settings.shortcuts.record." + action.ToString().ToLowerInvariant());
        recorder.Click += (_, _) =>
        {
            recordingAction = action;
            rejectedAction = null;
            BuildShortcutRows();
        };
        // 기다리는 동안 이 단추가 키를 받습니다. 창 전체를 잠그지 않으므로 Esc 로 언제든
        // 빠져나갈 수 있습니다.
        recorder.PreviewKeyDown += OnShortcutRecorderKeyDown;
        recorder.Tag = action;
        Grid.SetColumn(recorder, 1);
        row.Children.Add(recorder);
        if (recordingAction == action)
        {
            _ = recorder.Focus(FocusState.Programmatic);
        }

        Button reset = new()
        {
            Content = AppResources.Get("shortcutReset", "Content"),
            FontSize = 12,
            MinHeight = 30,
        };
        ToolTipService.SetToolTip(reset, (string)reset.Content);
        reset.Click += (_, _) =>
        {
            workspaceState?.UpdateShortcuts(current => current.Reset(action));
            recordingAction = null;
            rejectedAction = null;
            BuildShortcutRows();
        };
        Grid.SetColumn(reset, 2);
        row.Children.Add(reset);
        return row;
    }

    private void OnShortcutRecorderKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (sender is not Button { Tag: WorkflowShortcutAction action } ||
            recordingAction != action)
        {
            return;
        }
        args.Handled = true;
        if (args.Key == VirtualKey.Escape)
        {
            recordingAction = null;
            BuildShortcutRows();
            return;
        }
        // 조합 키만 눌린 상태는 아직 아무것도 정해지지 않은 것입니다 — 계속 기다립니다.
        if (args.Key is VirtualKey.Control or VirtualKey.Menu or VirtualKey.Shift
            or VirtualKey.LeftWindows or VirtualKey.RightWindows)
        {
            return;
        }
        if (RecorderKeyName(args.Key) is not { } key)
        {
            recordingAction = null;
            rejectedAction = action;
            BuildShortcutRows();
            return;
        }

        WorkflowShortcutModifiers modifiers = WorkflowShortcutModifiers.None;
        if (IsHeld(VirtualKey.Control))
        {
            modifiers |= WorkflowShortcutModifiers.Control;
        }
        if (IsHeld(VirtualKey.Menu))
        {
            modifiers |= WorkflowShortcutModifiers.Alt;
        }
        if (IsHeld(VirtualKey.Shift))
        {
            modifiers |= WorkflowShortcutModifiers.Shift;
        }

        WorkflowShortcutMap before = workspaceState?.Current.Shortcuts ?? WorkflowShortcutMap.Defaults;
        WorkflowShortcutMap after = before.With(action, new WorkflowShortcut(key, modifiers));
        recordingAction = null;
        // 참조가 그대로면 거절입니다 — 이미 다른 명령이 쓰고 있거나 쓸 수 없는 키입니다.
        if (ReferenceEquals(after, before))
        {
            rejectedAction = action;
            BuildShortcutRows();
            return;
        }
        rejectedAction = null;
        workspaceState?.UpdateShortcuts(_ => after);
        BuildShortcutRows();
    }

    private static bool IsHeld(VirtualKey key) =>
        InputKeyboardSource.GetKeyStateForCurrentThread(key)
            .HasFlag(CoreVirtualKeyStates.Down);

    private static string? RecorderKeyName(VirtualKey key) => key switch
    {
        >= VirtualKey.A and <= VirtualKey.Z => ((char)('a' + (key - VirtualKey.A))).ToString(),
        >= VirtualKey.Number0 and <= VirtualKey.Number9 =>
            ((char)('0' + (key - VirtualKey.Number0))).ToString(),
        >= VirtualKey.NumberPad0 and <= VirtualKey.NumberPad9 =>
            ((char)('0' + (key - VirtualKey.NumberPad0))).ToString(),
        VirtualKey.Delete => "delete",
        (VirtualKey)219 => "[",
        (VirtualKey)221 => "]",
        (VirtualKey)220 => "\\",
        (VirtualKey)222 => "'",
        _ => null,
    };

    private void OnShortcutResetAllClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.UpdateShortcuts(current => current.ResetAll());
        recordingAction = null;
        rejectedAction = null;
        BuildShortcutRows();
    }

    private static string GroupTitle(WorkflowShortcutGroup group) => AppResources.Get(group switch
    {
        WorkflowShortcutGroup.Library => "shortcutGroupLibrary",
        WorkflowShortcutGroup.Photo => "shortcutGroupPhoto",
        WorkflowShortcutGroup.View => "shortcutGroupView",
        WorkflowShortcutGroup.Scanner => "shortcutGroupScanner",
        WorkflowShortcutGroup.Export => "shortcutGroupExport",
        _ => "shortcutGroupDevelop",
    }, "Text");

    /// <summary>
    /// 표에 보이는 명령 이름입니다. macOS <c>action.title(in:)</c> 과 같은 문구를 씁니다 —
    /// 별점과 프로세스는 그 자리에서 숫자·이름을 붙입니다.
    /// </summary>
    private static string ActionTitle(WorkflowShortcutAction action) => action switch
    {
        WorkflowShortcutAction.Undo => AppResources.Get("shortcutUndo", "Text"),
        WorkflowShortcutAction.Redo => AppResources.Get("shortcutRedo", "Text"),
        WorkflowShortcutAction.ImportImages => AppResources.Get("shortcutImportImages", "Text"),
        WorkflowShortcutAction.ImportFolder => AppResources.Get("shortcutImportFolder", "Text"),
        WorkflowShortcutAction.RefreshLibrary => AppResources.Get("shortcutRefreshLibrary", "Text"),
        WorkflowShortcutAction.LibraryGrid => AppResources.Get("libraryCullingGrid", "Text"),
        WorkflowShortcutAction.LibraryCompare =>
            AppResources.Get("libraryCullingCompare", "Text"),
        WorkflowShortcutAction.LibrarySurvey =>
            AppResources.Get("libraryCullingSurvey", "Text"),
        WorkflowShortcutAction.PreviousPhoto => AppResources.Get("shortcutPreviousPhoto", "Text"),
        WorkflowShortcutAction.NextPhoto => AppResources.Get("shortcutNextPhoto", "Text"),
        WorkflowShortcutAction.PickPhoto => AppResources.Get("shortcutPickPhoto", "Text"),
        WorkflowShortcutAction.ClearPick => AppResources.Get("shortcutClearPick", "Text"),
        WorkflowShortcutAction.RejectPhoto => AppResources.Get("shortcutRejectPhoto", "Text"),
        WorkflowShortcutAction.DeletePhoto => AppResources.Get("shortcutDeletePhoto", "Text"),
        WorkflowShortcutAction.RateZero => AppResources.Get("shortcutRateZero", "Text"),
        WorkflowShortcutAction.RateOne => Stars(1),
        WorkflowShortcutAction.RateTwo => Stars(2),
        WorkflowShortcutAction.RateThree => Stars(3),
        WorkflowShortcutAction.RateFour => Stars(4),
        WorkflowShortcutAction.RateFive => Stars(5),
        WorkflowShortcutAction.CreateVirtualCopy =>
            AppResources.Get("libraryVirtualCopy", "Content"),
        WorkflowShortcutAction.ResetAdjustments =>
            AppResources.Get("shortcutResetAdjustments", "Text"),
        WorkflowShortcutAction.CopyDevelopSettings =>
            AppResources.Get("shortcutCopyDevelopSettings", "Text"),
        WorkflowShortcutAction.PasteDevelopSettings =>
            AppResources.Get("shortcutPasteDevelopSettings", "Text"),
        WorkflowShortcutAction.ProcessColorNegative => Process("filmTypeColorNegative"),
        WorkflowShortcutAction.ProcessColorPositive => Process("filmTypeColorPositive"),
        WorkflowShortcutAction.ProcessBwNegative => Process("filmTypeBlackAndWhiteNegative"),
        WorkflowShortcutAction.ProcessBwPositive => Process("filmTypeBlackAndWhitePositive"),
        WorkflowShortcutAction.TargetMain => Target(DevelopTarget.Main),
        WorkflowShortcutAction.TargetPrint => Target(DevelopTarget.Print),
        WorkflowShortcutAction.TargetNoritsu => Target(DevelopTarget.Noritsu),
        WorkflowShortcutAction.TargetSp3000 => Target(DevelopTarget.Sp3000),
        WorkflowShortcutAction.TargetF135 => Target(DevelopTarget.F135),
        WorkflowShortcutAction.TargetHr => Target(DevelopTarget.Hr),
        WorkflowShortcutAction.TargetExpired => Target(DevelopTarget.Rescue),
        WorkflowShortcutAction.RotateLeft => AppResources.Get("shortcutRotateLeft", "Text"),
        WorkflowShortcutAction.RotateRight => AppResources.Get("shortcutRotateRight", "Text"),
        WorkflowShortcutAction.FlipHorizontal =>
            AppResources.Get("shortcutFlipHorizontal", "Text"),
        WorkflowShortcutAction.FlipVertical => AppResources.Get("shortcutFlipVertical", "Text"),
        WorkflowShortcutAction.ToggleBeforeAfter =>
            AppResources.Get("shortcutToggleBeforeAfter", "Text"),
        WorkflowShortcutAction.ShowHideSidebar =>
            AppResources.Get("shortcutShowHideSidebar", "Text"),
        WorkflowShortcutAction.ShowHideFilmstrip =>
            AppResources.Get("shortcutShowHideFilmstrip", "Text"),
        WorkflowShortcutAction.ShowHideInspector =>
            AppResources.Get("shortcutShowHideInspector", "Text"),
        WorkflowShortcutAction.OpenLibraryWorkspace =>
            AppResources.Get("shortcutOpenLibrary", "Text"),
        WorkflowShortcutAction.OpenDevelopWorkspace =>
            AppResources.Get("shortcutOpenDevelop", "Text"),
        WorkflowShortcutAction.DetectScanners =>
            AppResources.Get("shortcutDetectScanners", "Text"),
        WorkflowShortcutAction.PreviewScan => AppResources.Get("shortcutPreviewScan", "Text"),
        WorkflowShortcutAction.ScanFrame => AppResources.Get("shortcutScanFrame", "Text"),
        WorkflowShortcutAction.QuickExport => AppResources.Get("shortcutQuickExport", "Text"),
        _ => AppResources.Get("shortcutExportPhoto", "Text"),
    };

    private static string Stars(int value) =>
        AppResources.FormatIntegers("libraryStarFormat", "Text", value);

    private static string Target(DevelopTarget target) =>
        AppResources.Get("libraryTarget", "Text") + ": " + DevelopTargets.DisplayName(target);

    private static string Process(string filmTypeKey) =>
        AppResources.Get("shortcutProcess", "Text") + ": " +
        AppResources.Get(filmTypeKey, "Text");
}
