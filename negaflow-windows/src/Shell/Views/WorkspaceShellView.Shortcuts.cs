using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml;
using Negaflow.Shell.Shortcuts;
using Windows.System;
using Windows.UI.Core;

namespace Negaflow.Shell.Views;

/// <summary>
/// 창 전체 단축키를 어느 화면의 어느 동작으로 보낼지 정합니다.
/// </summary>
/// <remarks>
/// macOS 는 이 자리를 메뉴 명령의 <c>keyboardShortcut</c> 이 맡습니다 — 메뉴 하나가 곧
/// 단축키 하나입니다. WinUI 에는 그 연결이 없으므로 <c>WorkflowShortcutAction</c> 을 두고
/// 메뉴막대와 이 키 처리기가 <b>같은</b> 동작 목록을 부릅니다.
/// </remarks>
public sealed partial class WorkspaceShellView
{
    /// <summary>
    /// 작업 흐름 단축키입니다. macOS 는 메뉴 막대가 이 일을 합니다. Windows 는 창 안
    /// 메뉴와 이 키 처리가 같이 받습니다.
    /// </summary>
    /// <remarks>
    /// **글자를 입력하는 중이면 손대지 않습니다.** 이름 상자에 "p" 를 치는 것이 사진을 선택으로
    /// 표시하면 안 됩니다. 조합 키가 붙은 단축키는 입력 중에도 살려 둡니다 — Ctrl+E 는 어디서
    /// 눌러도 내보내기입니다.
    /// </remarks>
    private void OnShellPreviewKeyDown(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        if (workspaceState is null || args.Handled)
        {
            return;
        }
        WorkflowShortcutModifiers modifiers = PressedModifiers();
        if (modifiers == WorkflowShortcutModifiers.None && IsTypingTarget(FocusManager.GetFocusedElement(XamlRoot)))
        {
            return;
        }
        if (KeyName(args.Key) is not { } key ||
            workspaceState.Current.Shortcuts.Resolve(key, modifiers) is not { } action)
        {
            return;
        }
        args.Handled = Invoke(action);
    }

    private static WorkflowShortcutModifiers PressedModifiers()
    {
        WorkflowShortcutModifiers modifiers = WorkflowShortcutModifiers.None;
        if (IsDown(VirtualKey.Control))
        {
            modifiers |= WorkflowShortcutModifiers.Control;
        }
        if (IsDown(VirtualKey.Menu))
        {
            modifiers |= WorkflowShortcutModifiers.Alt;
        }
        if (IsDown(VirtualKey.Shift))
        {
            modifiers |= WorkflowShortcutModifiers.Shift;
        }
        return modifiers;
    }

    private static bool IsDown(VirtualKey key) =>
        InputKeyboardSource.GetKeyStateForCurrentThread(key)
            .HasFlag(CoreVirtualKeyStates.Down);

    private static bool IsTypingTarget(object? focused) =>
        focused is TextBox or RichEditBox or AutoSuggestBox or PasswordBox;

    /// <summary>
    /// 눌린 키를 단축키 표가 쓰는 이름으로 바꿉니다. 모르는 키는 null 이며, 그 경우 아무 명령도
    /// 부르지 않습니다.
    /// </summary>
    private static string? KeyName(VirtualKey key) => key switch
    {
        >= VirtualKey.A and <= VirtualKey.Z => ((char)('a' + (key - VirtualKey.A))).ToString(),
        >= VirtualKey.Number0 and <= VirtualKey.Number9 =>
            ((char)('0' + (key - VirtualKey.Number0))).ToString(),
        >= VirtualKey.NumberPad0 and <= VirtualKey.NumberPad9 =>
            ((char)('0' + (key - VirtualKey.NumberPad0))).ToString(),
        VirtualKey.Delete => "delete",
        // 미국 자판의 [ ] \ 입니다. 다른 자판에서는 같은 자리의 글쇠가 잡힙니다 — macOS 도
        // 키 코드가 아니라 글쇠 자리로 답니다.
        (VirtualKey)219 => "[",
        (VirtualKey)221 => "]",
        (VirtualKey)220 => "\\",
        (VirtualKey)222 => "'",
        _ => null,
    };

