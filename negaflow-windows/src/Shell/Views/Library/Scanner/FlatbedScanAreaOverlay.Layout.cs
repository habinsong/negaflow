using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;
using Microsoft.UI;
using Windows.UI;

namespace Negaflow.Shell.Views.Library.Scanner;

/// <summary>
/// 프레임 사각형을 그립니다. macOS <c>regionView(_:number:)</c> 와 같은 모양입니다 -
/// 선택한 것은 강조색 2px 테두리에 9% 채움, 나머지는 흰색 1px 테두리에 4% 채움이고,
/// 왼쪽 위에 번호 캡슐이 붙습니다.
/// </summary>
public sealed partial class FlatbedScanAreaOverlay
{
    /// <summary>번호 캡슐의 여백입니다. macOS `.padding(5)` 와 같습니다.</summary>
    private const double BadgeInset = 5.0;

    /// <summary>지금 그려 둔 사각형입니다. 다시 그릴 때 자리만 옮겨 씁니다.</summary>
    private readonly Dictionary<string, RegionVisual> visuals = [];

    private sealed record RegionVisual(
        Border Body,
        Border Badge,
        TextBlock BadgeText,
        List<Border> Handles);

    /// <summary>
    /// 프리뷰 그림이 그려진 자리를 다시 재고 프레임을 그 위에 폅니다. 창 크기나 프레임
    /// 목록이 바뀔 때마다 부릅니다.
    /// </summary>
    private void LayoutRegions()
    {
        // 현상 캔버스에 얹을 때는 사진을 캔버스가 그립니다. 줌·팬이 이미 들어간 그 자리를
        // 그대로 받아야 프레임이 사진을 따라갑니다 - macOS 도 `canvasFittedImageFrame` 하나를
        // `imageLayer` 와 `FlatbedScanAreaOverlay` 에 똑같이 넘깁니다(`CanvasView.swift`).
        FlatbedOverlayRect previousFrame = ImageFrame;
        ImageFrame = externalImageFrame ?? FlatbedOverlayGeometry.FittedImageFrame(
            imagePixelWidth,
            imagePixelHeight,
            Host.ActualWidth,
            Host.ActualHeight);
        // 끌고 있는 중에 사진 자리가 움직였으면 기준도 같이 옮깁니다. 안 그러면 다음 이동
        // 때 옛 화면 좌표를 새 자리에 대고 재게 되어, 손가락은 가만히 있는데 스캔 영역이
        // 줌 배율만큼 커지거나 작아집니다(휠로 확대·축소할 때 보고됨).
        RebaseDrag(previousFrame);
        if (ImageFrame.Width <= 0 || ImageFrame.Height <= 0)
        {
            RegionLayer.Children.Clear();
            visuals.Clear();
            return;
        }

        IReadOnlyList<FlatbedScanRegion> regions = Regions;
        HashSet<string> live = [.. regions.Select(region => region.Id)];
        foreach (string stale in visuals.Keys.Where(id => !live.Contains(id)).ToArray())
        {
            RemoveVisual(stale);
        }

        bool transformed = TryPreviewTransform(out ImageTransformRecipe previewTransform, out uint sourceWidth, out uint sourceHeight);
        session?.SetPreviewGeometry(transformed ? previewTransform : null, sourceWidth, sourceHeight);
        string? selectedId = session?.SelectedRegionId;
        for (int index = 0; index < regions.Count; ++index)
        {
            FlatbedScanRegion region = regions[index];
            FlatbedRegionScreenShape shape = Shape(region);
            bool selected = string.Equals(region.Id, selectedId, StringComparison.Ordinal);
            RegionVisual visual = EnsureVisual(region.Id);
            ApplyVisual(visual, shape, index + 1, selected);
        }
    }

    private RegionVisual EnsureVisual(string regionId)
    {
        if (visuals.TryGetValue(regionId, out RegionVisual? existing))
        {
            return existing;
        }

        TextBlock badgeText = new()
        {
            FontSize = 11,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            IsHitTestVisible = false,
        };
        Border badge = new()
        {
            CornerRadius = new CornerRadius(9),
            Padding = new Thickness(5, 2, 5, 2),
            Child = badgeText,
            IsHitTestVisible = false,
        };
        Border body = new()
        {
            BorderThickness = new Thickness(1),
            Tag = regionId,
        };
        body.PointerPressed += OnRegionPointerPressed;
        body.PointerMoved += OnRegionPointerMoved;
        body.PointerReleased += OnRegionPointerReleased;
        body.PointerCaptureLost += OnRegionPointerReleased;

        List<Border> handles = [];
        foreach (FlatbedRegionHandle handle in Enum.GetValues<FlatbedRegionHandle>())
        {
            Border grip = BuildHandle(regionId, handle);
            handles.Add(grip);
        }

        RegionVisual created = new(body, badge, badgeText, handles);
        RegionLayer.Children.Add(body);
        RegionLayer.Children.Add(badge);
        foreach (Border grip in handles)
        {
            RegionLayer.Children.Add(grip);
        }
        visuals[regionId] = created;
        return created;
    }

