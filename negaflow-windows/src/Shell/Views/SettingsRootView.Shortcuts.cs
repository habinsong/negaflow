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

    /// <summary>
    /// 묶음 캡슐입니다. macOS 는 <c>Picker(.segmented)</c> 하나이고, 칸은 폭을 똑같이
    /// 나눠 가집니다 — 이름 길이에 따라 칸이 들쭉날쭉해지지 않습니다.
    /// </summary>
    private void BuildShortcutGroups()
    {
        ShortcutGroupPicker.SetOptions(
            [.. Enum.GetValues<WorkflowShortcutGroup>()
                .Select(group => new Controls.SegmentOption(group, GroupTitle(group)))],
            shortcutGroup);
    }

    private void OnShortcutGroupChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (ShortcutGroupPicker.SelectedValue is not WorkflowShortcutGroup group)
        {
            return;
        }
        shortcutGroup = group;
        recordingAction = null;
        rejectedAction = null;
        BuildShortcutRows();
    }

    private void BuildShortcutRows()
    {
        ShortcutRowsSection.Rows.Clear();
        ShortcutRowsSection.HeaderText = GroupTitle(shortcutGroup);
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
            ShortcutRowsSection.Rows.Add(ShortcutRow(action, map));
            if (rejectedAction == action)
            {
                Controls.SettingsFootnote note = new()
                {
                    Text = AppResources.Get("shortcutInvalidOrConflict", "Text"),
                };
                note.Foreground = new SolidColorBrush(
                    Windows.UI.Color.FromArgb(0xFF, 0xE5, 0x48, 0x4D));
                ShortcutRowsSection.Rows.Add(note);
            }
        }
        ShortcutRowsSection.Apply();
    }

    /// <summary>
    /// 한 줄입니다. 실측(단축키.png): 줄 높이 51, 녹화 칸 328, 되돌리기 40, 사이 8.
    /// </summary>
    private Controls.SettingsRow ShortcutRow(
        WorkflowShortcutAction action,
        WorkflowShortcutMap map)
    {
        // 빼앗긴 단축키는 빈칸으로 보입니다. 남의 키를 자기 것처럼 보여 주면 눌러 보고 나서야
        // 안 듣는다는 것을 알게 됩니다.
        bool bound = map.IsBound(action);
        string title = ActionTitle(action);
        Button recorder = new()
        {
            Content = recordingAction == action
                ? AppResources.Get("shortcutRecordingPrompt", "Text")
                : bound ? map.For(action).Display() : string.Empty,
            Width = 328,
            Height = 30,
            FontSize = 12,
            Tag = action,
        };
        ToolTipService.SetToolTip(recorder, AppResources.Get("shortcutClickToRecord", "Text"));
        AutomationProperties.SetName(recorder, title);
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

        Button reset = new()
        {
            Content = new FontIcon { FontSize = 13, Glyph = "\uE7A7" },
            Width = 40,
            Height = 30,
            Padding = new Thickness(0),
        };
        string resetLabel = AppResources.Get("shortcutReset", "Content");
        ToolTipService.SetToolTip(reset, resetLabel);
        AutomationProperties.SetName(reset, resetLabel);
        reset.Click += (_, _) =>
        {
            workspaceState?.UpdateShortcuts(current => current.Reset(action));
            recordingAction = null;
            rejectedAction = null;
            BuildShortcutRows();
        };

        StackPanel right = new()
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            VerticalAlignment = VerticalAlignment.Center,
        };
        right.Children.Add(recorder);
        right.Children.Add(reset);
        Controls.SettingsRow row = new() { Label = title, MinHeight = 51, Control = right };
        if (recordingAction == action)
        {
            _ = recorder.Focus(FocusState.Programmatic);
        }
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

    private void OnResetAllShortcuts(object sender, RoutedEventArgs args)
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
        WorkflowShortcutGroup.Help => "menuHelp",
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
        WorkflowShortcutAction.LoadScanner => AppResources.Get("loadScanner", "Text"),
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
        WorkflowShortcutAction.ProcessColorNegative => Process(DevelopmentProcess.C41),
        WorkflowShortcutAction.ProcessColorPositive => Process(DevelopmentProcess.E6),
        WorkflowShortcutAction.ProcessBwNegative => Process(DevelopmentProcess.D76),
        WorkflowShortcutAction.ProcessBwPositive =>
            Process(DevelopmentProcess.BlackAndWhiteReversal),
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
        WorkflowShortcutAction.ToggleFullScreen =>
            AppResources.Get("commandToggleFullScreen", "Text"),
        WorkflowShortcutAction.AutoTone => AppResources.Get("developAutoTone", "Content"),
        WorkflowShortcutAction.AutoWhiteBalance =>
            AppResources.Get("developAutoWhiteBalance", "Content"),
        WorkflowShortcutAction.ToggleAutoColor =>
            AppResources.Get("developAutoColor", "Content"),
        WorkflowShortcutAction.ToggleAutoLevels =>
            AppResources.Get("developAutoLevels", "Content"),
        WorkflowShortcutAction.ToggleNoiseReduction =>
            AppResources.Get("developNoiseReduction", "Text"),
        WorkflowShortcutAction.CropTool => AppResources.Get("developCropArea", "Text"),
        WorkflowShortcutAction.BasePickerTool => AppResources.Get("developPickBase", "Text"),
        WorkflowShortcutAction.AutoDefectTool => Defect("developGrainMendAuto"),
        WorkflowShortcutAction.GuidedDefectTool => Defect("developGrainMendGuided"),
        WorkflowShortcutAction.BrushDefectTool => Defect("developGrainMendBrush"),
        WorkflowShortcutAction.CloneStampTool => Defect("developGrainMendClone"),
        WorkflowShortcutAction.OpenLibraryWorkspace =>
            AppResources.Get("shortcutOpenLibrary", "Text"),
        WorkflowShortcutAction.OpenDevelopWorkspace =>
            AppResources.Get("shortcutOpenDevelop", "Text"),
        WorkflowShortcutAction.OpenPrintWorkspace =>
            AppResources.Get("menuPrint", "Text"),
        WorkflowShortcutAction.DetectScanners =>
            AppResources.Get("shortcutDetectScanners", "Text"),
        WorkflowShortcutAction.PreviewScan => AppResources.Get("shortcutPreviewScan", "Text"),
        WorkflowShortcutAction.ScanFrame => AppResources.Get("shortcutScanFrame", "Text"),
        WorkflowShortcutAction.ToggleScannerSimulator =>
            AppResources.Get("commandToggleScannerSimulator", "Header"),
        WorkflowShortcutAction.AddFlatbedFrame => AppResources.Get("scanAddFrame", "Text"),
        WorkflowShortcutAction.RemoveFlatbedFrame =>
            AppResources.Get("scanRemoveFrame", "Text"),
        WorkflowShortcutAction.OpenHelp =>
            AppResources.Get("commandNegaflowHelp", "Text"),
        WorkflowShortcutAction.QuickExport => AppResources.Get("shortcutQuickExport", "Text"),
        _ => AppResources.Get("shortcutExportPhoto", "Text"),
    };

    private static string Stars(int value) =>
        AppResources.FormatIntegers("libraryStarFormat", "Text", value);

    private static string Target(DevelopTarget target) =>
        AppResources.Get("libraryTarget", "Text") + ": " + DevelopTargets.DisplayName(target);

    /// <summary>
    /// macOS 는 "프로세스: C-41/ECN-2" 처럼 공정 규격 이름을 붙입니다
    /// (WorkflowShortcutActions.swift:280-287) — 공정 이름은 번역하지 않습니다.
    /// </summary>
    private static string Process(DevelopmentProcess process) =>
        AppResources.Get("shortcutProcess", "Text") + ": " +
        DevelopProcesses.DisplayName(process);

    /// <summary>macOS <c>defectToolTitle</c> — "결함: 자동".</summary>
    private static string Defect(string toolKey) =>
        AppResources.Get("developTabDefects", "Value") + ": " +
        AppResources.Get(toolKey, "Content");
}
