using Microsoft.UI.Input;
using Microsoft.UI.Xaml.Input;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Windows.System;
using Windows.UI.Core;

namespace Negaflow.Shell.Views.Develop.GrainMend;

/// <summary>
/// 캔버스 포인터·키입니다. 검토 성분 토글, 가이드 사각형, 브러시·복제 획 순서입니다.
/// </summary>
internal sealed class DevelopGrainMendCanvasInput
{
    private readonly DevelopGrainMendPanel view;
    private CropDisplayPoint guidedDragStart;
    private CropDisplayPoint guidedDragCurrent;
    private double guidedFrameWidth;
    private double guidedFrameHeight;
    private bool guidedDragging;
    private DefectPoint? cloneCursor;

    /// <summary>
    /// macOS <c>hoverPoint</c> / 진행 중 획의 마지막 점입니다. 복제 커서가 이 자리에 섭니다.
    /// </summary>
    internal DefectPoint? CloneCursor => cloneCursor;

    /// <summary>
    /// macOS <c>optionDown</c>: Alt 를 누르고 있으면 소스 지정 모드이며 십자선만 냅니다.
    /// </summary>
    internal bool CloneSourceModifierDown =>
        InputKeyboardSource
            .GetKeyStateForCurrentThread(Windows.System.VirtualKey.Menu)
            .HasFlag(CoreVirtualKeyStates.Down);

    internal DevelopGrainMendCanvasInput(DevelopGrainMendPanel view) => this.view = view;

    internal bool TryHandlePressed(PointerRoutedEventArgs args)
    {
        // Guided는 press가 아니라 release에서 6pt 탭/드래그를 가릅니다. 먼저 gesture를 잡아야
        // macOS처럼 작은 이동의 끝점에서 component를 토글할 수 있습니다.
        if (TryBeginGuided(args))
        {
            args.Handled = true;
            return true;
        }
        if (TryTogglePendingComponent(args))
        {
            args.Handled = true;
            return true;
        }
        if (TryBeginStroke(args))
        {
            args.Handled = true;
            return true;
        }
        return false;
    }

    internal bool TryHandleMoved(PointerRoutedEventArgs args)
    {
        // macOS 는 드래그하지 않을 때에도 커서를 따라 원을 그립니다(onContinuousHover). 커서를
        // 먼저 옮겨 두어야 획을 이을 때 같은 점으로 그립니다.
        bool clone = view.grainMend.Strokes.Tool == GrainMendTool.Clone;
        if (clone && TryMap(args, out CropDisplayPoint hover))
        {
            cloneCursor = new DefectPoint(hover.X, hover.Y);
        }
        if (TryContinueGuided(args))
        {
            args.Handled = true;
            return true;
        }
        if (TryContinueStroke(args))
        {
            args.Handled = true;
            return true;
        }
        if (clone)
        {
            view.review.RenderCloneCursor();
        }
        return false;
    }

    internal bool TryHandleReleased(PointerRoutedEventArgs args)
    {
        if (TryFinishGuided(args))
        {
            args.Handled = true;
            return true;
        }
        if (TryFinishStroke(args))
        {
            args.Handled = true;
            return true;
        }
        return false;
    }

    internal bool TryHandleKey(KeyRoutedEventArgs args)
    {
        // 검토 중인 검출이 있으면 그것이 먼저입니다. 도움말이 안내하는 대로 Enter 가 받아들이고
        // Esc 가 버립니다.
        if (view.grainMend.PendingEdit is not null)
        {
            if (view.isRemovingDefects && args.Key == VirtualKey.Enter)
            {
                args.Handled = true;
                return true;
            }
            if (args.Key == VirtualKey.Enter)
            {
                _ = view.review.AcceptPendingAsync();
                args.Handled = true;
                return true;
            }
            if (args.Key == VirtualKey.Escape)
            {
                _ = view.TryExitRegionDefectInteraction();
                args.Handled = true;
                return true;
            }
        }
        if (args.Key == VirtualKey.Escape &&
            (view.grainMend.IsDetecting ||
             view.grainMend.Strokes.Tool != GrainMendTool.None))
        {
            args.Handled = view.TryExitRegionDefectInteraction();
            return args.Handled;
        }
        if (args.Key == VirtualKey.Enter &&
            view.grainMend.Strokes.Tool == GrainMendTool.Brush &&
            view.grainMend.Strokes.HasPaintedStrokes)
        {
            view.ApplyBrushDraft();
            args.Handled = true;
            return true;
        }
        return false;
    }

