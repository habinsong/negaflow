using System.IO;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;

namespace Negaflow.Shell.Views.Develop.Canvas;

/// <summary>
/// 검출·마스크 덮개 화소를 미리보기 위에 올립니다. 마스크 계산은 뷰가 맡습니다.
/// </summary>
internal sealed class DevelopCanvasDefectOverlay
{
    private readonly DevelopPreviewCanvas view;

    internal DevelopCanvasDefectOverlay(DevelopPreviewCanvas view) => this.view = view;

    internal void Hide()
    {
        view.DefectOverlayImage.Source = null;
        view.DefectOverlayImage.Visibility = Visibility.Collapsed;
    }

    internal void Show(byte[] bgra, int width, int height)
    {
        WriteableBitmap bitmap = new(width, height);
        using (Stream buffer = bitmap.PixelBuffer.AsStream())
        {
            buffer.Write(bgra, 0, bgra.Length);
        }
        bitmap.Invalidate();
        view.DefectOverlayImage.Source = bitmap;
        view.DefectOverlayImage.Visibility = Visibility.Visible;
    }
}