    private bool Invoke(WorkflowShortcutAction action)
    {
        if (workspaceState is not { } state)
        {
            return false;
        }
        switch (action)
        {
            case WorkflowShortcutAction.OpenLibraryWorkspace:
                state.SelectWorkspace(WorkspaceModule.Library);
                return true;
            case WorkflowShortcutAction.OpenDevelopWorkspace:
                state.SelectWorkspace(WorkspaceModule.Develop);
                return true;
            case WorkflowShortcutAction.OpenPrintWorkspace:
                state.SelectWorkspace(WorkspaceModule.Print);
                return true;
            case WorkflowShortcutAction.ShowHideSidebar:
                state.ToggleSidebar();
                return true;
            case WorkflowShortcutAction.ShowHideInspector:
                state.ToggleInspector();
                return true;
            case WorkflowShortcutAction.ShowHideFilmstrip:
                state.ToggleFilmstrip();
                return true;
            case WorkflowShortcutAction.ToggleFullScreen:
                ToggleFullScreen();
                return true;
            case WorkflowShortcutAction.ImportImages:
                LibraryWorkspace.OnImportClicked(LibraryWorkspace, new RoutedEventArgs());
                return true;
            case WorkflowShortcutAction.ImportFolder:
                LibraryWorkspace.OnImportFoldersClicked(LibraryWorkspace, new RoutedEventArgs());
                return true;
            case WorkflowShortcutAction.RefreshLibrary:
                return LibraryWorkspace.InvokeShortcut(action);
            case WorkflowShortcutAction.LoadScanner:
                state.SelectWorkspace(WorkspaceModule.Library);
                LibraryWorkspace.PresentScannerSetup();
                return true;
            case WorkflowShortcutAction.LibraryGrid:
            case WorkflowShortcutAction.LibraryCompare:
            case WorkflowShortcutAction.LibrarySurvey:
                // macOS AppModel+WorkflowShortcuts: libraryCullingMode + activeWorkspaceModule = .library
                state.SelectWorkspace(WorkspaceModule.Library);
                return LibraryWorkspace.InvokeShortcut(action);
            case WorkflowShortcutAction.QuickExport:
                _ = DevelopWorkspace.QuickExportAsync();
                return true;
            case WorkflowShortcutAction.ExportPhoto:
                if (state.Current.SelectedWorkspace == WorkspaceModule.Print)
                {
                    PrintWorkspace.ExportFromMenu();
                }
                else
                {
                    _ = DevelopWorkspace.ExportPhotoAsync();
                }
                return true;
            case WorkflowShortcutAction.Undo:
            case WorkflowShortcutAction.Redo:
                return LibraryWorkspace.InvokeShortcut(action);
            case WorkflowShortcutAction.ToggleBeforeAfter:
                DevelopWorkspace.ToggleBeforeAfterFromMenu();
                return true;
            case WorkflowShortcutAction.ResetAdjustments:
                DevelopWorkspace.ResetAllAdjustmentsFromMenu();
                return true;
            case WorkflowShortcutAction.CopyDevelopSettings:
                DevelopWorkspace.CopyDevelopSettingsFromMenu();
                return true;
            case WorkflowShortcutAction.PasteDevelopSettings:
                DevelopWorkspace.PasteDevelopSettingsFromMenu();
                return true;
            case WorkflowShortcutAction.PickPhoto:
            case WorkflowShortcutAction.RejectPhoto:
            case WorkflowShortcutAction.DeletePhoto:
            case WorkflowShortcutAction.PreviousPhoto:
            case WorkflowShortcutAction.NextPhoto:
            case WorkflowShortcutAction.ClearPick:
            case WorkflowShortcutAction.RateZero:
            case WorkflowShortcutAction.RateOne:
            case WorkflowShortcutAction.RateTwo:
            case WorkflowShortcutAction.RateThree:
            case WorkflowShortcutAction.RateFour:
            case WorkflowShortcutAction.RateFive:
            case WorkflowShortcutAction.CreateVirtualCopy:
                return LibraryWorkspace.InvokeShortcut(action);
            case WorkflowShortcutAction.RotateLeft:
                DevelopWorkspace.UpdateImageTransform(state => state.Rotate(clockwise: false));
                return true;
            case WorkflowShortcutAction.RotateRight:
                DevelopWorkspace.UpdateImageTransform(state => state.Rotate(clockwise: true));
                return true;
            case WorkflowShortcutAction.FlipHorizontal:
                DevelopWorkspace.UpdateImageTransform(state => state.FlipHorizontally());
                return true;
            case WorkflowShortcutAction.FlipVertical:
                DevelopWorkspace.UpdateImageTransform(state => state.FlipVertically());
                return true;
            case WorkflowShortcutAction.AutoTone:
                DevelopWorkspace.RunAutoToneFromMenu();
                return true;
            case WorkflowShortcutAction.AutoWhiteBalance:
                DevelopWorkspace.RunAutoWhiteBalanceFromMenu();
                return true;
            case WorkflowShortcutAction.ToggleAutoColor:
                DevelopWorkspace.ToggleAutoColorFromMenu();
                return true;
            case WorkflowShortcutAction.ToggleAutoLevels:
                DevelopWorkspace.ToggleAutoLevelsFromMenu();
                return true;
            case WorkflowShortcutAction.ToggleNoiseReduction:
                DevelopWorkspace.ToggleNoiseReductionFromMenu();
                return true;
            case WorkflowShortcutAction.ProcessColorNegative:
            case WorkflowShortcutAction.ProcessColorPositive:
            case WorkflowShortcutAction.ProcessBwNegative:
            case WorkflowShortcutAction.ProcessBwPositive:
            case WorkflowShortcutAction.TargetMain:
            case WorkflowShortcutAction.TargetPrint:
            case WorkflowShortcutAction.TargetNoritsu:
            case WorkflowShortcutAction.TargetSp3000:
            case WorkflowShortcutAction.TargetF135:
            case WorkflowShortcutAction.TargetHr:
            case WorkflowShortcutAction.TargetExpired:
                return LibraryWorkspace.InvokeShortcut(action);
            case WorkflowShortcutAction.OpenHelp:
                QuickStartHelpRequested?.Invoke(this, EventArgs.Empty);
                return true;
            case WorkflowShortcutAction.DetectScanners:
            case WorkflowShortcutAction.ToggleScannerSimulator:
            case WorkflowShortcutAction.PreviewScan:
            case WorkflowShortcutAction.ScanFrame:
            case WorkflowShortcutAction.AddFlatbedFrame:
            case WorkflowShortcutAction.RemoveFlatbedFrame:
                // macOS 는 스캐너 명령으로 작업공간을 바꾸지 않습니다.
                return LibraryWorkspace.InvokeScannerShortcut(action);
            case WorkflowShortcutAction.CropTool:
                state.SelectWorkspace(WorkspaceModule.Develop);
                DevelopWorkspace.ToggleCropFromMenu();
                return true;
            case WorkflowShortcutAction.BasePickerTool:
                state.SelectWorkspace(WorkspaceModule.Develop);
                DevelopWorkspace.ToggleBasePickerFromMenu();
                return true;
            case WorkflowShortcutAction.AutoDefectTool:
                state.SelectWorkspace(WorkspaceModule.Develop);
                DevelopWorkspace.RunAutoDefectFromMenu();
                return true;
            case WorkflowShortcutAction.GuidedDefectTool:
                state.SelectWorkspace(WorkspaceModule.Develop);
                DevelopWorkspace.ToggleGuidedDefectFromMenu();
                return true;
            case WorkflowShortcutAction.BrushDefectTool:
                state.SelectWorkspace(WorkspaceModule.Develop);
                DevelopWorkspace.ToggleBrushDefectFromMenu();
                return true;
            case WorkflowShortcutAction.CloneStampTool:
                state.SelectWorkspace(WorkspaceModule.Develop);
                DevelopWorkspace.ToggleCloneStampFromMenu();
                return true;
        }
        // 나머지는 지금 보이는 화면이 맡습니다. 보이지 않는 화면이 조용히 사진을 바꾸면
        // 사용자는 무엇이 일어났는지 볼 수 없습니다.
        return state.Current.SelectedWorkspace == WorkspaceModule.Library &&
            LibraryWorkspace.InvokeShortcut(action);
    }

    /// <summary>macOS <c>NSApp.keyWindow?.toggleFullScreen</c> — WinUI FullScreen presenter.</summary>
    private void ToggleFullScreen()
    {
        if (hostWindowId is not { } id)
        {
            return;
        }
        AppWindow appWindow = AppWindow.GetFromWindowId(id);
        appWindow.SetPresenter(
            appWindow.Presenter.Kind == AppWindowPresenterKind.FullScreen
                ? AppWindowPresenterKind.Overlapped
                : AppWindowPresenterKind.FullScreen);
    }
}
