using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Develop.Perspective;
using Negaflow.Shell.Diagnostics;
using Negaflow.Shell.Localization;
using Windows.Foundation;

namespace Negaflow.Shell.Views.Develop.Host;

/// <summary>
/// 변환 자동 모드의 풀이와 도우미 안내선입니다. macOS <c>AppModel+PerspectiveControls</c> 와
/// <c>PerspectiveGuideOverlay</c> 자리입니다.
/// </summary>
/// <remarks>
/// 안내선은 원근 보정 앞 좌표에 저장하고, 손을 뗄 때 한 번만 다시 풉니다. 끄는 도중에 풀면 그림이
/// 바뀌면서 손가락 아래 점의 원래 좌표도 바뀌어 끝점이 미끄러집니다.
/// </remarks>
internal sealed class DevelopPerspectiveHost
{
    private const double EndpointHitRadius = 11.0;
    private readonly DevelopWorkspaceView view;
    private Point? draftStart;
    private Point draftEnd;
    private (int Index, bool IsStart)? moving;
    private Point movingPoint;

    internal DevelopPerspectiveHost(DevelopWorkspaceView view) => this.view = view;

    internal void Hook()
    {
        view.Adjustments.Transform.AutoSolveRequested += OnAutoSolveRequested;
        view.PreviewCanvas.ImageFrameChanged += (_, _) => Render();
    }

    private DevelopPanelState? Panel => view.panel;

    /// <summary>도우미 모드이고 다른 캔버스 도구가 없을 때만 안내선을 다룹니다.</summary>
    internal bool IsActive =>
        Panel?.SelectedFrame?.ImageTransform.Perspective.Mode == PerspectiveMode.Guided &&
        !view.crop.IsActive && view.PreviewCanvas.HasPreview;

    private async void OnAutoSolveRequested(object? sender, PerspectiveMode mode)
    {
        _ = sender;
        if (Panel?.SelectedFrame is not { } frame || view.PreviewCanvas.PreviewPixels is not { } pixels ||
            view.PreviewCanvas.PreviewBitmap is not { } bitmap)
        {
            return;
        }
        string frameId = frame.Id;
        // 선은 화면 그림에서 찾으므로 그 그림을 그린 변형으로 되돌려야 맞습니다.
        ImageTransformRecipe transform = view.PreviewCanvas.PreviewTransform ?? frame.ImageTransform;
        uint width = frame.SourceMetadata?.PixelWidth ?? 0U;
        uint height = frame.SourceMetadata?.PixelHeight ?? 0U;
        int displayWidth = bitmap.PixelWidth, displayHeight = bitmap.PixelHeight;
        byte[] copy = (byte[])pixels.Clone();
        PerspectiveSolution? solution = await Task.Run(() => PerspectiveWorkflow.SolveFromDisplay(
            copy, displayWidth, displayHeight, transform, width, height, mode));
        // 그 사이 다른 사진을 골랐거나, 사진을 돌렸거나, 다른 모드를 골랐으면 버립니다.
        if (Panel?.SelectedFrame is not { } current || current.Id != frameId ||
            current.ImageTransform.Rotation != transform.Rotation ||
            current.ImageTransform.FlipHorizontal != transform.FlipHorizontal ||
            current.ImageTransform.FlipVertical != transform.FlipVertical ||
            current.ImageTransform.Perspective.Mode != mode)
        {
            return;
        }
        if (Panel.SetPerspective(p => p with
            {
                SolvedVertical = solution?.Vertical ?? 0,
                SolvedHorizontal = solution?.Horizontal ?? 0,
                SolvedRotate = solution?.Rotate ?? 0,
            }) == LibraryFrameError.None)
        {
            view.RequestPreview();
        }
        if (solution is null)
        {
            AppStatusMessage.Shared.Post(AppResources.Get("transformAutoNoLines", "Text"));
        }
    }

