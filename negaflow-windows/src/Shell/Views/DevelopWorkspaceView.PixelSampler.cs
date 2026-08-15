using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// 캔버스의 픽셀 샘플러입니다. 포인터 아래 화소의 값을 읽어 보여 줍니다.
/// </summary>
/// <remarks>
/// macOS 는 원본·작업·프루프 셋을 나란히 냅니다. 여기서는 <b>원본</b>과 <b>화면에 보이는 것</b>
/// 둘입니다 — Windows 미리보기는 한 번에 버퍼 하나만 만들고, 프루프를 켜면 그 버퍼가 곧 프루프
/// 결과입니다. 셋을 다 보이려면 슬라이더를 움직이는 동안 렌더가 두 배가 되므로, 보이는 줄이
/// 지금 무엇인지를 <b>이름으로</b> 밝히는 쪽을 골랐습니다.
/// </remarks>
public sealed partial class DevelopWorkspaceView
{
    /// <summary>화면에 그려진 미리보기 화소입니다. 샘플러가 이것을 읽습니다.</summary>
    private byte[]? previewPixels;
    private int previewPixelWidth;
    private int previewPixelHeight;

    /// <summary>원본 화소입니다. 프레임마다 한 번만 읽어 둡니다.</summary>
    private string? samplerSourcePath;
    private byte[]? samplerSourcePixels;
    private int samplerSourceWidth;
    private int samplerSourceHeight;

    /// <summary>미리보기가 도착할 때마다 샘플러가 읽을 버퍼를 갈아 끼웁니다.</summary>
    private void KeepPreviewPixels(byte[]? pixels, uint width, uint height)
    {
        previewPixels = pixels;
        previewPixelWidth = (int)width;
        previewPixelHeight = (int)height;
    }

    private bool IsPixelSamplerOn =>
        workspaceState?.Current.PixelSamplerEnabled == true;

    internal void UpdatePixelSampler(PointerRoutedEventArgs args)
    {
        if (!IsPixelSamplerOn || previewPixels is null)
        {
            PixelSamplerPanel.Visibility = Visibility.Collapsed;
            return;
        }
        PixelSamplerPanel.Visibility = Visibility.Visible;

        Windows.Foundation.Point point = args.GetCurrentPoint(PreviewImage).Position;
        if (PixelSampler.ToSourceCoordinate(
                point.X,
                point.Y,
                PreviewImage.ActualWidth,
                PreviewImage.ActualHeight,
                previewPixelWidth,
                previewPixelHeight) is not { } preview)
        {
            ShowSamplerHint();
            return;
        }

        PixelColorReading? displayed = PixelSampler.Read(
            previewPixels,
            previewPixelWidth,
            previewPixelHeight,
            preview.X,
            preview.Y);

        // 미리보기는 줄여 그린 것이므로, 원본 좌표는 그 비율만큼 되돌립니다.
        EnsureSamplerSource();
        PixelCoordinate source = preview;
        PixelColorReading? original = null;
        if (samplerSourcePixels is not null && previewPixelWidth > 0 && previewPixelHeight > 0)
        {
            source = new PixelCoordinate(
                (int)((long)preview.X * samplerSourceWidth / previewPixelWidth),
                (int)((long)preview.Y * samplerSourceHeight / previewPixelHeight));
            original = PixelSampler.Read(
                samplerSourcePixels,
                samplerSourceWidth,
                samplerSourceHeight,
                source.X,
                source.Y);
        }

        ShowSamplerReadout(new PixelSamplerReadout(
            source,
            original,
            displayed,
            softProofPreferences.IsEnabled));
    }

    internal void ClearPixelSampler()
    {
        if (IsPixelSamplerOn)
        {
            ShowSamplerHint();
        }
        else
        {
            PixelSamplerPanel.Visibility = Visibility.Collapsed;
        }
    }

    private void ShowSamplerHint()
    {
        PixelSamplerCoordinate.Text = string.Empty;
        PixelSamplerOriginal.Text = string.Empty;
        PixelSamplerDisplayed.Text = string.Empty;
        PixelSamplerHint.Text = AppResources.Get("samplerMovePointer", "Text");
    }

    private void ShowSamplerReadout(PixelSamplerReadout readout)
    {
        PixelSamplerHint.Text = string.Empty;
        PixelSamplerCoordinate.Text =
            $"{AppResources.Get("samplerSourcePixel", "Text")}  " +
            $"{readout.SourceCoordinate.X}, {readout.SourceCoordinate.Y}";
        PixelSamplerOriginal.Text = Row(
            AppResources.Get("samplerOriginal", "Text"),
            readout.Original);
        PixelSamplerDisplayed.Text = Row(
            AppResources.Get(
                readout.DisplayedIsProof ? "samplerProof" : "samplerWorking",
                "Text"),
            readout.Displayed);
    }

    /// <summary>
    /// 한 줄입니다. RGB 와 Lab 을 함께 적습니다 — 색을 눈이 아니라 수로 견줄 때 RGB 만으로는
    /// 모자랍니다.
    /// </summary>
    private static string Row(string title, PixelColorReading? reading)
    {
        if (reading is not { } value)
        {
            return $"{title,-8} —";
        }
        (double l, double a, double b) = value.Lab;
        return $"{title,-8} RGB {value.Red,3} {value.Green,3} {value.Blue,3}   " +
            $"Lab {l,5:F1} {a,6:F1} {b,6:F1}";
    }

    /// <summary>
    /// 원본 화소를 한 번 읽어 둡니다. 포인터가 움직일 때마다 파일을 다시 열면 손이 무거워집니다.
    /// </summary>
    private void EnsureSamplerSource()
    {
        string? path = panel?.SelectedFrame?.SourcePath;
        if (path is null)
        {
            samplerSourcePixels = null;
            samplerSourcePath = null;
            return;
        }
        if (string.Equals(samplerSourcePath, path, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }
        samplerSourcePath = path;
        samplerSourcePixels = null;
        _ = LoadSamplerSourceAsync(path);
    }

    private async Task LoadSamplerSourceAsync(string path)
    {
        try
        {
            using FileStream file = File.OpenRead(path);
            Windows.Graphics.Imaging.BitmapDecoder decoder =
                await Windows.Graphics.Imaging.BitmapDecoder.CreateAsync(
                    file.AsRandomAccessStream());
            Windows.Graphics.Imaging.PixelDataProvider pixels = await decoder.GetPixelDataAsync(
                Windows.Graphics.Imaging.BitmapPixelFormat.Bgra8,
                Windows.Graphics.Imaging.BitmapAlphaMode.Ignore,
                new Windows.Graphics.Imaging.BitmapTransform(),
                Windows.Graphics.Imaging.ExifOrientationMode.IgnoreExifOrientation,
                Windows.Graphics.Imaging.ColorManagementMode.DoNotColorManage);
            if (!string.Equals(samplerSourcePath, path, StringComparison.OrdinalIgnoreCase))
            {
                // 읽는 사이에 다른 사진으로 옮겼습니다. 늦게 온 것을 쓰면 다른 사진의 값이
                // 이 사진의 값으로 보입니다.
                return;
            }
            samplerSourcePixels = pixels.DetachPixelData();
            samplerSourceWidth = (int)decoder.PixelWidth;
            samplerSourceHeight = (int)decoder.PixelHeight;
        }
        catch (Exception exception) when (exception is IOException or
            UnauthorizedAccessException or
            System.Runtime.InteropServices.COMException)
        {
            // 원본을 못 읽으면 원본 줄만 비웁니다 — 화면에 보이는 값은 그대로 읽힙니다.
            samplerSourcePixels = null;
        }
    }
}
