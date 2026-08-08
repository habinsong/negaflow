using Microsoft.UI.Dispatching;

namespace Negaflow.Shell;

/// <summary>
/// <see cref="IUiDispatcher"/> 를 WinUI 의 <see cref="DispatcherQueue"/> 위에 올립니다.
/// </summary>
/// <remarks>
/// **UI 스레드에서 만들어야 합니다.** <c>DispatcherQueue.GetForCurrentThread()</c> 는 다른
/// 스레드에서 <c>null</c> 을 돌려줍니다. 일단 만들어 두면 큐 자체는 agile 이라 워커 스레드에서
/// 그대로 써도 됩니다.
/// </remarks>
public sealed class DispatcherQueueUiDispatcher : IUiDispatcher
{
    private readonly DispatcherQueue queue;

    private DispatcherQueueUiDispatcher(DispatcherQueue queue)
    {
        this.queue = queue;
    }

    /// <summary>UI 스레드에서 부르십시오. 다른 스레드에서는 <c>null</c> 입니다.</summary>
    public static DispatcherQueueUiDispatcher? CaptureForCurrentThread()
    {
        DispatcherQueue? queue = DispatcherQueue.GetForCurrentThread();
        return queue is null ? null : new DispatcherQueueUiDispatcher(queue);
    }

    public bool HasThreadAccess => queue.HasThreadAccess;

    public bool TryEnqueue(Action callback)
    {
        ArgumentNullException.ThrowIfNull(callback);
        return queue.TryEnqueue(() => callback());
    }
}