    internal bool TryPressed(PointerRoutedEventArgs args)
    {
        if (!IsActive || !args.GetCurrentPoint(view.PreviewCanvas.CanvasHost).Properties.IsLeftButtonPressed)
        {
            return false;
        }
        Point point = args.GetCurrentPoint(view.PreviewCanvas.CanvasHost).Position;
        IReadOnlyList<PerspectiveGuideRecipe> guides = Guides();
        for (int index = 0; index < guides.Count; ++index)
        {
            if (Screen(guides[index].StartX, guides[index].StartY) is { } start && Near(start, point))
            {
                moving = (index, true);
            }
            else if (Screen(guides[index].EndX, guides[index].EndY) is { } end && Near(end, point))
            {
                moving = (index, false);
            }
            if (moving is not null)
            {
                movingPoint = point;
                break;
            }
        }
        if (moving is null)
        {
            if (guides.Count >= PerspectiveRecipe.MaximumGuides || !InsideImage(point))
            {
                return false;
            }
            draftStart = point;
            draftEnd = point;
        }
        view.PreviewCanvas.CaptureHost(args.Pointer);
        Render();
        args.Handled = true;
        return true;
    }

    internal bool TryMoved(PointerRoutedEventArgs args)
    {
        if (draftStart is null && moving is null)
        {
            return false;
        }
        Point point = ClampToImage(args.GetCurrentPoint(view.PreviewCanvas.CanvasHost).Position);
        if (moving is not null)
        {
            movingPoint = point;
        }
        else
        {
            draftEnd = point;
        }
        Render();
        args.Handled = true;
        return true;
    }

    internal bool TryReleased(PointerRoutedEventArgs args)
    {
        if (draftStart is null && moving is null)
        {
            return false;
        }
        view.PreviewCanvas.ReleaseHost(args.Pointer);
        List<PerspectiveGuideRecipe> guides = [.. Guides()];
        if (moving is { } target && target.Index < guides.Count &&
            Oriented(movingPoint) is { } moved)
        {
            PerspectiveGuideRecipe guide = guides[target.Index];
            guides[target.Index] = target.IsStart
                ? guide with { StartX = moved.X, StartY = moved.Y }
                : guide with { EndX = moved.X, EndY = moved.Y };
            Commit(guides);
        }
        else if (draftStart is { } start && Distance(start, draftEnd) >= 12 &&
                 Oriented(start) is { } a && Oriented(draftEnd) is { } b)
        {
            guides.Add(new PerspectiveGuideRecipe(a.X, a.Y, b.X, b.Y));
            Commit(guides);
        }
        draftStart = null;
        moving = null;
        Render();
        args.Handled = true;
        return true;
    }

    internal void Cancel()
    {
        draftStart = null;
        moving = null;
        Render();
    }

    private void Commit(List<PerspectiveGuideRecipe> guides)
    {
        if (Panel?.SelectedFrame is not { } frame)
        {
            return;
        }
        uint width = frame.SourceMetadata?.PixelWidth ?? 0U;
        uint height = frame.SourceMetadata?.PixelHeight ?? 0U;
        if (Panel.SetPerspective(p => PerspectiveWorkflow.WithGuidedSolution(
                p with { Guides = guides }, frame.ImageTransform, width, height)) == LibraryFrameError.None)
        {
            view.Adjustments.Transform.Show(Panel);
            view.RequestPreview();
        }
    }

    /// <summary>안내선을 다시 그립니다. 끌고 있는 끝은 손가락 자리에 둡니다.</summary>
    internal void Render()
    {
        var layer = view.PreviewCanvas.PerspectiveGuideLayer;
        layer.Children.Clear();
        if (!IsActive)
        {
            layer.Visibility = Visibility.Collapsed;
            return;
        }
        layer.Visibility = Visibility.Visible;
        IReadOnlyList<PerspectiveGuideRecipe> guides = Guides();
        for (int index = 0; index < guides.Count; ++index)
        {
            Point? start = Screen(guides[index].StartX, guides[index].StartY);
            Point? end = Screen(guides[index].EndX, guides[index].EndY);
            if (moving is { } target && target.Index == index)
            {
                if (target.IsStart) { start = movingPoint; } else { end = movingPoint; }
            }
            if (start is { } a && end is { } b)
            {
                AddLine(layer, a, b);
                AddHandle(layer, a);
                AddHandle(layer, b);
            }
        }
        if (draftStart is { } draft)
        {
            AddLine(layer, draft, draftEnd);
        }
    }

