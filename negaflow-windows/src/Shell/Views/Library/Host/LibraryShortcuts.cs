using Microsoft.UI.Xaml;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Shortcuts;

namespace Negaflow.Shell.Views.Library.Host;

/// <summary>라이브러리 단축키입니다. 메뉴 구성과 다른 이유입니다.</summary>
internal sealed class LibraryShortcuts
{
    private readonly LibraryWorkspaceView view;

    internal LibraryShortcuts(LibraryWorkspaceView view) => this.view = view;

    /// <summary>
    /// 단축키가 부른 명령입니다. 이 화면이 맡을 수 있으면 처리하고 true 를 돌려줍니다.
    /// </summary>
    /// <remarks>
    /// 고른 사진이 없으면 사진 명령은 조용히 지나갑니다 — 아무것도 고르지 않은 채 X 를 눌러
    /// 무엇이 제외됐는지 모르게 되는 편이 더 나쁩니다.
    /// </remarks>
    internal bool Invoke(WorkflowShortcutAction action)
    {
        switch (action)
        {
            case WorkflowShortcutAction.ImportImages:
                view.OnImportClicked(view, new RoutedEventArgs());
                return true;
            case WorkflowShortcutAction.ImportFolder:
                view.OnImportFoldersClicked(view, new RoutedEventArgs());
                return true;
            case WorkflowShortcutAction.Undo:
                return view.actions.Undo(redo: false);
            case WorkflowShortcutAction.Redo:
                return view.actions.Undo(redo: true);
            case WorkflowShortcutAction.RefreshLibrary:
                if (view.libraryHost is { } host)
                {
                    view.ShowLibrary(host, view.importWindowId ?? default);
                }
                return true;
            case WorkflowShortcutAction.LibraryGrid:
                return ApplyCullingMode(LibraryCullingMode.Grid);
            case WorkflowShortcutAction.LibraryCompare:
                return ApplyCullingMode(LibraryCullingMode.Compare);
            case WorkflowShortcutAction.LibrarySurvey:
                return ApplyCullingMode(LibraryCullingMode.Survey);
            case WorkflowShortcutAction.PreviousPhoto:
                return view.selection.Move(-1);
            case WorkflowShortcutAction.NextPhoto:
                return view.selection.Move(1);
        }

        IReadOnlyList<LibraryFrameListItem> targets = view.selection.SelectedItems();
        if (targets.Count == 0)
        {
            return false;
        }
        switch (action)
        {
            case WorkflowShortcutAction.PickPhoto:
                view.actions.SetPickState(targets, FramePickState.Picked);
                return true;
            case WorkflowShortcutAction.ClearPick:
                view.actions.SetPickState(targets, FramePickState.Unflagged);
                return true;
            case WorkflowShortcutAction.RejectPhoto:
                view.actions.SetPickState(targets, FramePickState.Rejected);
                return true;
            case WorkflowShortcutAction.DeletePhoto:
                view.actions.RemoveFromLibrary(targets);
                return true;
            case WorkflowShortcutAction.ProcessColorNegative:
            case WorkflowShortcutAction.ProcessColorPositive:
            case WorkflowShortcutAction.ProcessBwNegative:
            case WorkflowShortcutAction.ProcessBwPositive:
                view.DevelopDefaultsPanel.ApplyProcess(action);
                return true;
            case WorkflowShortcutAction.TargetMain:
                view.DevelopDefaultsPanel.ApplyTarget(DevelopTarget.Main);
                return true;
            case WorkflowShortcutAction.TargetPrint:
                view.DevelopDefaultsPanel.ApplyTarget(DevelopTarget.Print);
                return true;
            case WorkflowShortcutAction.TargetNoritsu:
                view.DevelopDefaultsPanel.ApplyTarget(DevelopTarget.Noritsu);
                return true;
            case WorkflowShortcutAction.TargetSp3000:
                view.DevelopDefaultsPanel.ApplyTarget(DevelopTarget.Sp3000);
                return true;
            case WorkflowShortcutAction.TargetF135:
                view.DevelopDefaultsPanel.ApplyTarget(DevelopTarget.F135);
                return true;
            case WorkflowShortcutAction.TargetHr:
                view.DevelopDefaultsPanel.ApplyTarget(DevelopTarget.Hr);
                return true;
            case WorkflowShortcutAction.TargetExpired:
                view.DevelopDefaultsPanel.ApplyTarget(DevelopTarget.Rescue);
                return true;
            case WorkflowShortcutAction.CreateVirtualCopy:
                // 사본은 한 장에 하나씩입니다. 여러 장을 골랐으면 macOS 처럼 활성 사진만
                // 복사합니다 — 한 번에 열 장을 복사하는 것은 되돌리기 어렵습니다.
                view.actions.CreateVirtualCopy(targets[0]);
                return true;
            case WorkflowShortcutAction.RateZero:
            case WorkflowShortcutAction.RateOne:
            case WorkflowShortcutAction.RateTwo:
            case WorkflowShortcutAction.RateThree:
            case WorkflowShortcutAction.RateFour:
            case WorkflowShortcutAction.RateFive:
                view.actions.SetRating(targets, action - WorkflowShortcutAction.RateZero);
                return true;
            default:
                return false;
        }
    }

    internal bool ApplyCullingMode(LibraryCullingMode mode)
    {
        if (!view.CullingSurface.SetMode(mode))
        {
            return true;
        }
        view.ShowFilteredItems();
        return true;
    }
}
