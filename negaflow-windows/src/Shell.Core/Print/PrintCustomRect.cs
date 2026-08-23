namespace Negaflow.Shell.Print;

/// <summary>사각형의 어느 값을 바꾸는지입니다.</summary>
public enum PrintRectComponent
{
    X,
    Y,
    Width,
    Height,
}

/// <summary>
/// 셀·문구의 자리를 숫자로 바꿀 때의 규칙입니다. macOS
/// <c>PrintPackageInspectorControls.customRectBinding</c> · <c>customCaptionRectBinding</c> 를
/// 그대로 옮긴 것입니다.
/// </summary>
/// <remarks>
/// <para>
/// 자르지 않으면 슬라이더로 칸을 판 밖으로 내보낼 수 있습니다. 판 밖으로 나간 칸이 하나라도
/// 있으면 <see cref="PrintPackageLayout"/> 이 배치를 <b>통째로</b> 거절해 미리보기가 빈
/// 종이가 됩니다.
/// </para>
/// <para>
/// 크기를 키울 때는 원점을 밀어 줍니다. macOS 주석 원문: "예전에는 `너비 ≤ 1 - x` 로
/// 잘라내서, x 가 조금이라도 있으면 100% 를 줘도 그 값에 닿지 못하고 '용지 전체'가 되지
/// 않았다."
/// </para>
/// <para>
/// 세로는 <b>위에서부터</b> 셉니다. macOS 는 아래가 0 인 좌표를 쓰므로 그쪽에서 뒤집고,
/// 여기 배치는 이미 위가 0 이라 그대로 씁니다 — 화면에서 본 움직임은 같습니다.
/// </para>
/// </remarks>
public static class PrintCustomRect
{
    /// <summary>칸의 최소 크기입니다. macOS <c>0.02</c>.</summary>
    public const double MinimumCellSize = 0.02;

    /// <summary>문구의 최소 크기입니다. macOS <c>0.01</c>.</summary>
    public const double MinimumCaptionSize = 0.01;

    /// <summary>칸 하나의 값을 바꿉니다.</summary>
    public static PrintRect UpdateCell(PrintRect rect, PrintRectComponent component, double raw)
    {
        double value = Math.Clamp(raw, 0, 1);
        switch (component)
        {
            case PrintRectComponent.X:
                return rect with { X = Math.Min(value, 1 - rect.Width) };
            case PrintRectComponent.Y:
                return rect with
                {
                    Y = Math.Max(0, Math.Min(value, 1 - rect.Height)),
                };
            case PrintRectComponent.Width:
            {
                double width = Math.Min(Math.Max(value, MinimumCellSize), 1);
                return rect with { Width = width, X = Math.Min(rect.X, 1 - width) };
            }
            case PrintRectComponent.Height:
            {
                double height = Math.Min(Math.Max(value, MinimumCellSize), 1);
                return rect with { Height = height, Y = Math.Min(rect.Y, 1 - height) };
            }
            default:
                return rect;
        }
    }

    /// <summary>문구 하나의 값을 바꿉니다. macOS <c>customCaptionRectBinding</c>.</summary>
    public static PrintRect UpdateCaption(PrintRect rect, PrintRectComponent component, double raw)
    {
        double value = Math.Clamp(raw, 0, 1);
        return component switch
        {
            PrintRectComponent.X => rect with { X = Math.Min(value, 1 - rect.Width) },
            PrintRectComponent.Y => rect with { Y = Math.Min(value, 1 - rect.Height) },
            PrintRectComponent.Width => rect with
            {
                Width = Math.Max(MinimumCaptionSize, Math.Min(value, 1 - rect.X)),
            },
            PrintRectComponent.Height => rect with
            {
                Height = Math.Max(MinimumCaptionSize, Math.Min(value, 1 - rect.Y)),
            },
            _ => rect,
        };
    }
}
