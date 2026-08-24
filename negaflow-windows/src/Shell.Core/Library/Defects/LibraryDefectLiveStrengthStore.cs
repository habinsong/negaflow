namespace Negaflow.Shell;

internal readonly record struct LibraryDefectLiveStrength(Guid ItemId, double Strength);

/// <summary>
/// 저장 전 결함 강도를 frame별로 보관합니다. 가상 사본은 어느 화면에서 만들든 생성 시점의
/// 현재 강도를 복사해야 하므로, 특정 Develop panel이 아니라 공유 library host가 소유합니다.
/// </summary>
internal sealed class LibraryDefectLiveStrengthStore
{
    private readonly Dictionary<string, LibraryDefectLiveStrength> values =
        new(StringComparer.Ordinal);

    internal LibraryDefectLiveStrength? Get(string? frameId) =>
        frameId is not null && values.TryGetValue(frameId, out LibraryDefectLiveStrength value)
            ? value
            : null;

    internal void Set(string frameId, Guid itemId, double strength) =>
        values[frameId] = new LibraryDefectLiveStrength(itemId, strength);

    internal void Clear(string? frameId)
    {
        if (frameId is not null)
        {
            values.Remove(frameId);
        }
    }

    internal bool HasForOtherFrame(string frameId, Guid itemId) =>
        values.Any(pair =>
            !string.Equals(pair.Key, frameId, StringComparison.Ordinal) &&
            pair.Value.ItemId == itemId);

    internal void RetainFrames(IEnumerable<string> frameIds)
    {
        HashSet<string> retained = new(frameIds, StringComparer.Ordinal);
        foreach (string frameId in values.Keys.Where(id => !retained.Contains(id)).ToArray())
        {
            values.Remove(frameId);
        }
    }

    internal void Clear() => values.Clear();
}
