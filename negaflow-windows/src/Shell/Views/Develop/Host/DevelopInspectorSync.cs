using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Host;

/// <summary>인스펙터 값을 화면에 되비춥니다. 탭 chrome·자동 조정 엔진과 다른 이유입니다.</summary>
internal sealed class DevelopInspectorSync
{
    private readonly DevelopWorkspaceView view;

    internal DevelopInspectorSync(DevelopWorkspaceView view) => this.view = view;

    internal void Hook()
    {
        view.Adjustments.PreviewRequested += OnPreviewRequested;
        view.Adjustments.RefreshRequested += OnRefreshRequested;
        view.Adjustments.ResetRequested += OnResetRequested;
        view.BaseCard.RecipeChanged += OnBaseRecipeChanged;
        view.BaseCard.ManualBaseCommitted += OnManualBaseCommitted;
        view.GeometryCard.TransformRequested += OnGeometryTransformRequested;
        view.ResetCard.ResetAllAdjustmentsRequested += OnResetAllAdjustmentsRequested;
        view.ResetCard.ResetPhotoAngleRequested += OnResetPhotoAngleRequested;
        view.GeometryCard.AspectChosen += view.cropSession.OnAspectChosen;
        view.GeometryCard.AspectLockToggled += view.cropSession.OnAspectLockToggled;
        view.HistogramView.ValueChanged += OnHistogramValueChanged;
        view.LeftPanel.PresetsPanel.RecipeReplaced += OnPresetRecipeReplaced;
        view.LeftPanel.VersionsPanel.VersionRestored += OnVersionRestored;
        view.LeftPanel.FilmLookPanel.LookChanged += OnFilmLookChanged;
    }

    internal void Synchronize()
    {
        if (view.panel is null)
        {
            return;
        }

        view.isSynchronizingInspector = true;
        view.Adjustments.Show(view.panel);
        view.GeometryCard.Show(view.panel);
        view.GeometryCard.UpdateAspectControls(view.panel, view.crop.IsAspectLocked);
        view.LeftPanel.FilmLookPanel.Update();
        view.LeftPanel.VersionsPanel.Update();
        view.LeftPanel.PresetsPanel.Update();
        view.HistogramView.SynchronizeValues(
            view.panel.Tone.Shadows,
            view.panel.Tone.Density,
            view.panel.Tone.Exposure,
            view.panel.Tone.Highlights);
        // Auto에는 수동 base가 없으므로 slider에는 시작 위치만 보입니다. 사용자가 값을 바꾸면
        // manual mode로 전환되며, 그 전까지 preview/export는 native Auto resolver를 사용합니다.
        view.BaseCard.ShowManualValues(view.panel);
        view.ResetCard.Show(view.panel);
        view.isSynchronizingInspector = false;
    }

    internal void SyncBase() => view.BaseCard.Sync();

    internal void SyncTone()
    {
        bool canEdit = view.panel?.CanEditTone == true;
        bool canAutoAdjust = view.panel?.SelectedFrame?.CanDevelop == true &&
                             view.autoAdjustCoordinator is not null;
        view.Adjustments.SetEnabled(canEdit, canAutoAdjust);
        view.GeometryCard.SetEnabled(canEdit);
        view.HistogramView.IsEnabled = canEdit;
    }

    internal void UpdateImageTransform(Func<DevelopPanelState, LibraryFrameError> update)
    {
        if (view.panel is null || view.isSynchronizingInspector ||
            update(view.panel) != LibraryFrameError.None)
        {
            return;
        }
        // macOS `onChange(of: frame.imageTransform.displayName)` → `resetViewport`.
        view.panel.Viewport.Reset();
        Synchronize();
        view.RequestPreview();
    }

