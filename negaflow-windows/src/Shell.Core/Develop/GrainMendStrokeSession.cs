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

    private readonly List<DefectPoint> stroke = [];
    private readonly List<DefectStroke> painted = [];
    private DefectPoint? cloneSourceAnchor;
    private DefectPoint? cloneAlignedOffsetRaw;
    private double brushThickness = DefaultBrushThickness;

    public GrainMendTool Tool { get; private set; }

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

    public void Select(GrainMendTool tool)
    {
        if (Tool == tool)
        {
            return;
        }
        Tool = tool;
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
        foreach (DefectStroke entry in painted)
        {
            error = panel.AddBrushStroke([.. entry.Points], entry.Thickness);
            if (error != LibraryFrameError.None)
            {
                return true;
            }
        }
        painted.Clear();
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
                out DefectPoint usedOffset);
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
