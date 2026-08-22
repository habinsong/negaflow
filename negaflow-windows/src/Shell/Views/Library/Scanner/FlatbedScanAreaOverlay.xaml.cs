using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;

namespace Negaflow.Shell.Views.Library.Scanner;

/// <summary>
/// 평판 프리뷰 그림과 그 위의 프레임 사각형입니다. macOS <c>FlatbedScanAreaOverlay</c> 를
/// 그대로 옮긴 것이며, 셈은 <see cref="FlatbedOverlayGeometry"/> 가 합니다.
/// </summary>
/// <remarks>
/// macOS 는 이 오버레이를 캔버스(프리뷰 프레임을 띄운 큰 그림) 위에 얹습니다. Windows
/// 라이브러리에는 한 장을 크게 띄우는 캔버스가 없어, 프리뷰가 살아 있는 동안 격자 자리를
/// 이 오버레이가 차지합니다 - 프레임을 눈으로 보고 손으로 고칠 자리가 달리 없습니다.
/// </remarks>
public sealed partial class FlatbedScanAreaOverlay : UserControl
{
    private ScanSessionController? session;

    private string? loadedPreviewPath;

    private double imagePixelWidth;

    private double imagePixelHeight;

    public FlatbedScanAreaOverlay()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    /// <summary>사용자가 프레임을 고치면 부릅니다. 패널이 개수 표시를 다시 그립니다.</summary>
    public event EventHandler? RegionsChanged;

    /// <summary>지금 그려진 프레임 사각형입니다. 화면 좌표이며 시험이 읽습니다.</summary>
    internal IReadOnlyList<FlatbedOverlayRect> ScreenRects =>
        [.. Regions.Select(region => FlatbedOverlayGeometry.ScreenRect(region, ImageFrame))];

    internal IReadOnlyList<FlatbedScanRegion> Regions => session?.Regions ?? [];

    /// <summary>그림이 실제로 그려진 자리입니다. 프레임 비율을 여기에 폅니다.</summary>
    internal FlatbedOverlayRect ImageFrame { get; private set; }

    public void Attach(ScanSessionController controller)
    {
        ArgumentNullException.ThrowIfNull(controller);
        session = controller;
    }

    /// <summary>
    /// 프리뷰 그림과 프레임을 다시 그립니다. 스캔이 끝나거나 프레임이 바뀔 때마다 부릅니다.
    /// </summary>
    public void Render(string? previewPath)
    {
        if (session is null)
        {
            return;
        }
        bool hasPreview = previewPath is { Length: > 0 } && File.Exists(previewPath);
        if (!hasPreview)
        {
            PreviewImage.Source = null;
            loadedPreviewPath = null;
            imagePixelWidth = 0;
            imagePixelHeight = 0;
            RegionLayer.Children.Clear();
            return;
        }

        if (!string.Equals(loadedPreviewPath, previewPath, StringComparison.OrdinalIgnoreCase))
        {
            LoadPreview(previewPath!);
        }
        LayoutRegions();
    }

    private void OnLoaded(object sender, RoutedEventArgs args)
    {
        // 방향키와 Ctrl+C/V 를 받으려면 포커스가 필요합니다. macOS 도 오버레이가 포커스를
        // 가진 동안에만 그 단축키를 살립니다 - 그래야 옆 글상자의 복사를 빼앗지 않습니다.
        _ = Focus(FocusState.Programmatic);
    }

    private void LoadPreview(string previewPath)
    {
        try
        {
            BitmapImage bitmap = new()
            {
                // 프리뷰는 프레임을 눈으로 확인하는 용도라 원본 해상도가 필요 없습니다.
                // 긴 변을 제한해 8 bit 로 접으면 큰 평판 스캔도 한 화면 분량만 씁니다.
                DecodePixelType = DecodePixelType.Logical,
                DecodePixelHeight = 1600,
                UriSource = new Uri(previewPath),
            };
            bitmap.ImageOpened += OnPreviewOpened;
            bitmap.ImageFailed += OnPreviewFailed;
            PreviewImage.Source = bitmap;
            loadedPreviewPath = previewPath;
        }
        catch (Exception error) when (error is UriFormatException or ArgumentException)
        {
            // 읽지 못한 프리뷰는 없는 프리뷰입니다. 빈 자리를 보여 주고 넘어갑니다.
            PreviewImage.Source = null;
            loadedPreviewPath = null;
        }
    }

    private void OnPreviewOpened(object sender, RoutedEventArgs args)
    {
        if (sender is not BitmapImage bitmap)
        {
            return;
        }
        imagePixelWidth = bitmap.PixelWidth;
        imagePixelHeight = bitmap.PixelHeight;
        LayoutRegions();
    }

    private void OnPreviewFailed(object sender, ExceptionRoutedEventArgs args)
    {
        PreviewImage.Source = null;
        loadedPreviewPath = null;
        imagePixelWidth = 0;
        imagePixelHeight = 0;
        RegionLayer.Children.Clear();
    }

    private void OnHostSizeChanged(object sender, SizeChangedEventArgs args) => LayoutRegions();

    private void NotifyChanged() => RegionsChanged?.Invoke(this, EventArgs.Empty);
}
