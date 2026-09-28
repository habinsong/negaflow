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

    /// <summary>
    /// 화면이 처음 보였습니다. 그 전에 온 메시지는 시작 로고에 가려 아무도 보지 못했으므로 지금부터
    /// 다시 셉니다 — 사진이 많으면 셸을 세우는 데 몇 초가 걸려 열기 알림이 보이기도 전에 지나갔습니다.
    /// macOS 는 상태바가 먼저 떠 있어 이 차이가 없습니다.
    /// </summary>
    public void Reannounce()
    {
        lock (gate)
        {
            if (message.Length == 0)
            {
                return;
            }
            postedAt = DateTimeOffset.UtcNow;
        }
        Changed?.Invoke(this, EventArgs.Empty);
    }
}
