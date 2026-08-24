using Negaflow.Catalog;

namespace Negaflow.Shell;

public enum GrainMendTool
{
    None,
    Guided,
    Brush,
    Clone,
}

/// <summary>
/// GrainMend 캔버스 도구 한 세션의 입력 상태입니다. 뷰는 포인터 좌표만 넘기고, 복제 소스와
/// 첫 획에서 확정된 raw 오프셋, 진행 중 획, recipe 커밋 순서는 이 타입이 책임집니다.
/// </summary>
public sealed class GrainMendStrokeSession
{
    /// <summary>macOS <c>BrushControlBar</c> 의 굵기 슬라이더 범위입니다.</summary>
    public const double MinimumBrushThickness = 0.004;

    public const double MaximumBrushThickness = 0.06;

    /// <summary>macOS <c>CanvasView.brushThickness</c> 의 초기값입니다.</summary>
    public const double DefaultBrushThickness = 0.010;

    /// <summary>macOS <c>CloneStampOverlay</c> 의 크기 슬라이더 범위(px)입니다.</summary>
    public const double MinimumCloneDiameterPixels = 4.0;

    public const double MaximumCloneDiameterPixels = 512.0;

    /// <summary>macOS <c>CanvasView.cloneStampSizePx</c> / <c>cloneStampHardness</c>.</summary>
    public const double DefaultCloneDiameterPixels = 48.0;

    public const double DefaultCloneHardness = 0.5;

    private readonly List<DefectPoint> stroke = [];
    private readonly List<DefectStroke> painted = [];
    private DefectPoint? cloneSourceAnchor;
    private DefectPoint? cloneAlignedOffsetRaw;
    private GrainMendTool selectedTool;
    private string? currentFrameId;
    private string? toolFrameId;
    private double brushThickness = DefaultBrushThickness;
    private double cloneDiameterPixels = DefaultCloneDiameterPixels;
    private double cloneHardness = DefaultCloneHardness;

    public GrainMendTool Tool =>
        currentFrameId is not null &&
        string.Equals(currentFrameId, toolFrameId, StringComparison.Ordinal)
            ? selectedTool
            : GrainMendTool.None;

    public bool IsDragging { get; private set; }

    /// <summary>
    /// macOS 는 칠을 바로 적용하지 않습니다 — 획을 모아 두고 <c>결함 제거</c> 를 눌러야
    /// recipe 로 갑니다. 오버레이가 이 목록을 빨강으로 그립니다.
    /// </summary>
    public IReadOnlyList<DefectStroke> PaintedStrokes => painted;

    /// <summary>진행 중인 획의 표시 정규 좌표입니다. 오버레이가 같은 색으로 그립니다.</summary>
    public IReadOnlyList<DefectPoint> InProgressStroke => stroke;

    /// <summary>macOS <c>hasStrokes</c> — 되돌리기·지우기·제거가 열리는 조건입니다.</summary>
    public bool HasPaintedStrokes => painted.Count > 0;

    /// <summary>굵기(짧은 변에 대한 비율). 슬라이더 범위로 잘립니다.</summary>
    public double BrushThickness
    {
        get => brushThickness;
        set => brushThickness = Math.Clamp(
            double.IsFinite(value) ? value : DefaultBrushThickness,
            MinimumBrushThickness,
            MaximumBrushThickness);
    }

    /// <summary>
    /// macOS 는 소스를 지정하기 전에는 컨트롤 바에 안내를 띄우고, 원 안에 미리보기를 넣지
    /// 않습니다(<c>sourceBase == nil</c>).
    /// </summary>
    public DefectPoint? CloneSourceAnchor => cloneSourceAnchor;

    /// <summary>
    /// macOS <c>alignedOffsetBase</c> — 첫 획에서 확정된 원본 공간 변위입니다. 커서 오버레이가
    /// 원 안에 보여 줄 소스 화소의 자리를 이것으로 셉니다(macOS <c>displayOffset</c>).
    /// </summary>
    public DefectPoint? CloneAlignedRawOffset => cloneAlignedOffsetRaw;

    /// <summary>복제 지름(원본 화소). 슬라이더 범위로 잘립니다.</summary>
    public double CloneDiameterPixels
    {
        get => cloneDiameterPixels;
        set => cloneDiameterPixels = Math.Clamp(
            double.IsFinite(value) ? value : DefaultCloneDiameterPixels,
            MinimumCloneDiameterPixels,
            MaximumCloneDiameterPixels);
    }

    /// <summary>복제 경도(0~1).</summary>
    public double CloneHardness
    {
        get => cloneHardness;
        set => cloneHardness = Math.Clamp(
            double.IsFinite(value) ? value : DefaultCloneHardness,
            0.0,
            1.0);
    }