    internal void CancelActivePointer(PointerRoutedEventArgs args)
    {
        bool hadStroke = view.grainMend.Strokes.IsDragging;
        EndGuidedSelection(args);
        if (!hadStroke)
        {
            return;
        }
        view.grainMend.Strokes.CancelStroke();
        view.canvas?.ReleaseHost(args.Pointer);
        RenderActiveTool();
        view.chrome.Update();
    }

    internal void EndGuidedSelection(PointerRoutedEventArgs args)
    {
        if (!guidedDragging)
        {
            return;
        }
        guidedDragging = false;
        view.canvas?.ReleaseHost(args.Pointer);
        guidedFrameWidth = 0.0;
        guidedFrameHeight = 0.0;
        view.canvas?.HideGuidedSelection();
    }

    internal void CancelGuidedDrag()
    {
        guidedDragging = false;
        guidedFrameWidth = 0.0;
        guidedFrameHeight = 0.0;
        view.canvas?.HideGuidedSelection();
    }

    internal void RenderGuidedSelection()
    {
        if (!guidedDragging)
        {
            view.canvas?.HideGuidedSelection();
            return;
        }
        view.canvas?.ShowGuidedSelection(guidedDragStart, guidedDragCurrent);
    }

    private bool TryBeginGuided(PointerRoutedEventArgs args)
    {
        if (view.isRemovingDefects ||
            view.grainMend.Strokes.Tool != GrainMendTool.Guided || view.grainMend.IsDetecting ||
            view.panel?.SelectedFrame is null ||
            !TryMapGuided(
                args,
                out CropDisplayPoint point,
                out double frameWidth,
                out double frameHeight))
        {
            return false;
        }
        guidedDragStart = point;
        guidedDragCurrent = point;
        guidedFrameWidth = frameWidth;
        guidedFrameHeight = frameHeight;
        guidedDragging = true;
        RenderGuidedSelection();
        view.canvas?.CaptureHost(args.Pointer);
        return true;
    }

    /// <summary>
    /// 보류 중인 자동/가이드 마스크의 연결 성분을 클릭하면 포함과 제외를 바꿉니다. 이 단계는
    /// recipe를 건드리지 않으며, Enter 또는 제거 단추를 눌러야만 sidecar로 갑니다.
    /// </summary>
    private bool TryTogglePendingComponent(PointerRoutedEventArgs args)
    {
        return TryMap(args, out CropDisplayPoint displayPoint) &&
            TryTogglePendingComponent(displayPoint);
    }

    private bool TryTogglePendingComponent(CropDisplayPoint displayPoint)
    {
        if (view.isRemovingDefects || view.grainMend.IsDetecting ||
            view.grainMend.PendingReview is null || view.grainMend.PendingEdit is null ||
            view.panel?.SelectedFrame is not { SourceMetadata: { } metadata } frame ||
            !DevelopDisplayGeometry.TryMapDisplayToRaw(
                frame.ImageTransform,
                metadata.PixelWidth,
                metadata.PixelHeight,
                displayPoint.X,
                displayPoint.Y,
                out double rawX,
                out double rawY) ||
            !view.grainMend.ToggleReviewAtRaw(new DefectPoint(rawX, rawY)))
        {
            return false;
        }

        view.SetStatus(AppResources.FormatIntegers(
            "developGrainMendFoundFormat",
            "Value",
            view.grainMend.IncludedCount));
        view.review.ShowOverlay(view.grainMend.PendingEdit);
        view.chrome.Update();
        return true;
    }

