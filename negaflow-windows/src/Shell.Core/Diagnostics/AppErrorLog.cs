namespace Negaflow.Shell.Diagnostics;

/// <summary>
/// 사용자에게 보인 오류의 기록소입니다. macOS <c>AppErrorLog</c> 이식본입니다.
/// </summary>
/// <remarks>
/// macOS 주석 원문: 상태 토스트는 3초 뒤 사라지지만, 상태바 빨간 점과 진단 리포트는
/// "무엇이 왜 실패했는지" 를 나중에도 보여줘야 한다. 그 지속 상태를 여기에 담는다.
/// 상한은 macOS 와 같은 30 입니다.
/// </remarks>
public sealed class AppErrorLog
{
    private const int Capacity = 30;
    private readonly Lock gate = new();
    private readonly List<AppErrorEntry> entries = [];

    /// <summary>앱 전체가 함께 쓰는 기록소입니다. macOS 의 <c>model.errorLog</c> 자리입니다.</summary>
    public static AppErrorLog Shared { get; } = new();

    public event EventHandler? Changed;

    /// <summary>오래된 것부터 최신 차례입니다.</summary>
    public IReadOnlyList<AppErrorEntry> Entries
    {
        get
        {
            lock (gate)
            {
                return [.. entries];
            }
        }
    }

    public AppErrorEntry? Latest
    {
        get
        {
            lock (gate)
            {
                return entries.Count == 0 ? null : entries[^1];
            }
        }
    }

    public bool HasEntries
    {
        get
        {
            lock (gate)
            {
                return entries.Count != 0;
            }
        }
    }

    public void Record(string message) => Record(message, DateTimeOffset.Now);

    public void Record(string message, DateTimeOffset at)
    {
        string trimmed = (message ?? string.Empty).Trim();
        if (trimmed.Length == 0)
        {
            return;
        }
        lock (gate)
        {
            entries.Add(new AppErrorEntry(trimmed, at));
            if (entries.Count > Capacity)
            {
                entries.RemoveRange(0, entries.Count - Capacity);
            }
        }
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public void Clear()
    {
        lock (gate)
        {
            if (entries.Count == 0)
            {
                return;
            }
            entries.Clear();
        }
        Changed?.Invoke(this, EventArgs.Empty);
    }
}

public sealed record AppErrorEntry(string Message, DateTimeOffset At);
