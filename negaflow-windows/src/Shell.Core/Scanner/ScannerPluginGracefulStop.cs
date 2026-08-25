using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Negaflow.Shell;

/// <summary>
/// 스캐너 플러그인에게 <b>먼저 정상 종료를 청합니다.</b> 곧바로 죽이지 않습니다.
/// </summary>
/// <remarks>
/// **왜 이것이 필요한가**
///
/// <c>TerminateProcess</c>(= <see cref="Process.Kill(bool)"/>)는 <c>sane_cancel()</c> 을 부르지
/// 않습니다. 그래서 전송 도중에 죽은 스캐너는 헤드가 홈으로 돌아가지 못한 채 남고, 전원을 다시
/// 넣기 전까지 어떤 요청에도 답하지 않습니다 — 실기에서 스캔을 취소할 때마다 장치를 찾지
/// 못하게 되던 것이 이것입니다(취소 03:05 → 탐지 실패 03:17, 전원 재투입으로 복구).
///
/// 플러그인은 이 계약을 <b>이미 갖추고 있습니다</b>. <c>negaflow-scanner-sane</c> 의
/// <c>process/cancel</c> 은 <c>CTRL_C</c>/<c>CTRL_BREAK</c>/<c>CTRL_CLOSE</c> 를 받아
/// <c>requestCancellation()</c> 을 부르고, 그것이 <c>scanimage</c> 에 CTRL_BREAK → 유예 대기 →
/// Job 종료의 3단계를 적용합니다. 보내는 쪽이 없었을 뿐입니다.
///
/// **콘솔이 없는 GUI 호스트가 어떻게 보내는가**
///
/// <c>GenerateConsoleCtrlEvent</c> 는 <b>부르는 쪽의 콘솔을 공유하는</b> 프로세스 그룹에만
/// 신호를 보냅니다. WinUI 앱에는 콘솔이 없습니다. 그런데 플러그인은 뜰 때
/// <c>ensureConsoleForCancellation()</c> 으로 <b>자기 콘솔을 만들어</b> 둡니다. 그러므로
/// 호스트가 그 콘솔에 잠시 붙으면 됩니다:
///
/// <code>
/// AttachConsole(플러그인 pid)      // 플러그인의 숨은 콘솔에 붙는다
/// SetConsoleCtrlHandler(null, TRUE) // 우리 자신은 그 이벤트를 무시한다
/// GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, 0)  // 이 콘솔의 모두에게
/// FreeConsole(); SetConsoleCtrlHandler(null, FALSE)
/// </code>
///
/// 세 번째 줄의 <c>0</c> 은 그 콘솔에 붙은 모두를 뜻하므로, 우리 자신을 먼저 귀먹게 하는
/// 두 번째 줄이 <b>반드시</b> 앞서야 합니다.
/// </remarks>
internal static class ScannerPluginGracefulStop
{
    /// <summary>
    /// 정상 종료를 청하고 기다립니다. 끝났으면 <see langword="true"/> 입니다.
    /// </summary>
    /// <param name="grace">
    /// 기다릴 <b>상한</b>입니다. 프로세스가 끝나는 즉시 돌아오므로 보통은 이보다 훨씬 짧습니다.
    /// 값은 플러그인이 문서로 못 박은 <c>kCancelGracePeriod</c>(15초)를 따릅니다 — 그쪽이
    /// <c>scanimage</c> 에게 주는 시간이고, 호스트는 그 뒤 플러그인 자신의 정리까지 기다려야
    /// 하므로 한 번 더 줍니다. 이 상한 안에 못 끝내면 그때 강제 종료합니다.
    /// </param>
    /// <remarks>
    /// **기다리는 동안 스레드를 잡지 않습니다.** 이 함수는 취소 처리의 이어짐에서 불리는데,
    /// 그 이어짐은 UI 스레드일 수 있습니다. 동기로 30초를 기다리면 그동안 창이 통째로
    /// 얼어붙습니다.
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

    /// <summary>플러그인이 문서로 못 박은 유예입니다. 호스트는 그 두 배를 기다립니다.</summary>
    /// <remarks>
    /// 플러그인 <c>process/cancel.h</c> 의 실측 주석: OpticFilm 8100 에서 스캔 6초 지점에
    /// CTRL_BREAK 를 보내면 <c>scanimage</c> 가 <b>6,890 ms</b> 만에 끝납니다 — 진행 중인
    /// <c>sane_read</c> 가 끝나기를 기다리고 <c>sane_cancel</c> 이 헤드를 홈으로 돌리는 시간이
    /// 그 안에 있습니다. 플러그인은 그 위에 15초를 잡았고, 호스트는 그 뒤 플러그인 자신이
    /// Job 을 정리하고 끝나는 시간까지 기다려야 하므로 한 번 더 줍니다.
    ///
    /// 이 값을 줄이면 그 한가운데에서 죽이게 되고, 그것이 바로 고치려는 고장입니다.
    /// </remarks>
    internal static TimeSpan DefaultGrace { get; } = TimeSpan.FromSeconds(30);

    private static bool RequestConsoleBreak(int processId)
    {
        // 우리에게 콘솔이 있으면 먼저 놓습니다 - `AttachConsole` 은 이미 붙어 있으면 실패합니다.
        _ = FreeConsole();
        if (!AttachConsole((uint)processId))
        {
            return false;
        }
        bool sent = false;
        try
        {
            // **우리부터 귀를 막습니다.** 그러지 않으면 우리가 방금 붙은 콘솔로 날아오는
            // CTRL_BREAK 를 앱 자신이 받아 그대로 끝납니다.
            if (!SetConsoleCtrlHandler(nint.Zero, true))
            {
                return false;
            }
            sent = GenerateConsoleCtrlEvent(CtrlBreakEvent, 0U);
        }
        finally
        {
            _ = FreeConsole();
            _ = SetConsoleCtrlHandler(nint.Zero, false);
        }
        return sent;
    }

    private const uint CtrlBreakEvent = 1U;

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AttachConsole(uint processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FreeConsole();

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetConsoleCtrlHandler(nint handlerRoutine, [MarshalAs(UnmanagedType.Bool)] bool add);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GenerateConsoleCtrlEvent(uint ctrlEvent, uint processGroupId);
}