    private bool TryContinueGuided(PointerRoutedEventArgs args)
    {
        if (!guidedDragging ||
            !TryMapGuided(args, out CropDisplayPoint point, out double frameWidth, out double frameHeight))
        {
            return false;
        }
        guidedDragCurrent = point;
        guidedFrameWidth = frameWidth;
        guidedFrameHeight = frameHeight;
        RenderGuidedSelection();
        return true;
    }

    private bool TryFinishGuided(PointerRoutedEventArgs args)
    {
        if (!guidedDragging)
        {
            return false;
        }
        if (TryMapGuided(
                args,
                out CropDisplayPoint point,
                out double frameWidth,
                out double frameHeight))
        {
            guidedDragCurrent = point;
            guidedFrameWidth = frameWidth;
            guidedFrameHeight = frameHeight;
        }
        guidedDragging = false;
        view.canvas?.ReleaseHost(args.Pointer);
        view.canvas?.HideGuidedSelection();

        GrainMendGuidedGestureResult result = GrainMendGuidedGesture.Complete(
            guidedDragStart,
            guidedDragCurrent,
            guidedFrameWidth,
            guidedFrameHeight);
        guidedFrameWidth = 0.0;
        guidedFrameHeight = 0.0;
        if (result.Kind == GrainMendGuidedGestureKind.Tap)
        {
            _ = TryTogglePendingComponent(guidedDragCurrent);
            return true;
        }
        if (result is not { Kind: GrainMendGuidedGestureKind.Region, Region: { } displayRoi } ||
            view.panel is null)
        {
            return true;
        }
        if (view.panel.TryMapDisplayRectToRaw(displayRoi, out DefectRect rawRoi))
        {
            _ = view.detector.DetectAsync(rawRoi, automatic: false);
        }
        return true;
    }

    /// <summary>
    /// 도구가 잡고 있으면 포인터를 가로챕니다. 크롭 세션과 같은 이벤트를 쓰므로 어느 쪽이
    /// 먼저인지가 분명해야 합니다 — 도구가 켜져 있으면 크롭은 이미 꺼져 있습니다.
    /// </summary>
    private bool TryBeginStroke(PointerRoutedEventArgs args)
    {
        if (view.panel?.SelectedFrame is null ||
            !TryMap(args, out CropDisplayPoint point))
        {
            return false;
        }

        bool alt = InputKeyboardSource
            .GetKeyStateForCurrentThread(Windows.System.VirtualKey.Menu)
            .HasFlag(CoreVirtualKeyStates.Down);
        if (view.grainMend.Strokes.Tool == GrainMendTool.Clone)
        {
            // macOS `current.last ?? hoverPoint` — 획이 시작되면 커서는 곧 그 획의 끝입니다.
            cloneCursor = new DefectPoint(point.X, point.Y);
        }
        bool handled = view.grainMend.Strokes.Begin(
            new DefectPoint(point.X, point.Y),
            alt);
        if (view.grainMend.Strokes.IsDragging)
        {
            view.canvas?.CaptureHost(args.Pointer);
        }
        if (handled && view.grainMend.Strokes.Tool == GrainMendTool.Clone)
        {
            // ⌥ 클릭으로 소스를 새로 잡았으면 십자선이 곧바로 그 자리로 갑니다.
            view.review.RenderCloneCursor();
        }
        return handled;
    }

    private bool TryContinueStroke(PointerRoutedEventArgs args)
    {
        if (!TryMapStroke(args, out CropDisplayPoint point))
        {
            return false;
        }
        if (!view.grainMend.Strokes.Continue(new DefectPoint(point.X, point.Y)))
        {
            return false;
        }
        RenderActiveTool();
        return true;
    }

