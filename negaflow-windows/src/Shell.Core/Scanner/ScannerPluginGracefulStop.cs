using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Negaflow.Shell;

/// <summary>
/// 스캐너 플러그인에게 <b>먼저 정상 종료를 청합니다.</b> 곧바로 죽이지 않습니다.
/// </summary>
/// <remarks>
/// **왜 필요한가**
///
/// <c>TerminateProcess</c>(= <see cref="Process.Kill(bool)"/>)는 <c>sane_cancel()</c> 을 부르지
/// 않습니다. 전송 도중에 죽은 스캐너는 헤드가 홈으로 돌아가지 못한 채 남아, 전원을 다시 넣기
/// 전까지 어떤 요청에도 답하지 않습니다.
///
/// 플러그인은 이 계약을 이미 갖추고 있습니다 — <c>negaflow-scanner-sane</c> 의
/// <c>process/cancel</c> 이 콘솔 제어 이벤트를 받아 <c>scanimage</c> 에 CTRL_BREAK → 유예 →
/// Job 종료의 3단계를 적용합니다. 보내는 쪽이 없었을 뿐입니다.
///
/// **앞서 이 자리에서 앱이 꺼졌습니다**
///
/// 콘솔이 없는 GUI 호스트는 플러그인이 만들어 둔 콘솔에 잠시 붙어야 하는데, 그 콘솔로 보낸
/// 이벤트는 <b>붙어 있는 모두</b>에게 갑니다 — 앱 자신을 포함해서. 그때
/// <c>SetConsoleCtrlHandler(NULL, TRUE)</c> 로 막았다고 여겼으나, MSDN 계약은 그것이
/// <b>CTRL+C 만</b> 무시하게 한다고 적혀 있습니다. CTRL_BREAK 는 그대로 도착해 기본 처리로
/// 프로세스를 끝냈습니다.
///
/// 그래서 <b>진짜 처리기</b>를 답니다. 실측으로 확인했습니다 — 처리기를 달고 CTRL_C 와
/// CTRL_BREAK 를 스스로에게 쏘면 둘 다 <c>handled</c> 로 삼켜지고 프로세스가 살아남습니다.
///
/// 처리기는 <b>한 번 달면 떼지 않습니다.</b> 보낸 신호가 도착하기 전에 떼면 그 사이에 기본
/// 처리가 일어나 앱이 꺼지고, 그 경합은 눈에 잘 띄지 않는 자리에서 가끔만 터집니다. GUI 앱이
/// 콘솔 Ctrl 신호로 할 일은 어차피 없습니다.
/// </remarks>
internal static class ScannerPluginGracefulStop
{
    /// <summary>
    /// 정상 종료를 청하고 기다립니다. 끝났으면 <see langword="true"/> 입니다.
    /// </summary>
    /// <param name="grace">
    /// 기다릴 <b>상한</b>입니다. 프로세스가 끝나는 즉시 돌아오므로 보통은 이보다 훨씬 짧습니다.
    /// </param>
    /// <remarks>
    /// 기다리는 동안 스레드를 잡지 않습니다. 이 함수는 취소 처리의 이어짐에서 불리고, 그
    /// 이어짐은 UI 스레드일 수 있습니다.
    /// </remarks>
    internal static async Task<bool> TryStopAsync(Process process, TimeSpan grace)
    {
        ArgumentNullException.ThrowIfNull(process);
        if (process.HasExited)
        {
            return true;
        }
        if (!RequestConsoleBreak(process.Id))
        {
            return false;
        }
        using CancellationTokenSource deadline = new(grace);
        try
        {
            await process.WaitForExitAsync(deadline.Token).ConfigureAwait(false);
            return true;
        }
        catch (OperationCanceledException)
        {
            return false;
        }
        catch (SystemException)
        {
            // 이미 사라졌거나 핸들이 닫혔습니다. 부르는 쪽이 강제 종료로 넘어갑니다.
            return false;
        }
    }

    /// <summary>플러그인이 문서로 못 박은 유예의 두 배입니다.</summary>
    /// <remarks>
    /// 플러그인 <c>process/cancel.h</c> 의 실측 주석: OpticFilm 8100 에서 스캔 6초 지점에
    /// CTRL_BREAK 를 보내면 <c>scanimage</c> 가 <b>6,890 ms</b> 만에 끝납니다 — 진행 중인
    /// <c>sane_read</c> 가 끝나기를 기다리고 <c>sane_cancel</c> 이 헤드를 홈으로 돌리는 시간이
    /// 그 안에 있습니다. 플러그인은 그 위에 15 초를 잡았고, 호스트는 그 뒤 플러그인 자신이
    /// Job 을 정리하고 끝나는 시간까지 기다려야 하므로 한 번 더 줍니다.
    ///
    /// 줄이면 그 한가운데에서 죽이게 되고, 그것이 바로 고치려는 고장입니다.
    /// </remarks>
    internal static TimeSpan DefaultGrace { get; } = TimeSpan.FromSeconds(30);

    private static bool RequestConsoleBreak(int processId)
    {
        if (!EnsureOwnHandlerInstalled())
        {
            // 우리를 지킬 수 없으면 보내지 않습니다. 강제 종료가 스캐너를 물리게 하더라도
            // 앱이 꺼지는 것보다는 낫습니다.
            return false;
        }
        // 우리에게 콘솔이 있으면 먼저 놓습니다 - `AttachConsole` 은 이미 붙어 있으면 실패합니다.
        _ = FreeConsole();
        if (!AttachConsole((uint)processId))
        {
            return false;
        }
        bool sent;
        try
        {
            sent = GenerateConsoleCtrlEvent(CtrlBreakEvent, 0U);
        }
        finally
        {
            _ = FreeConsole();
        }
        return sent;
    }

    private static readonly Lock HandlerGate = new();

    /// <summary>떼지 않고 남겨 두는 처리기입니다. 대리자를 붙들어야 GC 가 걷어가지 않습니다.</summary>
    private static ConsoleCtrlDelegate? installedHandler;

    private static bool EnsureOwnHandlerInstalled()
    {
        lock (HandlerGate)
        {
            if (installedHandler is not null)
            {
                return true;
            }
            ConsoleCtrlDelegate handler = OnConsoleCtrl;
            if (!SetConsoleCtrlHandler(handler, true))
            {
                return false;
            }
            installedHandler = handler;
            return true;
        }
    }

    /// <summary>
    /// 우리가 보낸 신호를 우리가 삼킵니다. <see langword="true"/> 를 돌려주면 기본 처리(종료)가
    /// 일어나지 않습니다.
    /// </summary>
    /// <remarks>
    /// 창 닫기·로그오프·시스템 종료는 <see langword="false"/> 로 흘려보냅니다 — 그것까지
    /// 삼키면 사용자가 컴퓨터를 끄려 할 때 앱이 버팁니다.
    /// </remarks>
    private static bool OnConsoleCtrl(uint type) =>
        type is CtrlCEvent or CtrlBreakEvent;

    private const uint CtrlCEvent = 0U;
    private const uint CtrlBreakEvent = 1U;

    private delegate bool ConsoleCtrlDelegate(uint type);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AttachConsole(uint processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FreeConsole();

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetConsoleCtrlHandler(
        ConsoleCtrlDelegate? handlerRoutine,
        [MarshalAs(UnmanagedType.Bool)] bool add);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GenerateConsoleCtrlEvent(uint ctrlEvent, uint processGroupId);
}
