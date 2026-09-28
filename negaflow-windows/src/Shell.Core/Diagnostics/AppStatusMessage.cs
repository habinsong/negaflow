namespace Negaflow.Shell.Diagnostics;

/// <summary>
/// 앱 전역 상태 메시지입니다. macOS <c>StatusMessageCenter</c> 자리로, 하단 상태바 가운데에 잠시
/// 뜹니다. 오류는 이것과 함께 <see cref="AppErrorLog"/> 에도 남깁니다(macOS <c>reportError</c>).
/// </summary>
public sealed class AppStatusMessage
{
    private readonly Lock gate = new();
    private string message = string.Empty;
    private DateTimeOffset postedAt = DateTimeOffset.MinValue;

    public static AppStatusMessage Shared { get; } = new();

    /// <summary>새 메시지가 들어왔습니다. 같은 글이 다시 와도 알립니다 — 다시 띄워야 합니다.</summary>
    public event EventHandler? Changed;

    public string Message
    {
        get
        {
            lock (gate)
            {
                return message;
            }
        }
    }

    /// <summary>마지막 메시지를 받은 때입니다.</summary>
    public DateTimeOffset PostedAt
    {
        get
        {
            lock (gate)
            {
                return postedAt;
            }
        }
    }

    public void Post(string text)
    {
        lock (gate)
        {
            message = (text ?? string.Empty).Trim();
            postedAt = DateTimeOffset.UtcNow;
        }
        Changed?.Invoke(this, EventArgs.Empty);
    }
}
