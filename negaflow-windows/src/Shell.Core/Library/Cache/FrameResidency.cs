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
    private sealed record ResidentFrame(string Id, long Bytes);

    private readonly List<ResidentFrame> resident = [];
    private readonly Lock gate = new();
    private long residentBytes;

    public FrameResidency(int limit, long byteLimit = long.MaxValue)
    {
        Limit = Math.Max(1, limit);
        ByteLimit = Math.Max(1L, byteLimit);
    }

    public int Limit { get; private set; }

    public long ByteLimit { get; private set; }

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

    public long ResidentBytes
    {
        get
        {
            lock (gate)
            {
                return residentBytes;
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

    public void SetLimits(int limit, long byteLimit, Action<string> onEvict)
    {
        ArgumentNullException.ThrowIfNull(onEvict);
        lock (gate)
        {
            Limit = Math.Max(1, limit);
            ByteLimit = Math.Max(1L, byteLimit);
            Trim(onEvict);
        }
    }

    /// <summary>macOS <c>markDevelopedResident</c>.</summary>
    public void MarkResident(string frameId, Action<string> onEvict)
        => MarkResident(frameId, 0L, onEvict);

    public void MarkResident(string frameId, long bytes, Action<string> onEvict)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        ArgumentNullException.ThrowIfNull(onEvict);
        lock (gate)
        {
            RemoveLocked(frameId);
            long storedBytes = Math.Max(0L, bytes);
            resident.Add(new ResidentFrame(frameId, storedBytes));
            residentBytes = checked(residentBytes + storedBytes);
            Trim(onEvict);
        }
    }

    /// <summary>macOS <c>removeDevelopedResident</c>.</summary>
    public void Remove(string frameId)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        lock (gate)
        {
            RemoveLocked(frameId);
        }
    }

    public void Clear()
    {
        lock (gate)
        {
            resident.Clear();
            residentBytes = 0L;
        }
    }

    private void RemoveLocked(string frameId)
    {
        for (int index = resident.Count - 1; index >= 0; index--)
        {
            ResidentFrame entry = resident[index];
            if (!string.Equals(entry.Id, frameId, StringComparison.Ordinal))
            {
                continue;
            }
            resident.RemoveAt(index);
            residentBytes -= entry.Bytes;
        }
    }

    /// <summary>macOS <c>trimDeveloped</c>.</summary>
    private void Trim(Action<string> onEvict)
    {
        while (resident.Count > Limit || residentBytes > ByteLimit)
        {
            ResidentFrame evict = resident[0];
            if (string.Equals(evict.Id, SelectedFrameId, StringComparison.Ordinal))
            {
                resident.RemoveAt(0);
                resident.Add(evict);
                if (resident.TrueForAll(
                        entry => string.Equals(
                            entry.Id,
                            SelectedFrameId,
                            StringComparison.Ordinal)))
                {
                    break;
                }
                continue;
            }
            resident.RemoveAt(0);
            residentBytes -= evict.Bytes;
            onEvict(evict.Id);
        }
    }
}
