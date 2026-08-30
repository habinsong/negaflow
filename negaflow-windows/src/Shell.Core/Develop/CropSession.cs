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

    /// <summary>
    /// 잠긴 종횡비를 <b>정규 좌표</b>로 나타낸 값입니다(정규 가로/정규 세로). 화소 비율이
    /// 아니라 정규 비율인 이유는 선택 사각형이 이미지 크기로 정규화돼 있기 때문입니다 —
    /// 화소 3:2 는 이미지가 4000×3000 이면 정규 비율 1.125 입니다. 변환은 호출자가 합니다.
    /// null 이면 자유롭게 끕니다.
    /// </summary>
    public double? LockedNormalizedAspectRatio { get; set; }

    public void Select(CropDisplayPoint start, CropDisplayPoint end) =>
        Selection = Constrain(CropDisplayRect.FromPoints(start, end));

    public void SetSelection(CropDisplayRect selection) =>
        Selection = Constrain(CropDisplayRect.Clamp(selection));

    /// <summary>
    /// 이미 맞는 사각형을 그대로 넣습니다. 비율을 다시 맞추지 않습니다.
    /// </summary>
    /// <remarks>
    /// 종횡비를 고르면 그 비율에 딱 맞는 사각형이 변형에 먼저 들어갑니다. 그것을
    /// <see cref="SetSelection"/> 으로 넣으면 잠긴 비율로 한 번 더 맞추므로, 잠금이 아직 옛
    /// 비율이면 두 비율을 곱한 모양이 됩니다. 실측으로 4:3 을 골랐는데 21:9 처럼 나왔습니다.
    /// 들어오는 값이 이미 정답인 자리에서는 이쪽을 씁니다.
    /// </remarks>
    public void SetSelectionExact(CropDisplayRect selection) =>
        Selection = CropDisplayRect.Clamp(selection);

    /// <summary>옮기기는 크기를 바꾸지 않으므로 비율을 다시 맞출 필요가 없습니다.</summary>
    public void Move(double dx, double dy) => Selection = Selection.Move(dx, dy);

    public void Resize(CropHandle handle, CropDisplayPoint point) =>
        Selection = Constrain(Selection.Resize(handle, point));

    /// <summary>
    /// 잠긴 비율에 맞춰 높이를 다시 냅니다. 왼쪽 위 모서리를 붙잡아 두므로 끌던 손끝이 튀지
    /// 않고, 화면 밖으로 나가면 마지막에 clamp 가 잡습니다.
    /// </summary>
    private CropDisplayRect Constrain(CropDisplayRect rect)
    {
        if (LockedNormalizedAspectRatio is not { } ratio || !double.IsFinite(ratio) || ratio <= 0.0)
        {
            return rect;
        }
        double height = rect.Width / ratio;
        if (height > 1.0)
        {
            return CropDisplayRect.Clamp(new(rect.X, rect.Y, ratio, 1.0));
        }
        return CropDisplayRect.Clamp(new(rect.X, rect.Y, rect.Width, height));
    }

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
