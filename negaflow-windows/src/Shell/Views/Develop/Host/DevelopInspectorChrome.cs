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
        // 부분 보정(닷지·번)은 마스크가 화면에 하나도 그려지지 않아 지금은 쓸 수 없습니다.
        // 설정 · 일반의 <b>개발자 모드</b>를 켰을 때만 냅니다 — 반쯤 동작하는 것을 사용자
        // 앞에 두지 않기 위해서입니다.
        view.LocalAdjustmentCard.Visibility =
            view.developerMode && view.GeometryCard.Visibility == Visibility.Visible
                ? Visibility.Visible
                : Visibility.Collapsed;
        if (view.LocalAdjustmentCard.Visibility == Visibility.Visible)
        {
            view.LocalAdjustmentCard.Show();
        }
        else
        {
            // 카드를 감추면 그리는 중이던 것도 멈춥니다. 안 그러면 캔버스에 안내줄만 남습니다.
            view.LocalAdjustmentCard.StopDrawing();
            view.SyncLocalAdjustmentPrompt();
        }
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
