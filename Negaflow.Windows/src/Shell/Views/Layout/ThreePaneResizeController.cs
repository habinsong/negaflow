namespace Negaflow.Shell.Views.Layout;

internal sealed class ThreePaneResizeController
{
    private double? leftDragBase;
    private double? rightDragBase;

    internal double LeftWidth { get; private set; }

    internal double RightWidth { get; private set; }

    internal void Synchronize(double leftWidth, double rightWidth, double availableWidth)
    {
        WorkspaceLayout layout = WorkspaceLayoutCalculator.Calculate(availableWidth);
        if (leftDragBase is null)
        {
            LeftWidth = layout.ClampPanelWidth(leftWidth);
        }

        if (rightDragBase is null)
        {
            RightWidth = layout.ClampPanelWidth(rightWidth);
        }
    }

    internal void BeginLeft() => leftDragBase = LeftWidth;

    internal void BeginRight() => rightDragBase = RightWidth;

    internal double UpdateLeft(double horizontalChange, double availableWidth)
    {
        leftDragBase ??= LeftWidth;
        LeftWidth = WorkspaceLayoutCalculator.Calculate(availableWidth)
            .ClampPanelWidth(LeftWidth + horizontalChange);
        return LeftWidth;
    }

    internal double UpdateRight(double horizontalChange, double availableWidth)
    {
        rightDragBase ??= RightWidth;
        RightWidth = WorkspaceLayoutCalculator.Calculate(availableWidth)
            .ClampPanelWidth(RightWidth - horizontalChange);
        return RightWidth;
    }

    internal double EndLeft()
    {
        leftDragBase = null;
        return LeftWidth;
    }

    internal double EndRight()
    {
        rightDragBase = null;
        return RightWidth;
    }
}