    private static void AddLine(Microsoft.UI.Xaml.Controls.Canvas layer, Point a, Point b)
    {
        layer.Children.Add(new Line
        {
            X1 = a.X, Y1 = a.Y, X2 = b.X, Y2 = b.Y,
            Stroke = new SolidColorBrush(Windows.UI.Color.FromArgb(0x8C, 0, 0, 0)),
            StrokeThickness = 3,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
        });
        layer.Children.Add(new Line
        {
            X1 = a.X, Y1 = a.Y, X2 = b.X, Y2 = b.Y,
            Stroke = new SolidColorBrush(Windows.UI.Color.FromArgb(0xFF, 0xFF, 0xD8, 0x4A)),
            StrokeThickness = 1.5,
        });
    }

    private static void AddHandle(Microsoft.UI.Xaml.Controls.Canvas layer, Point point)
    {
        Ellipse handle = new()
        {
            Width = 10,
            Height = 10,
            Fill = new SolidColorBrush(Colors.White),
            Stroke = new SolidColorBrush(Windows.UI.Color.FromArgb(0x80, 0, 0, 0)),
            StrokeThickness = 1,
        };
        Microsoft.UI.Xaml.Controls.Canvas.SetLeft(handle, point.X - 5);
        Microsoft.UI.Xaml.Controls.Canvas.SetTop(handle, point.Y - 5);
        layer.Children.Add(handle);
    }

    private IReadOnlyList<PerspectiveGuideRecipe> Guides() =>
        Panel?.SelectedFrame?.ImageTransform.Perspective.Guides ?? [];

    /// <summary>원근 보정 앞 좌표 → 화면 자리.</summary>
    private Point? Screen(double x, double y)
    {
        if (Panel?.SelectedFrame is not { } frame || !view.PreviewCanvas.TryGetPreviewFrame(out PreviewFrame image))
        {
            return null;
        }
        ImageTransformRecipe transform = frame.ImageTransform;
        (double rawX, double rawY) = PerspectiveWorkflow.OrientedToRaw(transform, x, y);
        return DevelopDisplayGeometry.TryMapRawToDisplay(
                transform, frame.SourceMetadata?.PixelWidth ?? 0U, frame.SourceMetadata?.PixelHeight ?? 0U,
                rawX, rawY, out double displayX, out double displayY)
            ? new Point(image.Left + (displayX * image.Width), image.Top + (displayY * image.Height))
            : null;
    }

    /// <summary>화면 자리 → 원근 보정 앞 좌표.</summary>
    private (double X, double Y)? Oriented(Point point)
    {
        if (Panel?.SelectedFrame is not { } frame || !view.PreviewCanvas.TryGetPreviewFrame(out PreviewFrame image))
        {
            return null;
        }
        ImageTransformRecipe transform = frame.ImageTransform;
        double displayX = (point.X - image.Left) / Math.Max(image.Width, 1);
        double displayY = (point.Y - image.Top) / Math.Max(image.Height, 1);
        return DevelopDisplayGeometry.TryMapDisplayToRaw(
                transform, frame.SourceMetadata?.PixelWidth ?? 0U, frame.SourceMetadata?.PixelHeight ?? 0U,
                displayX, displayY, out double rawX, out double rawY)
            ? PerspectiveWorkflow.RawToOriented(transform, rawX, rawY)
            : null;
    }

    private bool InsideImage(Point point) =>
        view.PreviewCanvas.TryGetPreviewFrame(out PreviewFrame image) &&
        point.X >= image.Left && point.Y >= image.Top &&
        point.X <= image.Left + image.Width && point.Y <= image.Top + image.Height;

    private Point ClampToImage(Point point) =>
        view.PreviewCanvas.TryGetPreviewFrame(out PreviewFrame image)
            ? new Point(Math.Clamp(point.X, image.Left, image.Left + image.Width),
                Math.Clamp(point.Y, image.Top, image.Top + image.Height))
            : point;

    private static bool Near(Point a, Point b) => Distance(a, b) <= EndpointHitRadius;

    private static double Distance(Point a, Point b) =>
        Math.Sqrt(((a.X - b.X) * (a.X - b.X)) + ((a.Y - b.Y) * (a.Y - b.Y)));
}
