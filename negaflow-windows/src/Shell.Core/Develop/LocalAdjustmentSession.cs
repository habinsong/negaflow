using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// macOS <c>LocalAdjustmentSession</c>(Features/Develop/LocalAdjustments) 그대로입니다.
/// </summary>
/// <remarks>
/// 부분 보정 카드가 들고 있는 "지금 무엇을 그리는 중인가" 상태입니다. 카탈로그에 들어간
/// 보정과는 자리가 다릅니다 — 여기 값은 <b>다음에 만들</b> 보정의 초기값이고, 이미 만든
/// 보정은 프레임 레시피에 삽니다.
/// </remarks>
public sealed class LocalAdjustmentSession
{
    /// <summary>macOS <c>@Published var amount = 0.35</c>.</summary>
    public const double DefaultAmount = 0.35;

    /// <summary>macOS <c>@Published var feather = 0.20</c>.</summary>
    public const double DefaultFeather = 0.20;

    /// <summary>macOS <c>@Published var brushThickness = 0.04</c>.</summary>
    public const double DefaultBrushThickness = 0.04;

    /// <summary>macOS 브러시 굵기 슬라이더 범위 <c>0.005...0.25</c> 입니다.</summary>
    public const double MinimumBrushThickness = 0.005;

    public const double MaximumBrushThickness = 0.25;

    private LocalDodgeBurnMaskKind maskKind = LocalDodgeBurnMaskKind.Brush;
    private readonly List<LocalDodgeBurnPoint> polygonPoints = [];

    /// <summary>그리는 중인 프레임입니다. 없으면 아무 것도 그리고 있지 않습니다.</summary>
    public string? ActiveFrameId { get; private set; }

    /// <summary>목록에서 펼쳐 놓은 보정입니다.</summary>
    public Guid? SelectedAdjustmentId { get; set; }

    /// <summary>마스크 종류를 바꾸면 macOS 처럼 찍어 둔 다각형 꼭짓점을 버립니다.</summary>
    public LocalDodgeBurnMaskKind MaskKind
    {
        get => maskKind;
        set
        {
            if (maskKind == value)
            {
                return;
            }
            maskKind = value;
            polygonPoints.Clear();
        }
    }

    public LocalDodgeBurnMode Mode { get; set; } = LocalDodgeBurnMode.Dodge;

    public double Amount { get; set; } = DefaultAmount;

    public double Feather { get; set; } = DefaultFeather;

    public double BrushThickness { get; set; } = DefaultBrushThickness;

    public IReadOnlyList<LocalDodgeBurnPoint> PolygonPoints => polygonPoints;

    /// <summary>복사해 둔 보정입니다. macOS <c>copiedAdjustment</c>.</summary>
    public LocalDodgeBurnAdjustment? CopiedAdjustment { get; private set; }

    public bool IsActive(string frameId) =>
        ActiveFrameId is { } active && string.Equals(active, frameId, StringComparison.Ordinal);

    /// <summary>이 종류를 지금 그리고 있는지. 아이콘 단추의 켬 표시가 이 값입니다.</summary>
    public bool IsDrawing(string frameId, LocalDodgeBurnMaskKind kind) =>
        IsActive(frameId) && MaskKind == kind;

    /// <summary>
    /// macOS <c>activate(for:)</c> — 그리기를 켜고 그 프레임의 마지막 보정을 펼칩니다.
    /// </summary>
    public void Activate(string frameId, IReadOnlyList<LocalDodgeBurnAdjustment> adjustments)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        ArgumentNullException.ThrowIfNull(adjustments);
        ActiveFrameId = frameId;
        SelectedAdjustmentId = adjustments.Count == 0 ? null : adjustments[^1].Id;
    }

    public void Deactivate()
    {
        ActiveFrameId = null;
        polygonPoints.Clear();
    }

    /// <summary>
    /// macOS <c>toggleDrawing(_:)</c> — 같은 종류를 다시 누르면 끄고, 아니면 그 종류로 켭니다.
    /// 돌려주는 것은 켜졌는지 여부입니다(다른 캔버스 도구를 꺼야 하는지 부르는 쪽이 압니다).
    /// </summary>
    public bool ToggleDrawing(
        string frameId,
        LocalDodgeBurnMaskKind kind,
        IReadOnlyList<LocalDodgeBurnAdjustment> adjustments)
    {
        if (IsDrawing(frameId, kind))
        {
            Deactivate();
            return false;
        }
        MaskKind = kind;
        Activate(frameId, adjustments);
        SelectedAdjustmentId = null;
        return true;
    }

    public void Copy(LocalDodgeBurnAdjustment adjustment)
    {
        ArgumentNullException.ThrowIfNull(adjustment);
        CopiedAdjustment = adjustment;
    }

    /// <summary>붙여넣을 사본입니다. macOS 처럼 <b>새 id</b> 를 답니다.</summary>
    public LocalDodgeBurnAdjustment? PastedAdjustment() =>
        CopiedAdjustment is { } copy ? copy with { Id = Guid.NewGuid() } : null;

    /// <summary>지금 값으로 보정을 하나 만듭니다. macOS <c>makeAdjustment(mask:)</c>.</summary>
    public LocalDodgeBurnAdjustment MakeAdjustment(LocalDodgeBurnMask mask)
    {
        ArgumentNullException.ThrowIfNull(mask);
        return new LocalDodgeBurnAdjustment(Guid.NewGuid(), Mode, Amount, true, mask);
    }

    /// <summary>다각형 꼭짓점을 하나 찍습니다.</summary>
    public void AddPolygonPoint(LocalDodgeBurnPoint point) => polygonPoints.Add(point);

    public void ClearPolygonPoints() => polygonPoints.Clear();
}
