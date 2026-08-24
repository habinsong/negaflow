namespace Negaflow.Shell;

/// <summary>
/// recipe가 없는 동안에도 열린 문서 안에서 frame별 defect revision을 단조 증가시킵니다.
/// 이 값은 세션 수명 상태이며 catalog나 빈 sidecar로 영속화하지 않습니다.
/// </summary>
internal sealed class LibraryDefectRevisionTracker
{
    private readonly Dictionary<string, ulong> revisions =
        new(StringComparer.Ordinal);

    internal ulong Current(string frameId) =>
        revisions.GetValueOrDefault(frameId);

    internal bool TryGetNext(string frameId, out ulong revision)
    {
        ulong current = Current(frameId);
        if (current == ulong.MaxValue)
        {
            revision = 0;
            return false;
        }
        revision = current + 1UL;
        return true;
    }

    internal bool IsNext(string frameId, ulong revision) =>
        TryGetNext(frameId, out ulong expected) && revision == expected;

    internal void Observe(string frameId, ulong revision)
    {
        if (revision > Current(frameId))
        {
            revisions[frameId] = revision;
        }
    }

    internal void Remove(string frameId) => revisions.Remove(frameId);
}
