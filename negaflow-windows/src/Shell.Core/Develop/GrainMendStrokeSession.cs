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
    private readonly List<DefectPoint> stroke = [];
    private DefectPoint? cloneSourceAnchor;
    private DefectPoint? cloneAlignedOffsetRaw;

    public GrainMendTool Tool { get; private set; }

    public bool IsDragging { get; private set; }

    public void Select(GrainMendTool tool)
    {
        if (Tool == tool)
        {
            return;
        }
        Tool = tool;
        stroke.Clear();
        cloneSourceAnchor = null;
        cloneAlignedOffsetRaw = null;
        IsDragging = false;
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

        error = panel.AddBrushStroke(completed);
        return true;
    }
}
