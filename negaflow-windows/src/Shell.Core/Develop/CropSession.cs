using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// Develop canvas crop의 일시 상태입니다. 표시 좌표는 y-down이고 저장 recipe는 y-up이므로,
/// 변환을 이 한 곳에 둡니다. 드래그 중에는 catalog를 쓰지 않으며 Apply에서만 저장합니다.
/// </summary>
public sealed class CropSession
{
    public const double MinimumSize = 0.035;

    private ImageCropRect? previousCrop;

    private CropSession(ImageCropRect? previousCrop, CropDisplayRect selection)
    {
        this.previousCrop = previousCrop;
        Selection = selection;
    }

    public CropDisplayRect Selection { get; private set; }

    public static CropSession Start(ImageCropRect? crop)
    {
        CropDisplayRect selection = crop is { } stored
            ? CropDisplayRect.Clamp(new(
                stored.X,
                1.0 - (stored.Y + stored.Height),
                stored.Width,
                stored.Height))
            : CropDisplayRect.Full;
        return new CropSession(crop, selection);
    }

    /// <summary>Full은 macOS처럼 기존 crop 복원 기준도 지웁니다.</summary>
    public void Full()
    {
        Selection = CropDisplayRect.Full;
        previousCrop = null;
    }

    public void Select(CropDisplayPoint start, CropDisplayPoint end) =>
        Selection = CropDisplayRect.FromPoints(start, end);

    public void SetSelection(CropDisplayRect selection) => Selection = CropDisplayRect.Clamp(selection);

    public void Move(double dx, double dy) => Selection = Selection.Move(dx, dy);

    public void Resize(CropHandle handle, CropDisplayPoint point) =>
        Selection = Selection.Resize(handle, point);

    /// <summary>저장되는 y-up crop입니다. 거의 full인 선택은 crop 없음으로 저장합니다.</summary>
    public ImageCropRect? Apply() =>
        Selection.IsFull
            ? null
            : new ImageCropRect(
                Selection.X,
                1.0 - (Selection.Y + Selection.Height),
                Selection.Width,
                Selection.Height);

    public ImageCropRect? Cancel() => previousCrop;
}

public enum CropHandle
{
    TopLeft,
    Top,
    TopRight,
    Right,
    BottomRight,
    Bottom,
    BottomLeft,
    Left,
}

public readonly record struct CropDisplayPoint(double X, double Y)
{
    public CropDisplayPoint Clamp() => new(Math.Clamp(X, 0.0, 1.0), Math.Clamp(Y, 0.0, 1.0));
}

public readonly record struct CropDisplayRect(double X, double Y, double Width, double Height)
{
    public static CropDisplayRect Full { get; } = new(0.0, 0.0, 1.0, 1.0);

    public double Right => X + Width;

    public double Bottom => Y + Height;

    public bool IsFull => Width >= 0.995 && Height >= 0.995;

    public static CropDisplayRect Clamp(CropDisplayRect value)
    {
        double width = Math.Clamp(value.Width, CropSession.MinimumSize, 1.0);
        double height = Math.Clamp(value.Height, CropSession.MinimumSize, 1.0);
        return new(
            Math.Clamp(value.X, 0.0, 1.0 - width),
            Math.Clamp(value.Y, 0.0, 1.0 - height),
            width,
            height);
    }

    public static CropDisplayRect FromPoints(CropDisplayPoint first, CropDisplayPoint second)
    {
        CropDisplayPoint a = first.Clamp();
        CropDisplayPoint b = second.Clamp();
        return Clamp(new(
            Math.Min(a.X, b.X),
            Math.Min(a.Y, b.Y),
            Math.Abs(a.X - b.X),
            Math.Abs(a.Y - b.Y)));
    }

    public CropDisplayRect Move(double dx, double dy) =>
        Clamp(new(X + dx, Y + dy, Width, Height));

    public CropDisplayRect Resize(CropHandle handle, CropDisplayPoint point)
    {
        CropDisplayPoint p = point.Clamp();
        return handle switch
        {
            CropHandle.TopLeft => Clamp(new(p.X, p.Y, Right - p.X, Bottom - p.Y)),
            CropHandle.Top => Clamp(new(X, p.Y, Width, Bottom - p.Y)),
            CropHandle.TopRight => Clamp(new(X, p.Y, p.X - X, Bottom - p.Y)),
            CropHandle.Right => Clamp(new(X, Y, p.X - X, Height)),
            CropHandle.BottomRight => Clamp(new(X, Y, p.X - X, p.Y - Y)),
            CropHandle.Bottom => Clamp(new(X, Y, Width, p.Y - Y)),
            CropHandle.BottomLeft => Clamp(new(p.X, Y, Right - p.X, p.Y - Y)),
            CropHandle.Left => Clamp(new(p.X, Y, Right - p.X, Height)),
            _ => this,
        };
    }
}
