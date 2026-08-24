namespace Negaflow.Shell.Develop;

/// <summary>
/// 저장 전 레이어 조작을 frame별로 보관합니다. recipe item ID는 가상 사본에 복사되므로
/// item ID만으로는 사진 소유권을 판별할 수 없습니다.
/// </summary>
internal sealed class DefectLayerFrameInteractionState(
    LibraryDefectLiveStrengthStore liveStrengths)
{
    private readonly Dictionary<string, Guid> maskPreviews =
        new(StringComparer.Ordinal);

    internal LibraryDefectLiveStrength? LiveStrength(string? frameId) =>
        liveStrengths.Get(frameId);

    internal void SetLiveStrength(string frameId, Guid itemId, double strength) =>
        liveStrengths.Set(frameId, itemId, strength);

    internal void EndGesture(string? frameId) => liveStrengths.Clear(frameId);

    internal bool HasLiveStrengthForOtherFrame(string frameId, Guid itemId) =>
        liveStrengths.HasForOtherFrame(frameId, itemId);

    internal Guid? MaskPreview(string? frameId) =>
        frameId is not null && maskPreviews.TryGetValue(frameId, out Guid itemId)
            ? itemId
            : null;

    internal void ToggleMaskPreview(string frameId, Guid itemId)
    {
        if (maskPreviews.TryGetValue(frameId, out Guid current) && current == itemId)
        {
            maskPreviews.Remove(frameId);
            return;
        }
        maskPreviews[frameId] = itemId;
    }

    internal void SetMaskPreview(string frameId, Guid? itemId)
    {
        if (itemId is { } value)
        {
            maskPreviews[frameId] = value;
        }
        else
        {
            maskPreviews.Remove(frameId);
        }
    }

    internal void RetainFrames(IEnumerable<string> frameIds)
    {
        HashSet<string> retained = new(frameIds, StringComparer.Ordinal);
        liveStrengths.RetainFrames(retained);
        foreach (string frameId in maskPreviews.Keys.Where(id => !retained.Contains(id)).ToArray())
        {
            maskPreviews.Remove(frameId);
        }
    }
}
