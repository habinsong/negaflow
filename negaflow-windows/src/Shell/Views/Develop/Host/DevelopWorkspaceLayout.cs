using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls.Primitives;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views.Develop.Host;

/// <summary>세 칸 너비와 패널 가시성입니다. 선택·미리보기와 다른 이유입니다.</summary>
internal sealed class DevelopWorkspaceLayout
{
    private readonly DevelopWorkspaceView view;

    internal DevelopWorkspaceLayout(DevelopWorkspaceView view) => this.view = view;

    internal void Hook()
    {
        view.Root.SizeChanged += OnRootSizeChanged;
        view.LeftResizeThumb.DragStarted += OnLeftResizeStarted;
        view.LeftResizeThumb.DragDelta += OnLeftResizeDelta;
        view.LeftResizeThumb.DragCompleted += OnLeftResizeCompleted;
        view.RightResizeThumb.DragStarted += OnRightResizeStarted;
        view.RightResizeThumb.DragDelta += OnRightResizeDelta;
        view.RightResizeThumb.DragCompleted += OnRightResizeCompleted;
    }

    internal void Update(ShellPreferences preferences)
    {
        view.LeftPanel.Visibility = preferences.IsSidebarVisible ? Visibility.Visible : Visibility.Collapsed;
        view.LeftDivider.Visibility = view.LeftPanel.Visibility;
        view.LeftResizeThumb.Visibility = view.LeftPanel.Visibility;
        view.RightPanel.Visibility = preferences.IsInspectorVisible ? Visibility.Visible : Visibility.Collapsed;
        view.RightDivider.Visibility = view.RightPanel.Visibility;
        view.RightResizeThumb.Visibility = view.RightPanel.Visibility;
        view.Filmstrip.Visibility = preferences.IsFilmstripVisible ? Visibility.Visible : Visibility.Collapsed;
        SynchronizeWidths(preferences);
        view.LeftPanel.SynchronizeTab(preferences.SelectedDevelopSidebarTab);
        if (view.LeftPanel.ExportPanel.Settings != preferences.Export ||
            view.LeftPanel.ExportPanel.QuickSettings != preferences.QuickExport ||
            view.LeftPanel.ExportPanel.Recipes != preferences.ExportRecipes)
        {
            view.LeftPanel.ExportPanel.ApplyPreferences(
                preferences.Export,
                preferences.QuickExport,
                preferences.ExportRecipes);
        }

        // 프루프는 보기용이므로 미리보기에만 겁니다. 게시하는 파일은 그대로입니다.
        if (view.softProofPreferences != preferences.SoftProof)
        {
            view.softProofPreferences = preferences.SoftProof;
            view.ApplySoftProof();
        }
    }

    internal void SynchronizeWidths(ShellPreferences preferences)
    {
        view.resizeController.Synchronize(
            preferences.SidebarWidth,
            preferences.InspectorWidth,
            view.Root.ActualWidth);
        view.LeftPanel.Width = view.resizeController.LeftWidth;
        view.RightPanel.Width = view.resizeController.RightWidth;
        view.LeftPanel.UpdateCompactRail();
    }

    private void OnRootSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (view.workspaceState is not null)
        {
            SynchronizeWidths(view.workspaceState.Current);
        }
    }

    private void OnLeftResizeStarted(object sender, DragStartedEventArgs args)
    {
        _ = sender;
        _ = args;
        view.resizeController.BeginLeft();
    }

    private void OnLeftResizeDelta(object sender, DragDeltaEventArgs args)
    {
        _ = sender;
        view.LeftPanel.Width = view.resizeController.UpdateLeft(args.HorizontalChange, view.Root.ActualWidth);
        view.LeftPanel.UpdateCompactRail();
    }

    private void OnLeftResizeCompleted(object sender, DragCompletedEventArgs args)
    {
        _ = sender;
        _ = args;
        view.workspaceState?.SetSidebarWidth(view.resizeController.EndLeft());
    }

    private void OnRightResizeStarted(object sender, DragStartedEventArgs args)
    {
        _ = sender;
        _ = args;
        view.resizeController.BeginRight();
    }

    private void OnRightResizeDelta(object sender, DragDeltaEventArgs args)
    {
        _ = sender;
        view.RightPanel.Width = view.resizeController.UpdateRight(args.HorizontalChange, view.Root.ActualWidth);
    }

    private void OnRightResizeCompleted(object sender, DragCompletedEventArgs args)
    {
        _ = sender;
        _ = args;
        view.workspaceState?.SetInspectorWidth(view.resizeController.EndRight());
    }
}