    private void OnPreviewRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        view.RequestPreview();
    }

    private void OnRefreshRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        Synchronize();
        view.RequestPreview();
    }

    /// <summary>macOS <c>resetAllAdjustments</c> — 인스펙터 단추와 메뉴가 같은 길입니다.</summary>
    private void OnResetAllAdjustmentsRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        view.ResetAllAdjustmentsFromMenu();
    }

    /// <summary>
    /// macOS <c>resetPhotoAngle</c> — 회전과 수평 보정만 되돌립니다. 기하가 바뀌므로 다른
    /// 회전·뒤집기와 같이 뷰포트도 되돌립니다.
    /// </summary>
    private void OnResetPhotoAngleRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateImageTransform(state => state.ResetPhotoAngle());
    }

    private void OnResetRequested(
        object? sender,
        Func<DevelopPanelState, LibraryFrameError> reset)
    {
        _ = sender;
        if (view.panel is null || reset(view.panel) != LibraryFrameError.None)
        {
            return;
        }
        Synchronize();
        view.RequestPreview();
    }

    private void OnManualBaseCommitted(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (view.panel is null)
        {
            return;
        }

        // slider 변경은 Auto를 Manual로 전환합니다. 선택 행과 export 상태도 즉시 같은 snapshot으로
        // 갱신해야 preview/export의 요청 mode가 화면과 어긋나지 않습니다.
        view.frames.UpdateSelectedFrameText();
        view.NotifyQuickExportAvailabilityChanged();
        if (view.panel.SelectedFrame is { CanDevelop: true })
        {
            view.ExportStatusText.Text = string.Empty;
        }
        view.RequestPreview();
    }

    private void OnBaseRecipeChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (view.panel is null)
        {
            return;
        }

        SyncBase();
        view.frames.UpdateSelectedFrameText();
        view.NotifyQuickExportAvailabilityChanged();
        view.ExportStatusText.Text = string.Empty;
        view.RequestPreview();
    }

    private void OnHistogramValueChanged(object? sender, DevelopHistogramValueChangedEventArgs args)
    {
        _ = sender;
        if (view.panel is null || view.isSynchronizingInspector)
        {
            return;
        }

        LibraryFrameError error = args.Region switch
        {
            DevelopHistogramRegion.Shadow => view.panel.Tone.SetShadows(args.Value),
            DevelopHistogramRegion.Density => view.panel.Tone.SetDensity(args.Value),
            DevelopHistogramRegion.Exposure => view.panel.Tone.SetExposure(args.Value),
            DevelopHistogramRegion.Highlight => view.panel.Tone.SetHighlights(args.Value),
            _ => LibraryFrameError.InvalidToneValue,
        };
        if (error == LibraryFrameError.None)
        {
            Synchronize();
            view.RequestPreview();
        }
    }

    private void OnGeometryTransformRequested(
        object? sender,
        Func<DevelopPanelState, LibraryFrameError> update)
    {
        _ = sender;
        UpdateImageTransform(update);
    }

    private void OnPresetRecipeReplaced(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        ReloadAfterRecipeReplaced();
    }

    /// <summary>
    /// recipe 가 통째로 바뀌었을 때 화면 전체를 다시 맞춥니다. 붙여넣기와 프리셋 적용이 같은
    /// 자리를 쓰므로 한쪽만 갱신되는 일이 없습니다.
    /// </summary>
    private void ReloadAfterRecipeReplaced()
    {
        Synchronize();
        SyncBase();
        SyncTone();
        view.LeftPanel.FilmLookPanel.Update();
        view.LeftPanel.PresetsPanel.Update();
        view.RequestPreview();
    }

    private void OnVersionRestored(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        // 되돌린 recipe 가 인스펙터와 캔버스에 함께 반영돼야 합니다.
        Synchronize();
        SyncBase();
        SyncTone();
        view.RequestPreview();
    }

    private void OnFilmLookChanged(
        object? sender,
        Func<DevelopPanelState, LibraryFrameError> update)
    {
        _ = sender;
        UpdateImageTransform(update);
    }
}
