namespace Negaflow.Shell.Develop;

/// <summary>현재 Develop frame의 비동기 IR 표시 상태와 수동 GrainMend 양보 명령입니다.</summary>
public sealed class DevelopInfraredCleanState
{
    private readonly LibraryHostService host;
    private string? frameId;

    internal DevelopInfraredCleanState(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        this.host = host;
    }

    public InfraredCleanStatus Status { get; private set; } = InfraredCleanStatus.Silent;

    internal void BindFrame(string? selectedFrameId)
    {
        if (string.Equals(frameId, selectedFrameId, StringComparison.Ordinal))
        {
            return;
        }
        frameId = selectedFrameId;
        Status = InfraredCleanStatus.Silent;
    }

    public bool Update(string updatedFrameId, InfraredCleanStatus status)
    {
        ArgumentException.ThrowIfNullOrEmpty(updatedFrameId);
        if (!string.Equals(frameId, updatedFrameId, StringComparison.Ordinal))
        {
            return false;
        }
        Status = status;
        return true;
    }

    public bool YieldToManualTool() =>
        frameId is { } selectedFrameId &&
        host.YieldInfraredCleanToManualTool(selectedFrameId);
}