    private Border BuildHandle(string regionId, FlatbedRegionHandle handle)
    {
        (double width, double height) = FlatbedOverlayGeometry.HandleSize(handle);
        Rectangle knob = new()
        {
            Width = width,
            Height = height,
            RadiusX = 2,
            RadiusY = 2,
            Fill = new SolidColorBrush(Colors.White),
            Stroke = AccentBrush(1.0),
            StrokeThickness = 1,
        };
        Border grip = new()
        {
            Width = FlatbedOverlayGeometry.HandleHitSize,
            Height = FlatbedOverlayGeometry.HandleHitSize,
            // 손잡이는 눈에 보이는 것보다 넓게 집힙니다. 배경이 없으면 WinUI 가 집지
            // 못하므로 투명을 칠합니다.
            Background = new SolidColorBrush(Colors.Transparent),
            Child = knob,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Tag = new HandleTag(regionId, handle),
            Visibility = Visibility.Collapsed,
        };
        grip.PointerPressed += OnHandlePointerPressed;
        grip.PointerMoved += OnHandlePointerMoved;
        grip.PointerReleased += OnHandlePointerReleased;
        grip.PointerCaptureLost += OnHandlePointerReleased;
        return grip;
    }

    /// <summary>
    /// 칸을 기운 그대로 그립니다. 몸통·번호·손잡이를 같은 각도로 돌립니다 — WinUI 는 돌린 요소의
    /// 집는 자리도 함께 돌립니다.
    /// </summary>
    private void ApplyVisual(
        RegionVisual visual,
        FlatbedRegionScreenShape shape,
        int number,
        bool selected)
    {
        double degrees = shape.Angle * 180.0 / Math.PI;
        double width = Math.Max(shape.Width, 0);
        double height = Math.Max(shape.Height, 0);
        visual.Body.Width = width;
        visual.Body.Height = height;
        Canvas.SetLeft(visual.Body, shape.CenterX - (width / 2));
        Canvas.SetTop(visual.Body, shape.CenterY - (height / 2));
        visual.Body.RenderTransform = new RotateTransform { Angle = degrees, CenterX = width / 2, CenterY = height / 2 };
        visual.Body.Background = selected ? AccentBrush(0.09) : BlackBrush(0.04);
        visual.Body.BorderBrush = selected ? AccentBrush(1.0) : new SolidColorBrush(Colors.White);
        visual.Body.BorderThickness = new Thickness(selected ? 2 : 1);

        visual.BadgeText.Text = number.ToString(
            System.Globalization.CultureInfo.CurrentCulture);
        visual.BadgeText.Foreground = selected
            ? new SolidColorBrush(Colors.White)
            : (Brush)Application.Current.Resources["TextFillColorPrimaryBrush"];
        visual.Badge.Background = selected ? AccentBrush(1.0) : WhiteBrush(0.82);
        (double badgeX, double badgeY) = shape.ScreenPoint(BadgeInset, BadgeInset);
        Canvas.SetLeft(visual.Badge, badgeX);
        Canvas.SetTop(visual.Badge, badgeY);
        visual.Badge.RenderTransform = new RotateTransform { Angle = degrees };

        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(
            visual.Body,
            AppResources.FormatInteger("scanFlatbedFrameFormat", "Text", number));

        foreach (Border grip in visual.Handles)
        {
            if (grip.Tag is not HandleTag tag)
            {
                continue;
            }
            grip.Visibility = selected ? Visibility.Visible : Visibility.Collapsed;
            if (!selected)
            {
                continue;
            }
            (double localX, double localY) = FlatbedOverlayGeometry.HandlePoint(tag.Handle, width, height);
            (double x, double y) = shape.ScreenPoint(localX, localY);
            const double half = FlatbedOverlayGeometry.HandleHitSize / 2;
            Canvas.SetLeft(grip, x - half);
            Canvas.SetTop(grip, y - half);
            grip.RenderTransform = new RotateTransform { Angle = degrees, CenterX = half, CenterY = half };
        }
    }

    private void RemoveVisual(string regionId)
    {
        if (!visuals.Remove(regionId, out RegionVisual? visual))
        {
            return;
        }
        _ = RegionLayer.Children.Remove(visual.Body);
        _ = RegionLayer.Children.Remove(visual.Badge);
        foreach (Border grip in visual.Handles)
        {
            _ = RegionLayer.Children.Remove(grip);
        }
    }

    private static SolidColorBrush BlackBrush(double opacity) =>
        new(Color.FromArgb((byte)Math.Round(opacity * 255), 0, 0, 0));

    private static SolidColorBrush WhiteBrush(double opacity) =>
        new(Color.FromArgb((byte)Math.Round(opacity * 255), 255, 255, 255));

    private static SolidColorBrush AccentBrush(double opacity)
    {
        Color accent = Application.Current.Resources["SystemAccentColor"] is Color value
            ? value
            : Color.FromArgb(255, 0, 120, 212);
        return new SolidColorBrush(
            Color.FromArgb((byte)Math.Round(opacity * 255), accent.R, accent.G, accent.B));
    }

    private sealed record HandleTag(string RegionId, FlatbedRegionHandle Handle);
}