    /// <summary>
    /// macOS 는 브러시와 복제 도장에 <b>서로 다른 오버레이</b>를 답니다 —
    /// <c>BrushOverlay</c> 는 칠하는 동안 빨강으로 보여 주고(획이 끝나야 보이면 어디를 칠했는지
    /// 모르고 칠합니다), <c>CloneStampOverlay</c> 는 빨강 대신 <b>소스 창의 실제 화소</b>를 획
    /// 모양으로 보여 줍니다. Windows 는 한 표면을 나눠 쓰므로 도구에 맞는 쪽을 그립니다.
    /// </summary>
    private bool RenderActiveTool()
    {
        if (view.grainMend.Strokes.Tool == GrainMendTool.Clone)
        {
            return view.review.RenderCloneCursor();
        }
        return view.review.RenderPaintOverlay();
    }

    private bool TryFinishStroke(PointerRoutedEventArgs args)
    {
        if (!view.grainMend.Strokes.IsDragging)
        {
            return false;
        }
        GrainMendPresentationSample presentation =
            view.grainMend.Strokes.Tool == GrainMendTool.Clone
                ? view.BeginManualPresentation(GrainMendTool.Clone)
                : default;
        if (view.panel is null)
        {
            view.grainMend.Strokes.CancelStroke();
            view.canvas?.ReleaseHost(args.Pointer);
            return true;
        }
        bool wasBrush = view.grainMend.Strokes.Tool == GrainMendTool.Brush;
        if (!view.grainMend.Strokes.Finish(view.panel, out LibraryFrameError error))
        {
            view.canvas?.ReleaseHost(args.Pointer);
            return false;
        }
        // ReleasePointerCapture는 PointerCaptureLost를 즉시 다시 보낼 수 있습니다. 먼저 Finish로
        // 획을 draft/recipe에 확정해야 재진입한 cancel이 완료 전 획을 지우지 않습니다.
        view.canvas?.ReleaseHost(args.Pointer);
        // 브러시는 recipe 로 가지 않고 칠로 남습니다(macOS 와 같은 "모았다가 적용").
        if (wasBrush)
        {
            view.review.RenderPaintOverlay();
            view.chrome.Update();
            return true;
        }
        if (error == LibraryFrameError.None)
        {
            view.SetStatus(string.Empty);
            view.chrome.Update();
            view.TrackDevelopedPresentation(presentation);
            view.RequestPreview();
        }
        else
        {
            view.ShowDefectWriteError();
            view.chrome.Update();
        }
        // macOS 는 획이 끝나면 `current` 가 비어 획 모양 미리보기가 사라지고, 원과 소스 십자선만
        // 남습니다. 이제 정렬 오프셋이 확정됐으므로 원 안에는 그 오프셋의 소스가 보입니다.
        RenderActiveTool();
        return true;
    }

    private bool TryMap(PointerRoutedEventArgs args, out CropDisplayPoint point)
    {
        if (view.canvas is null)
        {
            point = default;
            return false;
        }
        return view.canvas.TryMapPointer(args, out point);
    }

    private bool TryMapStroke(PointerRoutedEventArgs args, out CropDisplayPoint point)
    {
        if (view.grainMend.Strokes.Tool != GrainMendTool.Brush || view.canvas is null)
        {
            return TryMap(args, out point);
        }
        return view.canvas.TryMapPointerForCrop(
            args,
            double.PositiveInfinity,
            out point,
            out _,
            out _,
            out _);
    }

    private bool TryMapGuided(
        PointerRoutedEventArgs args,
        out CropDisplayPoint point,
        out double frameWidth,
        out double frameHeight)
    {
        if (view.canvas is null)
        {
            point = default;
            frameWidth = 0.0;
            frameHeight = 0.0;
            return false;
        }
        return view.canvas.TryMapPointerForCrop(
            args,
            0.0,
            out point,
            out bool inside,
            out frameWidth,
            out frameHeight) && inside;
    }
}
