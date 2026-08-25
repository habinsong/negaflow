using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using System.Runtime.InteropServices.WindowsRuntime;
using Negaflow.Catalog;
using Negaflow.Shell.Library;

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

    private LibraryFrameSnapshot? previewFrame;

    private ThumbnailService? previewCache;

    private WriteableBitmap? developedBitmap;

    public FlatbedScanAreaOverlay()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    /// <summary>사용자가 프레임을 고치면 부릅니다. 패널이 개수 표시를 다시 그립니다.</summary>
    public event EventHandler? RegionsChanged;

    /// <summary>지금 그려진 프레임 사각형입니다. 화면 좌표이며 시험이 읽습니다.</summary>
    internal IReadOnlyList<FlatbedOverlayRect> ScreenRects =>
        [.. Regions.Select(ScreenRect)];

    internal IReadOnlyList<FlatbedScanRegion> Regions => session?.Regions ?? [];

    /// <summary>그림이 실제로 그려진 자리입니다. 프레임 비율을 여기에 폅니다.</summary>
    internal FlatbedOverlayRect ImageFrame { get; private set; }

    private FlatbedOverlayRect? externalImageFrame;

    /// <summary>
    /// 사진을 <b>바깥이 그리는</b> 자리에 얹습니다. 현상 캔버스가 줌·팬까지 넣어 계산한
    /// 프레임을 그대로 받아 씁니다. 이 판에서는 자기 그림을 그리지 않습니다.
    /// </summary>
    internal void UseExternalImage()
    {
        PreviewImage.Visibility = Microsoft.UI.Xaml.Visibility.Collapsed;
        drawsOwnImage = false;
    }

    /// <summary>바깥이 그린 사진의 자리입니다. 줌·팬이 바뀔 때마다 부릅니다.</summary>
    internal void SetExternalImageFrame(double left, double top, double width, double height)
    {
        externalImageFrame = new FlatbedOverlayRect(left, top, width, height);
        LayoutRegions();
    }

    private bool drawsOwnImage = true;

    public void Attach(
        ScanSessionController controller,
        LibraryFrameSnapshot? frame,
        ThumbnailService? cache)
    {
        ArgumentNullException.ThrowIfNull(controller);
        session = controller;
        previewFrame = frame;
        previewCache = cache;
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
            previewFrame = null;
            RegionLayer.Children.Clear();
            return;
        }

        if (!drawsOwnImage)
        {
            // 사진은 캔버스가 그립니다. 프레임만 다시 폅니다.
            LayoutRegions();
            return;
        }
        if (TryPresentDeveloped())
        {
            LayoutRegions();
            return;
        }
        if (previewFrame is { } frame)
        {
            previewCache?.RequestDeveloped(frame, 2048);
        }

        // 변형된 frame에 raw 파일을 잠깐 보여 주면 region만 변형 좌표로 움직여 둘이 어긋납니다.
        // native 현상 프록시가 올 때까지 빈 상태를 유지하고, identity일 때만 raw를 즉시 씁니다.
        if (previewFrame?.ImageTransform != ImageTransformRecipe.Identity)
        {
            PreviewImage.Source = null;
            loadedPreviewPath = null;
            imagePixelWidth = 0;
            imagePixelHeight = 0;
            LayoutRegions();
            return;
        }

        if (!string.Equals(loadedPreviewPath, previewPath, StringComparison.OrdinalIgnoreCase))
        {
            LoadPreview(previewPath!);
        }
        LayoutRegions();
    }

    /// <summary>developed FIFO에 현재 프리뷰가 준비되면 raw 대신 같은 현상 화소를 올립니다.</summary>
    internal void OnDevelopedReady(string frameId)
    {
        if (!string.Equals(previewFrame?.Id, frameId, StringComparison.Ordinal) ||
            !TryPresentDeveloped())
        {
            return;
        }
        LayoutRegions();
    }

    private bool TryPresentDeveloped()
    {
        if (previewFrame is not { } frame || previewCache is null ||
            !previewCache.TryGetDeveloped(frame, out ThumbnailService.DevelopedPreview developed) ||
            developed.Width <= 0 || developed.Height <= 0 ||
            developed.Pixels.LongLength < (long)developed.Width * developed.Height * 4)
        {
            return false;
        }
        if (developedBitmap is null ||
            developedBitmap.PixelWidth != developed.Width ||
            developedBitmap.PixelHeight != developed.Height)
        {
            developedBitmap = new WriteableBitmap(developed.Width, developed.Height);
        }
        using (Stream buffer = developedBitmap.PixelBuffer.AsStream())
        {
            buffer.Write(developed.Pixels, 0, developed.Width * developed.Height * 4);
        }
        developedBitmap.Invalidate();
        PreviewImage.Source = developedBitmap;
        loadedPreviewPath = null;
        imagePixelWidth = developed.Width;
        imagePixelHeight = developed.Height;
        return true;
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

    private FlatbedOverlayRect ScreenRect(FlatbedScanRegion region) =>
        TryPreviewTransform(out ImageTransformRecipe transform, out uint width, out uint height)
            ? FlatbedOverlayGeometry.ScreenRect(region, ImageFrame, transform, width, height)
            : FlatbedOverlayGeometry.ScreenRect(region, ImageFrame);

    private bool TryPreviewTransform(
        out ImageTransformRecipe transform,
        out uint width,
        out uint height)
    {
        transform = previewFrame?.ImageTransform ?? ImageTransformRecipe.Identity;
        width = previewFrame?.SourceMetadata?.PixelWidth ?? 0U;
        height = previewFrame?.SourceMetadata?.PixelHeight ?? 0U;
        return width > 1U && height > 1U && transform.IsValid;
    }
}
