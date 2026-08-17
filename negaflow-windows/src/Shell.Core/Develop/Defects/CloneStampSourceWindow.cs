using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 복제 도장이 원 안과 획 안에 보여 주는 <b>소스 창</b>입니다. macOS
/// <c>CloneStampOverlay.draw</c> 의
/// <c>layer.draw(Image(nsImage: referenceImage), in: imageFrame.offsetBy(dx: -offset.width, dy: -offset.height))</c>
/// 한 줄에 해당합니다 — 표시 이미지를 오프셋만큼 되밀어 그리므로, 표시 화소
/// <c>(x, y)</c> 자리에는 <c>(x + offset.x, y + offset.y)</c> 의 화소가 옵니다.
/// </summary>
/// <remarks>
/// 기준 이미지는 macOS <c>referenceImage</c> 와 같이 <b>화면에 보이는 미리보기 그 자체</b>이며
/// (<c>CanvasView</c> 가 <c>referenceImage: image</c> 로 넘깁니다), 덮개와 같은 격자입니다.
/// </remarks>
public sealed class CloneStampSourceWindow
{
    private readonly byte[] reference;
    private readonly int width;
    private readonly int height;

    private CloneStampSourceWindow(
        byte[] reference,
        int width,
        int height,
        int offsetX,
        int offsetY)
    {
        this.reference = reference;
        this.width = width;
        this.height = height;
        OffsetX = offsetX;
        OffsetY = offsetY;
    }

    /// <summary>macOS <c>offset.width</c> — 표시 화소 단위입니다.</summary>
    public int OffsetX { get; }

    /// <summary>macOS <c>offset.height</c> — 표시 화소 단위입니다.</summary>
    public int OffsetY { get; }

    /// <summary>
    /// macOS <c>displayOffset(forCursorAt:)</c>: 기준점에서의 화면 오프셋(소스 표시점 − 대상
    /// 표시점)입니다. 정렬 오프셋이 있으면 그것을, 없으면 소스−기준점을 씁니다.
    /// </summary>
    /// <param name="anchor">
    /// macOS <c>current.first ?? cursor</c>. 변형이 affine 이라 오프셋은 한 획 안에서 상수이며,
    /// macOS 도 첫 점 기준으로 한 번만 셉니다.
    /// </param>
    /// <param name="source">지정된 복제 소스의 표시 정규 좌표(macOS <c>sourceBase</c>).</param>
    /// <param name="alignedRawOffset">
    /// macOS <c>alignedOffsetBase</c> — 첫 획에서 확정된 원본 공간 변위입니다.
    /// </param>
    public static (int X, int Y)? TryOffset(
        LibraryFrameSnapshot frame,
        int width,
        int height,
        DefectPoint anchor,
        DefectPoint source,
        DefectPoint? alignedRawOffset)
    {
        ArgumentNullException.ThrowIfNull(frame);
        if (width <= 0 || height <= 0 || frame.SourceMetadata is not { } metadata ||
            !DevelopDisplayGeometry.TryMapDisplayToRaw(
                frame.ImageTransform,
                metadata.PixelWidth,
                metadata.PixelHeight,
                anchor.X,
                anchor.Y,
                out double anchorRawX,
                out double anchorRawY))
        {
            return null;
        }

        DefectPoint offsetRaw;
        if (alignedRawOffset is { } aligned)
        {
            offsetRaw = aligned;
        }
        else if (DevelopDisplayGeometry.TryMapDisplayToRaw(
            frame.ImageTransform,
            metadata.PixelWidth,
            metadata.PixelHeight,
            source.X,
            source.Y,
            out double sourceRawX,
            out double sourceRawY))
        {
            offsetRaw = new DefectPoint(sourceRawX - anchorRawX, sourceRawY - anchorRawY);
        }
        else
        {
            return null;
        }
        if (!double.IsFinite(offsetRaw.X) || !double.IsFinite(offsetRaw.Y))
        {
            return null;
        }

        // macOS: `transform.baseUnitToDisplay(cursorBase + offset)`.
        if (!DevelopDisplayGeometry.TryMapRawToDisplay(
                frame.ImageTransform,
                metadata.PixelWidth,
                metadata.PixelHeight,
                anchorRawX + offsetRaw.X,
                anchorRawY + offsetRaw.Y,
                out double sourceDisplayX,
                out double sourceDisplayY))
        {
            return null;
        }

        // macOS 는 CGSize(실수)로 돌려주고 이미지를 보간해 그립니다. 여기서는 화소를 통째로
        // 옮기므로 가장 가까운 화소로 반올림합니다.
        (int anchorX, int anchorY) = Pixel(anchor.X, anchor.Y, width, height);
        (int sourceX, int sourceY) = Pixel(sourceDisplayX, sourceDisplayY, width, height);
        return (sourceX - anchorX, sourceY - anchorY);
    }

    /// <summary>
    /// 표시 정규 좌표를 덮개 화소로 옮깁니다. <see cref="DefectDisplayLocator"/> 가 표를 만들 때
    /// 쓰는 것과 같은 규약입니다(<c>display = pixel / (size − 1)</c>).
    /// </summary>
    public static (int X, int Y) Pixel(double displayX, double displayY, int width, int height) =>
        ((int)Math.Round(displayX * (width - 1)), (int)Math.Round(displayY * (height - 1)));

    /// <summary>
    /// 기준 이미지가 덮개와 같은 격자일 때에만 창을 엽니다. macOS 는 소스 지정 전
    /// (<c>sourceBase == nil</c>) 이나 이미지가 없으면 미리보기를 넣지 않습니다.
    /// </summary>
    public static CloneStampSourceWindow? TryCreate(
        byte[]? reference,
        int width,
        int height,
        int offsetX,
        int offsetY)
    {
        if (reference is null || width <= 0 || height <= 0 ||
            reference.Length < checked(width * height * 4))
        {
            return null;
        }
        return new CloneStampSourceWindow(reference, width, height, offsetX, offsetY);
    }

    /// <summary>덮개 화소 하나에 소스 화소를 옮깁니다. 소스가 이미지 밖이면 아무것도 그리지 않습니다.</summary>
    internal void CopyInto(DefectCanvas canvas, int x, int y)
    {
        int sourceX = x + OffsetX;
        int sourceY = y + OffsetY;
        if (sourceX < 0 || sourceY < 0 || sourceX >= width || sourceY >= height)
        {
            return;
        }
        int index = ((sourceY * width) + sourceX) * 4;
        canvas.Write(x, y, reference[index], reference[index + 1], reference[index + 2]);
    }
}
