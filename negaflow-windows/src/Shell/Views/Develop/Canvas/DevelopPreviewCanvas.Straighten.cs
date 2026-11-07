using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Shortcuts;
using Windows.Foundation;
using Windows.System;
using Windows.UI.Core;

namespace Negaflow.Shell.Views.Develop.Canvas;

/// <summary>
/// 크롭 중 조합키 + 드래그로 기준선을 그려 수평을 맞추고, 조합키를 누르고 있는 동안 촘촘한 격자를
/// 보여 줍니다. macOS <c>CropOverlay</c> 의 기준선·격자와 같은 동작이며 키는 설정에서 바꿉니다.
/// </summary>
public sealed partial class DevelopPreviewCanvas
{
    private Point? straightenStart;
    private Point straightenEnd;

    /// <summary>기준선을 그리는 조합키입니다. 기본 Ctrl.</summary>
    public WorkflowShortcutModifiers StraightenLineModifier { get; set; } = WorkflowShortcutModifiers.Control;

    /// <summary>격자를 보여 주는 조합키입니다. 기본 Alt.</summary>
    public WorkflowShortcutModifiers StraightenGridModifier { get; set; } = WorkflowShortcutModifiers.Alt;

    /// <summary>기준선을 놓았을 때의 회전량(도, 양수 = 시계방향)입니다. 뷰가 지금 각도에 더합니다.</summary>
    public event EventHandler<double>? StraightenCorrectionRequested;

    private static WorkflowShortcutModifiers HeldModifiers()
    {
        static bool Down(VirtualKey key) =>
            InputKeyboardSource.GetKeyStateForCurrentThread(key).HasFlag(CoreVirtualKeyStates.Down);
        WorkflowShortcutModifiers held = WorkflowShortcutModifiers.None;
        if (Down(VirtualKey.Control)) { held |= WorkflowShortcutModifiers.Control; }
        if (Down(VirtualKey.Menu)) { held |= WorkflowShortcutModifiers.Alt; }
        if (Down(VirtualKey.Shift)) { held |= WorkflowShortcutModifiers.Shift; }
        return held;
    }

    private bool TryBeginStraighten(PointerRoutedEventArgs args)
    {
        if (crop is not { IsActive: true } ||
            !WorkflowGestureModifierActions.IsHeld(StraightenLineModifier, HeldModifiers()) ||
            !args.GetCurrentPoint(CanvasHost).Properties.IsLeftButtonPressed)
        {
            return false;
        }
        Point position = ClampToCropFrame(args.GetCurrentPoint(CanvasHost).Position);
        straightenStart = position;
        straightenEnd = position;
        CaptureHost(args.Pointer);
        RenderStraightenLine();
        args.Handled = true;
        return true;
    }

    private bool TryContinueStraighten(PointerRoutedEventArgs args)
    {
        if (straightenStart is null)
        {
            RefreshStraightenGrid();
            return false;
        }
        straightenEnd = ClampToCropFrame(args.GetCurrentPoint(CanvasHost).Position);
        RenderStraightenLine();
        args.Handled = true;
        return true;
    }

    private bool TryEndStraighten(PointerRoutedEventArgs args)
    {
        if (straightenStart is not { } start)
        {
            return false;
        }
        straightenEnd = ClampToCropFrame(args.GetCurrentPoint(CanvasHost).Position);
        Point end = straightenEnd;
        CancelStraighten();
        ReleaseHost(args.Pointer);
        args.Handled = true;
        if (CropInteraction.StraightenCorrection(start.X, start.Y, end.X, end.Y) is { } correction)
        {
            StraightenCorrectionRequested?.Invoke(this, correction);
        }
        return true;
    }

    private void CancelStraighten()
    {
        straightenStart = null;
        CropStraightenLine.Visibility = Visibility.Collapsed;
        CropStraightenLineShadow.Visibility = Visibility.Collapsed;
        RefreshStraightenGrid();
    }

    private void RenderStraightenLine()
    {
        if (straightenStart is not { } start)
        {
            return;
        }
        foreach (Microsoft.UI.Xaml.Shapes.Line line in new[] { CropStraightenLineShadow, CropStraightenLine })
        {
            line.X1 = start.X;
            line.Y1 = start.Y;
            line.X2 = straightenEnd.X;
            line.Y2 = straightenEnd.Y;
            line.Visibility = Visibility.Visible;
        }
        RefreshStraightenGrid();
    }

    /// <summary>
    /// 격자는 기준선을 그리는 동안, 또는 격자 조합키를 누르고 있는 동안 보입니다. 선택 사각형 위에
    /// 24px 안팎 간격으로 긋습니다(macOS 와 같은 간격).
    /// </summary>
    private void RefreshStraightenGrid()
    {
        bool show = crop is { IsActive: true } && CropOverlay.Visibility == Visibility.Visible &&
            (straightenStart is not null ||
             WorkflowGestureModifierActions.IsHeld(StraightenGridModifier, HeldModifiers()));
        if (!show)
        {
            CropFineGrid.Visibility = Visibility.Collapsed;
            return;
        }
        double left = Microsoft.UI.Xaml.Controls.Canvas.GetLeft(CropSelection);
        double top = Microsoft.UI.Xaml.Controls.Canvas.GetTop(CropSelection);
        double width = CropSelection.Width, height = CropSelection.Height;
        if (!double.IsFinite(width) || !double.IsFinite(height) || width < 8 || height < 8)
        {
            CropFineGrid.Visibility = Visibility.Collapsed;
            return;
        }
        const double spacing = 24.0;
        int columns = Math.Max((int)Math.Round(width / spacing), 4);
        int rows = Math.Max((int)Math.Round(height / spacing), 4);
        GeometryGroup group = new();
        for (int i = 1; i < columns; ++i)
        {
            double x = left + (width * i / columns);
            group.Children.Add(new LineGeometry { StartPoint = new Point(x, top), EndPoint = new Point(x, top + height) });
        }
        for (int i = 1; i < rows; ++i)
        {
            double y = top + (height * i / rows);
            group.Children.Add(new LineGeometry { StartPoint = new Point(left, y), EndPoint = new Point(left + width, y) });
        }
        CropFineGrid.Data = group;
        CropFineGrid.Visibility = Visibility.Visible;
    }

    private Point ClampToCropFrame(Point position)
    {
        if (crop is { OverlayFrame: { } frame })
        {
            return new Point(
                Math.Clamp(position.X, frame.Left, frame.Left + frame.Width),
                Math.Clamp(position.Y, frame.Top, frame.Top + frame.Height));
        }
        return position;
    }

    private void OnCanvasKeyUp(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        RefreshStraightenGrid();
    }
}