    public void Select(GrainMendTool tool)
    {
        if (tool == GrainMendTool.None)
        {
            if (selectedTool == GrainMendTool.None)
            {
                return;
            }
            selectedTool = GrainMendTool.None;
            toolFrameId = null;
            ClearTransientInput();
            return;
        }
        if (currentFrameId is null || Tool == tool)
        {
            return;
        }
        selectedTool = tool;
        toolFrameId = currentFrameId;
        ClearTransientInput();
    }

    /// <summary>
    /// macOS 캔버스는 frame ID로 다시 만들어져 draft/source/current stroke를 다른 사진에 넘기지
    /// 않습니다. Brush/Clone tool owner만 원래 frame ID에 남아 돌아왔을 때 빈 도구로 다시 보입니다.
    /// Guided는 frame 전환 즉시 끝납니다.
    /// </summary>
    public void ChangeFrame(string? frameId)
    {
        if (string.Equals(currentFrameId, frameId, StringComparison.Ordinal))
        {
            return;
        }
        currentFrameId = frameId;
        ClearTransientInput();
        if (selectedTool == GrainMendTool.Guided || frameId is null)
        {
            selectedTool = GrainMendTool.None;
            toolFrameId = null;
        }
    }

    private void ClearTransientInput()
    {
        stroke.Clear();
        painted.Clear();
        cloneSourceAnchor = null;
        cloneAlignedOffsetRaw = null;
        IsDragging = false;
    }

    /// <summary>macOS <c>onUndo</c> — 마지막으로 칠한 획 하나를 지웁니다.</summary>
    public bool UndoLastPaintedStroke()
    {
        if (painted.Count == 0)
        {
            return false;
        }
        painted.RemoveAt(painted.Count - 1);
        return true;
    }

    /// <summary>macOS <c>onClear</c> — 칠한 것을 전부 지웁니다(적용된 것은 그대로).</summary>
    public bool ClearPaintedStrokes()
    {
        if (painted.Count == 0)
        {
            return false;
        }
        painted.Clear();
        return true;
    }

    /// <summary>
    /// macOS <c>onApply</c> — 모아 둔 획을 recipe 로 보냅니다. 성공하면 칠을 비웁니다.
    /// </summary>
    public bool ApplyPaintedStrokes(DevelopPanelState panel, out LibraryFrameError error)
    {
        ArgumentNullException.ThrowIfNull(panel);
        error = LibraryFrameError.None;
        if (painted.Count == 0)
        {
            return false;
        }
        DefectStroke[] pending = [.. painted];
        error = panel.AddBrushStrokes(pending);
        if (error == LibraryFrameError.None)
        {
            painted.Clear();
        }
        return true;
    }

    public bool Begin(DefectPoint displayPoint, bool cloneSourceModifier)
    {
        if (Tool is GrainMendTool.None or GrainMendTool.Guided)
        {
            return false;
        }
        if (Tool == GrainMendTool.Clone && cloneSourceModifier)
        {
            cloneSourceAnchor = displayPoint;
            cloneAlignedOffsetRaw = null;
            stroke.Clear();
            IsDragging = false;
            return true;
        }
        if (Tool == GrainMendTool.Clone && cloneSourceAnchor is null)
        {
            return true;
        }

        stroke.Clear();
        stroke.Add(displayPoint);
        IsDragging = true;
        return true;
    }

    public bool Continue(DefectPoint displayPoint)
    {
        if (!IsDragging)
        {
            return false;
        }
        stroke.Add(displayPoint);
        return true;
    }

    public void CancelStroke()
    {
        stroke.Clear();
        IsDragging = false;
    }

    public bool Finish(DevelopPanelState panel, out LibraryFrameError error)
    {
        ArgumentNullException.ThrowIfNull(panel);
        error = LibraryFrameError.None;
        if (!IsDragging)
        {
            return false;
        }

        IsDragging = false;
        DefectPoint[] completed = [.. stroke];
        stroke.Clear();
        if (completed.Length == 0)
        {
            return true;
        }
        if (Tool == GrainMendTool.Clone)
        {
            error = panel.AddCloneStroke(
                completed,
                cloneSourceAnchor ?? completed[0],
                cloneAlignedOffsetRaw,
                out DefectPoint usedOffset,
                cloneDiameterPixels,
                cloneHardness);
            if (error == LibraryFrameError.None)
            {
                cloneAlignedOffsetRaw = usedOffset;
            }
            return true;
        }

        // macOS 브러시는 획을 끝내도 적용하지 않습니다 — 빨강으로 모아 두고 `결함 제거` 를
        // 눌러야 recipe 로 갑니다. 획마다 자기 굵기를 들고 갑니다.
        painted.Add(new DefectStroke([.. completed], brushThickness));
        return true;
    }
}
