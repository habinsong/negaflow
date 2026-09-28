namespace Negaflow.Shell;

/// <summary>
/// 종료 저장이 실패했을 때 저장 없이 끝낼지 정합니다. macOS
/// <c>NegaflowApplicationDelegate.quitAfterFailedSave</c> 와 같습니다.
/// </summary>
/// <remarks>
/// 저장이 실패해도 종료를 무조건 막으면 작업 관리자 말고는 앱을 끌 수 없습니다. 재실행 요청은
/// 거두고, 사용자가 고르면 저장 없이 끝냅니다. 고르지 않으면 실패를 알리고 앱을 남겨 두며,
/// 다음 종료 때 다시 묻습니다.
/// </remarks>
public static class QuitAfterFailedSave
{
    /// <returns>저장 없이 종료하면 <see langword="true"/> 입니다.</returns>
    public static async Task<bool> DecideAsync(
        Action cancelRelaunch,
        Func<Task<bool>> confirmQuitWithoutSaving,
        Action reportFailure)
    {
        ArgumentNullException.ThrowIfNull(cancelRelaunch);
        ArgumentNullException.ThrowIfNull(confirmQuitWithoutSaving);
        ArgumentNullException.ThrowIfNull(reportFailure);
        cancelRelaunch();
        if (await confirmQuitWithoutSaving().ConfigureAwait(true))
        {
            return true;
        }
        reportFailure();
        return false;
    }
}
