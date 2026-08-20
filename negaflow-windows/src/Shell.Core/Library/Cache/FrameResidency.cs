namespace Negaflow.Shell.Library;

/// <summary>
/// macOS <c>Services/Cache/FrameCacheManager.swift</c> 의 developed 상주 목록 이식본입니다.
/// </summary>
/// <remarks>
/// <para>
/// macOS 주석 원문: <i>"FIFO 재등록 후 한도 초과분을 축출한다. 축출 프레임은 onEvict 로
/// 넘기며, 호출자가 메모리 이미지와 재생성 가능한 임시 상태를 내려놓는다."</i>
/// </para>
/// <para>
/// <c>trimDeveloped</c> 의 선택 프레임 보호까지 그대로 옮겼습니다 — 선택된 것이 목록 앞에
/// 오면 축출하지 않고 뒤로 돌리고, 목록이 전부 선택 프레임이면 멈춥니다.
/// </para>
/// <para>
/// cleaned raw 상주 목록은 네이티브가 들고 있습니다
/// (<c>src/Native/pipeline/export/stages/decode.cpp</c>). 여기는 developed 만 봅니다.
/// </para>
/// </remarks>
public sealed class FrameResidency
{
    private readonly List<string> resident = [];
    private readonly Lock gate = new();

    public FrameResidency(int limit) => Limit = Math.Max(1, limit);

    public int Limit { get; private set; }

    /// <summary>macOS <c>selectedFrameID</c> — 이 프레임은 축출하지 않습니다.</summary>
    public string? SelectedFrameId { get; set; }

    public int Count
    {
        get
        {
            lock (gate)
            {
                return resident.Count;
            }
        }
    }

    public void SetLimit(int limit, Action<string> onEvict)
    {
        ArgumentNullException.ThrowIfNull(onEvict);
        lock (gate)
        {
            Limit = Math.Max(1, limit);
            Trim(onEvict);
        }
    }

    /// <summary>macOS <c>markDevelopedResident</c>.</summary>
    public void MarkResident(string frameId, Action<string> onEvict)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        ArgumentNullException.ThrowIfNull(onEvict);
        lock (gate)
        {
            resident.RemoveAll(id => string.Equals(id, frameId, StringComparison.Ordinal));
            resident.Add(frameId);
            Trim(onEvict);
        }
    }

    /// <summary>macOS <c>removeDevelopedResident</c>.</summary>
    public void Remove(string frameId)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        lock (gate)
        {
            resident.RemoveAll(id => string.Equals(id, frameId, StringComparison.Ordinal));
        }
    }

    public void Clear()
    {
        lock (gate)
        {
            resident.Clear();
        }
    }

    /// <summary>macOS <c>trimDeveloped</c>.</summary>
    private void Trim(Action<string> onEvict)
    {
        while (resident.Count > Limit)
        {
            string evictId = resident[0];
            if (string.Equals(evictId, SelectedFrameId, StringComparison.Ordinal))
            {
                resident.RemoveAt(0);
                resident.Add(evictId);
                if (resident.TrueForAll(
                        id => string.Equals(id, SelectedFrameId, StringComparison.Ordinal)))
                {
                    break;
                }
                continue;
            }
            resident.RemoveAt(0);
            onEvict(evictId);
        }
    }
}
