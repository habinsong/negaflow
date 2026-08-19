using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls.Primitives;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Views.Develop.Inspector;

namespace Negaflow.Shell.Views.Develop.Host;

/// <summary>인스펙터 탭과 섹션 펼침입니다. frame 선택·크롭과 다른 이유입니다.</summary>
internal sealed class DevelopInspectorChrome
{
    private readonly DevelopWorkspaceView view;

    internal DevelopInspectorChrome(DevelopWorkspaceView view) => this.view = view;

    internal void Hook()
    {
        view.BasicTabButton.Click += OnInspectorTabClicked;
        view.BaseTabButton.Click += OnInspectorTabClicked;
        view.EditTabButton.Click += OnInspectorTabClicked;
        view.DefectsTabButton.Click += OnInspectorTabClicked;
        view.InfoTabButton.Click += OnInspectorTabClicked;
        view.ResetTabButton.Click += OnInspectorTabClicked;
        view.Adjustments.SectionToggleRequested += OnAdjustmentSectionToggle;
        view.Adjustments.SectionExpansionRequested += OnAdjustmentSectionExpansion;
    }

    internal void SelectTab(DevelopInspectorTab tab)
    {
        if (tab != DevelopInspectorTab.Edit)
        {
            view.cropSession.Cancel();
        }
        view.inspectorPresentation.SelectTab(tab);
        Apply();
    }

    internal void Apply()
    {
        if (!view.isInspectorPresentationReady)
        {
            return;
        }

        view.isSynchronizingInspectorPresentation = true;
        view.BasicTabButton.IsChecked = view.inspectorPresentation.SelectedTab == DevelopInspectorTab.Basic;
        view.BaseTabButton.IsChecked = view.inspectorPresentation.SelectedTab == DevelopInspectorTab.Base;
        view.EditTabButton.IsChecked = view.inspectorPresentation.SelectedTab == DevelopInspectorTab.Edit;
        view.DefectsTabButton.IsChecked = view.inspectorPresentation.SelectedTab == DevelopInspectorTab.Defects;
        view.InfoTabButton.IsChecked = view.inspectorPresentation.SelectedTab == DevelopInspectorTab.Info;
        view.ResetTabButton.IsChecked = view.inspectorPresentation.SelectedTab == DevelopInspectorTab.Reset;
        view.BaseCard.Visibility = view.inspectorPresentation.SelectedTab == DevelopInspectorTab.Base
            ? Visibility.Visible
            : Visibility.Collapsed;
        view.InfoCards.Apply(view.inspectorPresentation.SelectedTab == DevelopInspectorTab.Info);
        view.GrainMendPanel.Apply(view.inspectorPresentation.SelectedTab == DevelopInspectorTab.Defects);
        view.GeometryCard.Visibility = view.inspectorPresentation.SelectedTab == DevelopInspectorTab.Edit
            ? Visibility.Visible
            : Visibility.Collapsed;
        // macOS resetToolContent — 초기화 탭은 ResetControlsSection 하나를 냅니다.
        view.ResetCard.Visibility = view.inspectorPresentation.SelectedTab == DevelopInspectorTab.Reset
            ? Visibility.Visible
            : Visibility.Collapsed;
        view.ResetCard.Show(view.panel);
        view.Adjustments.Apply(view.inspectorPresentation);
        view.isSynchronizingInspectorPresentation = false;
    }

    private void OnInspectorTabClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (!view.isInspectorPresentationReady ||
            view.isSynchronizingInspectorPresentation ||
            sender is not ToggleButton { Tag: string tag } ||
            !Enum.TryParse(tag, out DevelopInspectorTab tab))
        {
            return;
        }

        if (tab != DevelopInspectorTab.Edit)
        {
            view.cropSession.Cancel();
        }

        view.inspectorPresentation.SelectTab(tab);
        Apply();
    }

    private void OnAdjustmentSectionToggle(object? sender, DevelopInspectorSection section)
    {
        _ = sender;
        if (!view.isInspectorPresentationReady || view.isSynchronizingInspectorPresentation)
        {
            return;
        }

        if (view.inspectorPresentation.ExpandedSection == section)
        {
            view.inspectorPresentation.Collapse(section);
        }
        else
        {
            view.inspectorPresentation.Expand(section);
        }
        Apply();
    }

    private void OnAdjustmentSectionExpansion(
        object? sender,
        DevelopInspectorSectionExpansion request)
    {
        _ = sender;
        if (!view.isInspectorPresentationReady || view.isSynchronizingInspectorPresentation)
        {
            return;
        }

        if (request.IsExpanded)
        {
            view.inspectorPresentation.Expand(request.Section);
        }
        else
        {
            view.inspectorPresentation.Collapse(request.Section);
        }
        Apply();
    }
}
