namespace Negaflow.Shell;

/// <summary>
/// UI 스레드로 되돌아가는 유일한 통로입니다. WinUI 의 <c>DispatcherQueue</c> 를 그대로 쓰지 않고
/// 한 겹 두는 이유는, 이 정책을 XAML 없이 시험할 수 있어야 하기 때문입니다. 스레딩은 CLI 검증이
/// 절대 건드리지 못하는 부분이고, 앱에서 가장 잘 깨지는 부분이기도 합니다.
/// </summary>
public interface IUiDispatcher
{
    /// <summary>
    /// 지금 스레드가 UI 스레드인지. WinUI 의 <c>DispatcherQueue.HasThreadAccess</c> 입니다.
    /// </summary>
    bool HasThreadAccess { get; }

    /// <summary>
    /// UI 스레드에서 실행하도록 넣습니다. <c>false</c> 는 **큐에 들어가지 못했다**는 뜻이며,
    /// 창이 닫혀 큐가 종료된 뒤가 대표적입니다. 이 경우 콜백은 영영 실행되지 않으므로 호출자는
    /// 반환값을 반드시 확인해야 합니다. <c>true</c> 는 큐에 들어갔다는 뜻일 뿐 실행됐다는 뜻이
    /// 아닙니다.
    /// </summary>
    bool TryEnqueue(Action callback);
}
